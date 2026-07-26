"""Validate researched registry batches and generate registry.jac."""

import argparse;
import json;
import re;
import from pathlib { Path }
import from urllib.parse { urlparse }


obj ResearchEntry {
    has name: str,
        domain: str,
        subprocessor_url: str,
        source_type: str,
        verified_on: str,
        notes: str,
        flow_type: str,
        recommended_flow: str,
        location: str;
}


glob REQUIRED_FIELDS: set[str] = {
    "name",
    "domain",
    "subprocessor_url",
    "source_type",
    "verified_on",
    "notes",
    "flow_type",
    "recommended_flow"
};
glob ALLOWED_SOURCE_TYPES: set[str] = {
    "official_website",
    "official_github"
};
glob ALLOWED_FLOW_TYPES: set[str] = {
    "github_raw",
    "pdf_text",
    "rendered_html",
    "rendered_html_guarded",
    "rendered_trust_center",
    "trust_center_clickthrough"
};
glob DOMAIN_PATTERN: re.Pattern[str] = re.compile(
    r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"
);


def parse_args -> argparse.Namespace {
    parser = argparse.ArgumentParser();
    _ = parser.add_argument(
        "--research-dir",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("research"),
        help="Directory containing registry-*.json batch files."
    );
    _ = parser.add_argument(
        "--output",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("registry.jac"),
        help="Generated Jac registry module."
    );
    _ = parser.add_argument(
        "--expected-count",
        `type=lambda (value: str) -> int { return int(value); },
        `default=150,
        help="Require this many unique registry entries."
    );
    _ = parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate without writing the Jac module."
    );
    return parser.parse_args();
}


def has_only_string_values(raw: dict[str, object]) -> bool {
    for field in REQUIRED_FIELDS {
        if not isinstance(raw[field], str) {
            return False;
        }
    }
    return True;
}


def load_batches(research_dir: Path) -> tuple[list[ResearchEntry], list[str]] {
    entries: list[ResearchEntry] = [];
    errors: list[str] = [];
    paths: list[Path] = sorted(list(research_dir.glob("registry-*.json")));

    if not paths {
        return ([], [f"No registry batch files found under {research_dir}"]);
    }

    for path in paths {
        try {
            raw_batch = json.loads(path.read_text()) as object;

            if not isinstance(raw_batch, list) {
                errors.append(f"{path}: top-level value must be a list");
                continue;
            }

            batch = raw_batch as list[object];
            for (index, raw_item) in enumerate(batch) {
                location: str = f"{path}:{index + 1}";
                if not isinstance(raw_item, dict) {
                    errors.append(f"{location}: entry must be an object");
                    continue;
                }

                raw = raw_item as dict[str, object];
                fields: set[str] = set(raw.keys()) as set[str];
                missing: set[str] = REQUIRED_FIELDS - fields;
                extra: set[str] = fields - REQUIRED_FIELDS;
                if missing {
                    errors.append(
                        f"{location}: missing fields {sorted(missing)}"
                    );
                }
                if extra {
                    errors.append(
                        f"{location}: unexpected fields {sorted(extra)}"
                    );
                }
                if missing or extra {
                    continue;
                }

                if not has_only_string_values(raw) {
                    errors.append(f"{location}: every field must be a string");
                    continue;
                }

                values = raw as dict[str, str];
                entries.append(
                    ResearchEntry(
                        name=values["name"].strip(),
                        domain=values["domain"].strip(),
                        subprocessor_url=values["subprocessor_url"].strip(),
                        source_type=values["source_type"].strip(),
                        verified_on=values["verified_on"].strip(),
                        notes=values["notes"].strip(),
                        flow_type=values["flow_type"].strip(),
                        recommended_flow=values["recommended_flow"].strip(),
                        location=location
                    )
                );
            }
        } except (OSError, json.JSONDecodeError) as exc {
            errors.append(f"{path}: cannot read valid JSON: {str(exc)}");
            continue;
        }
    }
    return (entries, errors);
}


