"""Resumable Browser Harness + byLLM atlas precompute for the full registry."""

import argparse;
import asyncio;
import json;
import from datetime { datetime, timezone }
import from hashlib { sha256 }
import from pathlib { Path }
import from atlas_seed {
    canonical_identity_key,
    normalize_company_identity,
    parse_seed_file
}
import from browser_discovery {
    BrowserPageResult,
    browser_read_url
}
import from contracts { ResolvedSubprocessor }
import from extract {
    extract_and_resolve,
    is_complete_disclosure
}
import from registry {
    RegistryEntry,
    VENDOR_REGISTRY
}


obj BatchResult {
    has domain: str;
    has status: str;
    has subprocessor_count: int = 0;
    has detail: str = "";
}


def parse_args -> argparse.Namespace {
    parser = argparse.ArgumentParser(
        description=(
            "Precompute committed atlas records from the 152-company registry."
        )
    );
    _ = parser.add_argument(
        "--seed-dir",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("seed/atlas"),
        help="Destination for canonical seed JSON."
    );
    _ = parser.add_argument(
        "--raw-dir",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("seed/raw"),
        help="Destination for Browser Harness text fixtures."
    );
    _ = parser.add_argument(
        "--manifest",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=None,
        help="Optional JSON array of domains; defaults to all registry entries."
    );
    _ = parser.add_argument(
        "--concurrency",
        `type=lambda (value: str) -> int { return int(value); },
        `default=10,
        help="Maximum simultaneous Browser Harness/byLLM jobs."
    );
    _ = parser.add_argument(
        "--limit",
        `type=lambda (value: str) -> int { return int(value); },
        `default=0,
        help="Process only the first N selected domains; zero means all."
    );
    _ = parser.add_argument(
        "--force",
        action="store_true",
        help="Recompute valid existing records instead of resuming."
    );
    _ = parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the selected domains without browser/model calls."
    );
    return parser.parse_args();
}


def load_selected_domains(
    manifest_path: Path | None
) -> tuple[list[str], list[str]] {
    if manifest_path is None {
        return (sorted(VENDOR_REGISTRY.keys()), []);
    }
    try {
        raw = json.loads(manifest_path.read_text()) as object;
    } except (OSError, json.JSONDecodeError) as exc {
        return (
            [],
            [f"{manifest_path}: cannot read JSON array: {str(exc)}"]
        );
    }
    if not isinstance(raw, list) {
        return ([], [f"{manifest_path}: manifest must be a JSON array"]);
    }
    domains: list[str] = [];
    errors: list[str] = [];
    seen: set[str] = set();
    for (index, value) in enumerate(raw as list[object]) {
        if not isinstance(value, str) {
            errors.append(f"{manifest_path}[{index}]: expected a domain string");
            continue;
        }
        domain: str = value.strip().casefold().removeprefix("www.");
        if domain not in VENDOR_REGISTRY {
            errors.append(f"{manifest_path}[{index}]: unknown domain {domain}");
            continue;
        }
        if domain in seen {
            errors.append(f"{manifest_path}[{index}]: duplicate domain {domain}");
            continue;
        }
        seen.add(domain);
        domains.append(domain);
    }
    return (domains, errors);
}


def _record_sort_key(record: dict[str, str]) -> str {
    return record["name"].casefold();
}


def seed_subprocessors(
    owner_name: str,
    records: list[ResolvedSubprocessor]
) -> list[dict[str, str]] {
    owner_key: str = normalize_company_identity(owner_name);
    selected: dict[str, dict[str, str]] = {};
    for record in records {
        name: str = record.canonical_name.strip();
        name_key: str = normalize_company_identity(name);
        if (
            not name_key
            or name_key == owner_key
            or name_key.startswith(owner_key + " ")
        ) {
            continue;
        }
        identity: str = canonical_identity_key(name);
        candidate: dict[str, str] = {
            "name": name,
            "purpose": record.purpose.strip(),
            "region": record.region.strip()
        };
        if identity not in selected {
            selected[identity] = candidate;
        } else {
            existing: dict[str, str] = selected[identity];
            if not existing["purpose"] and candidate["purpose"] {
                existing["purpose"] = candidate["purpose"];
            }
            if not existing["region"] and candidate["region"] {
                existing["region"] = candidate["region"];
            }
        }
    }
    output: list[dict[str, str]] = list(selected.values());
    output.sort(key=_record_sort_key);
    return output;
}


