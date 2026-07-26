"""Merge Browser Harness flow-audit results into registry research batches."""

import argparse;
import json;
import from pathlib { Path }


obj FlowRecord {
    has domain: str,
        flow_type: str,
        recommended_flow: str;
}


def parse_args -> argparse.Namespace {
    parser = argparse.ArgumentParser();
    _ = parser.add_argument(
        "--audit",
        `type=lambda (value: str) -> Path { return Path(value); },
        required=True,
        help="Browser Harness audit JSON file."
    );
    _ = parser.add_argument(
        "--research-dir",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("research"),
        help="Directory containing registry-*.json batch files."
    );
    return parser.parse_args();
}


def load_flows(path: Path) -> tuple[dict[str, FlowRecord], list[str]] {
    errors: list[str] = [];
    flows: dict[str, FlowRecord] = {};
    try {
        raw_items = json.loads(path.read_text()) as object;
        if not isinstance(raw_items, list) {
            return ({}, [f"{path}: top-level value must be a list"]);
        }
        for (index, raw_item) in enumerate(raw_items as list[object]) {
            location: str = f"{path}:{index + 1}";
            if not isinstance(raw_item, dict) {
                errors.append(f"{location}: audit entry must be an object");
                continue;
            }
            raw = raw_item as dict[str, object];
            domain_obj = raw.get("domain");
            flow_type_obj = raw.get("flow_type");
            recommended_flow_obj = raw.get("recommended_flow");
            if (
                not isinstance(domain_obj, str)
                or not isinstance(flow_type_obj, str)
                or not isinstance(recommended_flow_obj, str)
            ) {
                errors.append(
                    f"{location}: domain, flow_type, and recommended_flow "
                    "must be strings"
                );
                continue;
            }
            domain: str = domain_obj.strip().lower();
            if domain in flows {
                errors.append(f"{location}: duplicate domain {domain}");
                continue;
            }
            flows[domain] = FlowRecord(
                domain=domain,
                flow_type=flow_type_obj.strip(),
                recommended_flow=recommended_flow_obj.strip()
            );
        }
    } except (OSError, json.JSONDecodeError) as exc {
        errors.append(f"{path}: cannot read valid JSON: {str(exc)}");
    }
    return (flows, errors);
}


def merge_batches(
    research_dir: Path,
    flows: dict[str, FlowRecord]
) -> tuple[int, list[str]] {
    errors: list[str] = [];
    updated: int = 0;
    seen_domains: set[str] = set();
    paths: list[Path] = sorted(list(research_dir.glob("registry-*.json")));
    if not paths {
        return (0, [f"No registry batch files found under {research_dir}"]);
    }

    for path in paths {
        try {
            raw_batch_obj = json.loads(path.read_text()) as object;
            if not isinstance(raw_batch_obj, list) {
                errors.append(f"{path}: top-level value must be a list");
                continue;
            }
            raw_batch = raw_batch_obj as list[object];
            for (index, raw_item) in enumerate(raw_batch) {
                location: str = f"{path}:{index + 1}";
                if not isinstance(raw_item, dict) {
                    errors.append(f"{location}: entry must be an object");
                    continue;
                }
                raw = raw_item as dict[str, object];
                domain_obj = raw.get("domain");
                if not isinstance(domain_obj, str) {
                    errors.append(f"{location}: domain must be a string");
                    continue;
                }
                domain: str = domain_obj.strip().lower();
                if domain not in flows {
                    errors.append(f"{location}: no audited flow for {domain}");
                    continue;
                }
                flow_record: FlowRecord = flows[domain];
                raw["flow_type"] = flow_record.flow_type;
                raw["recommended_flow"] = flow_record.recommended_flow;
                seen_domains.add(domain);
                updated += 1;
            }
            _ = path.write_text(
                json.dumps(raw_batch, ensure_ascii=False, indent=2) + "\n"
            );
        } except (OSError, json.JSONDecodeError) as exc {
            errors.append(f"{path}: cannot update valid JSON: {str(exc)}");
        }
    }

    for domain in sorted(set(flows.keys()) - seen_domains) {
        errors.append(f"Audit contains unknown registry domain {domain}");
    }
    return (updated, errors);
}


def main -> int {
    args = parse_args();
    audit = args.audit as Path;
    research_dir = args.research_dir as Path;
    (flows, errors) = load_flows(audit);
    updated: int = 0;
    if not errors {
        (updated, merge_errors) = merge_batches(research_dir, flows);
        errors.extend(merge_errors);
    } else {
        updated = 0;
    }

    if errors {
        for error in errors {
            print(f"ERROR: {error}");
        }
        return 1;
    }
    print(f"Updated {updated} registry research entries");
    return 0;
}


with entry:__main__ {
    raise SystemExit(main());
}