def validate_entries(
    entries: list[ResearchEntry],
    expected_count: int
) -> list[str] {
    errors: list[str] = [];
    seen_domains: dict[str, str] = {};
    seen_names: dict[str, str] = {};
    seen_urls: dict[str, str] = {};

    for entry in entries {
        domain: str = entry.domain.lower();
        if not entry.name {
            errors.append(f"{entry.location}: name cannot be empty");
        }
        if domain != entry.domain {
            errors.append(
                f"{entry.location}: domain must be lowercase: {entry.domain}"
            );
        }
        if domain.startswith("www.") {
            errors.append(
                f"{entry.location}: domain must not start with www."
            );
        }
        if DOMAIN_PATTERN.fullmatch(domain) is None {
            errors.append(
                f"{entry.location}: invalid normalized domain: {domain}"
            );
        }

        parsed = urlparse(entry.subprocessor_url);
        if parsed.scheme != "https" or not parsed.netloc {
            errors.append(
                f"{entry.location}: subprocessor_url must be an absolute HTTPS URL"
            );
        }
        if entry.source_type not in ALLOWED_SOURCE_TYPES {
            errors.append(
                f"{entry.location}: source_type must be one of "
                f"{sorted(ALLOWED_SOURCE_TYPES)}"
            );
        }
        if entry.flow_type not in ALLOWED_FLOW_TYPES {
            errors.append(
                f"{entry.location}: flow_type must be one of "
                f"{sorted(ALLOWED_FLOW_TYPES)}"
            );
        }
        if not entry.recommended_flow {
            errors.append(
                f"{entry.location}: recommended_flow cannot be empty"
            );
        } elif "return notfound" not in entry.recommended_flow.lower() {
            errors.append(
                f"{entry.location}: recommended_flow must include a "
                "\"return notfound\" guard"
            );
        }
        if (
            entry.source_type == "official_github"
            and parsed.netloc != "github.com"
        ) {
            errors.append(
                f"{entry.location}: official_github source must use github.com"
            );
        }
        if entry.verified_on != "2026-07-26" {
            errors.append(
                f"{entry.location}: verified_on must be 2026-07-26 for this build"
            );
        }

        name_key: str = entry.name.casefold();
        if domain in seen_domains {
            errors.append(
                f"{entry.location}: duplicate domain {domain}; first at "
                f"{seen_domains[domain]}"
            );
        } else {
            seen_domains[domain] = entry.location;
        }
        if name_key in seen_names {
            errors.append(
                f"{entry.location}: duplicate name {entry.name}; first at "
                f"{seen_names[name_key]}"
            );
        } else {
            seen_names[name_key] = entry.location;
        }

        canonical_url: str = entry.subprocessor_url.rstrip("/").casefold();
        if canonical_url in seen_urls {
            errors.append(
                f"{entry.location}: duplicate source URL; first at "
                f"{seen_urls[canonical_url]}"
            );
        } else {
            seen_urls[canonical_url] = entry.location;
        }
    }

    if len(entries) != expected_count {
        errors.append(
            f"Expected {expected_count} entries, found {len(entries)}"
        );
    }
    return errors;
}


def jac_string(value: str) -> str {
    return json.dumps(value, ensure_ascii=False) as str;
}


def render_jac(entries: list[ResearchEntry]) -> str {
    sorted_entries: list[ResearchEntry] = sorted(
        entries,
        key=lambda (item: ResearchEntry) { item.domain; }
    );
    lines: list[str] = [
        "# Generated by scripts/build_registry.jac. Do not edit by hand.",
        "",
        "obj RegistryEntry {",
        "    has name: str;",
        "    has domain: str;",
        "    has subprocessor_url: str;",
        "    has source_type: str;",
        "    has verified_on: str;",
        "    has notes: str = \"\";",
        "    has flow_type: str = \"rendered_html_guarded\";",
        "    has recommended_flow: str = \"\";",
        "}",
        "",
        "glob VENDOR_REGISTRY: dict[str, RegistryEntry] = {"
    ];

    for entry in sorted_entries {
        lines.extend(
            [
                f"    {jac_string(entry.domain)}: RegistryEntry(",
                f"        name={jac_string(entry.name)},",
                f"        domain={jac_string(entry.domain)},",
                "        subprocessor_url="
                f"{jac_string(entry.subprocessor_url)},",
                f"        source_type={jac_string(entry.source_type)},",
                f"        verified_on={jac_string(entry.verified_on)},",
                f"        notes={jac_string(entry.notes)},",
                f"        flow_type={jac_string(entry.flow_type)},",
                "        recommended_flow="
                f"{jac_string(entry.recommended_flow)}",
                "    ),"
            ]
        );
    }
    lines.extend(
        [
            "};",
            "",
            "def registry_size -> int {",
            "    return len(VENDOR_REGISTRY);",
            "}",
            "",
            "def resolve_registry(domain: str) -> RegistryEntry | None {",
            "    normalized = domain.lower().strip().removeprefix(\"www.\");",
            "    if normalized in VENDOR_REGISTRY {",
            "        return VENDOR_REGISTRY[normalized];",
            "    }",
            "    return None;",
            "}",
            ""
        ]
    );
    return "\n".join(lines);
}


def main -> int {
    args = parse_args();
    research_dir = args.research_dir as Path;
    output = args.output as Path;
    expected_count = args.expected_count as int;
    validate_only = args.validate_only as bool;
    (entries, errors) = load_batches(research_dir);
    errors.extend(validate_entries(entries, expected_count));

    if errors {
        for error in errors {
            print(f"ERROR: {error}");
        }
        return 1;
    }
    if validate_only {
        print(f"Validated {len(entries)} entries");
    } else {
        _ = output.write_text(render_jac(entries));
        print(f"Wrote {len(entries)} entries to {output}");
    }
    return 0;
}


with entry:__main__ {
    raise SystemExit(main());
}