def write_seed_record(
    registry_entry: RegistryEntry,
    seed_dir: Path,
    raw_dir: Path,
    status: str,
    page_text: str,
    subprocessors: list[dict[str, str]]
) {
    seed_dir.mkdir(parents=True, exist_ok=True);
    raw_dir.mkdir(parents=True, exist_ok=True);
    raw_path: Path = raw_dir / f"{registry_entry.domain}.txt";
    digest: str = "";
    if page_text.strip() {
        _ = raw_path.write_text(page_text);
        digest = sha256(raw_path.read_bytes()).hexdigest();
    } elif raw_path.exists() {
        raw_path.unlink();
    }
    payload: dict[str, object] = {
        "domain": registry_entry.domain,
        "name": registry_entry.name,
        "subprocessor_url": registry_entry.subprocessor_url,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "raw_text_sha": digest,
        "crawl_status": status,
        "subprocessors": subprocessors if status == "ok" else []
    };
    path: Path = seed_dir / f"{registry_entry.domain}.json";
    temporary: Path = seed_dir / f".{registry_entry.domain}.json.tmp";
    _ = temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    );
    temporary.replace(path);
}


def is_resumable_seed(
    registry_entry: RegistryEntry,
    seed_dir: Path,
    raw_dir: Path
) -> bool {
    path: Path = seed_dir / f"{registry_entry.domain}.json";
    if not path.exists() {
        return False;
    }
    (record, errors) = parse_seed_file(path, raw_dir);
    return record is not None and not errors;
}


async def precompute_one(
    registry_entry: RegistryEntry,
    seed_dir: Path,
    raw_dir: Path,
    force: bool,
    semaphore: asyncio.Semaphore
) -> BatchResult {
    if not force and is_resumable_seed(
        registry_entry,
        seed_dir,
        raw_dir
    ) {
        return BatchResult(domain=registry_entry.domain, status="skipped");
    }
    async with semaphore {
        page: BrowserPageResult = await browser_read_url(
            registry_entry.subprocessor_url,
            registry_entry.flow_type
        );
        if page.status != "found" or not page.page_text.strip() {
            status: str = (
                "notfound" if page.status == "notfound" else "unreadable"
            );
            write_seed_record(
                registry_entry,
                seed_dir,
                raw_dir,
                status,
                page.page_text,
                []
            );
            return BatchResult(
                domain=registry_entry.domain,
                status=status,
                detail=page.error
            );
        }
        if not is_complete_disclosure(page.page_text) {
            write_seed_record(
                registry_entry,
                seed_dir,
                raw_dir,
                "unreadable",
                page.page_text,
                []
            );
            return BatchResult(
                domain=registry_entry.domain,
                status="unreadable",
                detail="page did not expose a complete disclosure"
            );
        }
        resolved = await asyncio.to_thread(
            extract_and_resolve,
            page.page_text,
            []
        );
        subprocessors: list[dict[str, str]] = seed_subprocessors(
            registry_entry.name,
            resolved as list[ResolvedSubprocessor]
        );
        status = "ok" if subprocessors else "unreadable";
        write_seed_record(
            registry_entry,
            seed_dir,
            raw_dir,
            status,
            page.page_text,
            subprocessors
        );
        return BatchResult(
            domain=registry_entry.domain,
            status=status,
            subprocessor_count=len(subprocessors),
            detail=(
                "" if subprocessors else "byLLM returned no subprocessors"
            )
        );
    }
}


async def run_batch(
    domains: list[str],
    seed_dir: Path,
    raw_dir: Path,
    concurrency: int,
    force: bool
) -> list[BatchResult] {
    semaphore = asyncio.Semaphore(max(1, concurrency));
    tasks: list[Coroutine[None, None, BatchResult]] = [
        precompute_one(
            VENDOR_REGISTRY[domain],
            seed_dir,
            raw_dir,
            force,
            semaphore
        )
        for domain in domains
    ];
    return list(await asyncio.gather(*tasks));
}


def main -> int {
    args = parse_args();
    manifest_path = args.manifest as Path | None;
    (domains, errors) = load_selected_domains(manifest_path);
    if args.limit > 0 {
        domains = domains[:args.limit];
    }
    if errors {
        for error in errors {
            print(f"ERROR: {error}");
        }
        return 1;
    }
    print(
        f"Selected {len(domains)} of {len(VENDOR_REGISTRY)} registry companies"
    );
    if args.dry_run {
        for domain in domains {
            print(domain);
        }
        return 0;
    }
    results: list[BatchResult] = asyncio.run(
        run_batch(
            domains,
            args.seed_dir as Path,
            args.raw_dir as Path,
            max(1, args.concurrency),
            args.force
        )
    );
    counts: dict[str, int] = {};
    for result in results {
        counts[result.status] = counts.get(result.status, 0) + 1;
        print(
            f"{result.domain}: {result.status} "
            f"({result.subprocessor_count}) {result.detail}".rstrip()
        );
    }
    print(
        "Summary: "
        + ", ".join(
            f"{status}={counts[status]}"
            for status in sorted(counts.keys())
        )
    );
    return 0;
}


with entry:__main__ {
    raise SystemExit(main());
}
