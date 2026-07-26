"""Normalize the committed Atlas seed corpus to the SPEC-V2 contract."""

import argparse;
import json;
import from datetime { datetime }
import from hashlib { sha256 }
import from pathlib { Path }
import from zoneinfo { ZoneInfo }
import from atlas_seed {
    canonical_identity_key,
    normalize_company_identity,
    normalize_company_name
}


def parse_args -> argparse.Namespace {
    parser = argparse.ArgumentParser();
    _ = parser.add_argument(
        "--seed-dir",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("seed/atlas")
    );
    _ = parser.add_argument(
        "--raw-dir",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("seed/raw")
    );
    return parser.parse_args();
}


def clean_text(value: object | None) -> str {
    return (
        " ".join(value.split())
        if isinstance(value, str)
        else ""
    );
}


def merge_detail(left: str, right: str) -> str {
    values: list[str] = [];
    for value in [left, right] {
        for part in value.split(" | ") {
            cleaned: str = part.strip();
            if cleaned and cleaned not in values {
                values.append(cleaned);
            }
        }
    }
    return " | ".join(values);
}


def normalize_timestamp(value: str) -> str {
    parsed: datetime = datetime.fromisoformat(value.replace("Z", "+00:00"));
    if parsed.tzinfo is None {
        parsed = parsed.replace(tzinfo=ZoneInfo("America/Los_Angeles"));
    }
    return parsed.isoformat();
}


def normalize_subprocessors(
    raw_value: object | None,
    owner_name: str
) -> list[dict[str, str]] {
    if not isinstance(raw_value, list) {
        return [];
    }
    owner_key: str = normalize_company_identity(owner_name);
    selected: dict[str, dict[str, str]] = {};
    for raw_item in raw_value as list[object] {
        if not isinstance(raw_item, dict) {
            continue;
        }
        raw = raw_item as dict[str, object];
        name: str = clean_text(raw.get("name"));
        if not name {
            continue;
        }
        name_key: str = normalize_company_identity(name);
        if (
            owner_key
            and (
                name_key == owner_key
                or name_key.startswith(owner_key + " ")
            )
        ) {
            continue;
        }
        identity_key: str = canonical_identity_key(name);
        if not identity_key {
            continue;
        }
        purpose: str = clean_text(raw.get("purpose"));
        region: str = clean_text(raw.get("region"));
        if identity_key not in selected {
            selected[identity_key] = {
                "name": name,
                "purpose": purpose,
                "region": region
            };
            continue;
        }
        existing: dict[str, str] = selected[identity_key];
        existing["purpose"] = merge_detail(existing["purpose"], purpose);
        existing["region"] = merge_detail(existing["region"], region);
        if (
            normalize_company_name(name),
            name.casefold()
        ) < (
            normalize_company_name(existing["name"]),
            existing["name"].casefold()
        ) {
            existing["name"] = name;
        }
    }
    rows: list[dict[str, str]] = list(selected.values());
    rows.sort(
        key=lambda (row: dict[str, str]) -> tuple[str, str] {
            return (
                normalize_company_name(row["name"]),
                row["name"].casefold()
            );
        }
    );
    return rows;
}


def finalize_seed(path: Path, raw_dir: Path) -> dict[str, object] {
    raw_value = json.loads(path.read_text()) as object;
    if not isinstance(raw_value, dict) {
        raise ValueError(f"{path}: top-level value must be an object");
    }
    raw = raw_value as dict[str, object];
    domain: str = clean_text(raw.get("domain"));
    name: str = clean_text(raw.get("name"));
    source_url: str = clean_text(raw.get("subprocessor_url"));
    status: str = clean_text(raw.get("crawl_status")) or "unreadable";
    fetched_at: str = normalize_timestamp(
        clean_text(raw.get("fetched_at"))
    );
    fixture_path: Path = raw_dir / f"{domain}.txt";
    fixture_sha: str = (
        sha256(fixture_path.read_bytes()).hexdigest()
        if fixture_path.exists()
        else ""
    );
    subprocessors: list[dict[str, str]] = (
        normalize_subprocessors(raw.get("subprocessors"), name)
        if status == "ok"
        else []
    );
    if status == "ok" and not fixture_sha {
        raise ValueError(f"{path}: ok seed is missing {fixture_path}");
    }
    if status == "ok" and not subprocessors {
        raise ValueError(f"{path}: ok seed has no third-party subprocessors");
    }
    return {
        "domain": domain,
        "name": name,
        "subprocessor_url": source_url,
        "fetched_at": fetched_at,
        "raw_text_sha": fixture_sha,
        "crawl_status": status,
        "subprocessors": subprocessors
    };
}


def finalize_directory(seed_dir: Path, raw_dir: Path) -> int {
    updated: int = 0;
    for path in sorted(list(seed_dir.glob("*.json"))) {
        record: dict[str, object] = finalize_seed(path, raw_dir);
        path.write_text(
            json.dumps(
                record,
                ensure_ascii=False,
                indent=2
            ) + "\n"
        );
        updated += 1;
    }
    return updated;
}


with entry:__main__ {
    args = parse_args();
    count: int = finalize_directory(
        args.seed_dir as Path,
        args.raw_dir as Path
    );
    print(f"Finalized {count} atlas seed records");
}
