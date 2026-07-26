"""Run the real typed byLLM extractor across every readable atlas fixture."""

import argparse;
import asyncio;
import json;
import os;
import from datetime { datetime, timezone }
import from hashlib { sha256 }
import from pathlib { Path }
import from byllm.lib { ByLLMError }
import from atlas_seed {
    canonical_identity_key,
    load_seed_directory
}
import from contracts { AtlasSeedRecord }
import from extract {
    clean_extracted_field,
    extract_subprocessors
}


obj FixtureCrosscheck {
    has domain: str;
    has fixture_sha256: str;
    has expected_count: int;
    has extracted_count: int = 0;
    has expected_names: list[str] = [];
    has extracted_names: list[str] = [];
    has missing_names: list[str] = [];
    has unexpected_names: list[str] = [];
    has exact_identity_match: bool = False;
    has error: str = "";
}


def parse_args -> argparse.Namespace {
    parser = argparse.ArgumentParser(
        description=(
            "Cross-check committed readable fixtures with the real byLLM wrapper."
        )
    );
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
    _ = parser.add_argument(
        "--manifest",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("seed/atlas-manifest.json")
    );
    _ = parser.add_argument(
        "--output",
        `type=lambda (value: str) -> Path { return Path(value); },
        `default=Path("reports/byllm-crosscheck.json")
    );
    _ = parser.add_argument(
        "--concurrency",
        `type=lambda (value: str) -> int { return int(value); },
        `default=3
    );
    _ = parser.add_argument(
        "--limit",
        `type=lambda (value: str) -> int { return int(value); },
        `default=0,
        help="Debug only: run the first N readable fixtures."
    );
    return parser.parse_args();
}


def _name_sort_key(value: str) -> str {
    return value.casefold();
}


def names_by_identity(names: list[str]) -> dict[str, str] {
    output: dict[str, str] = {};
    for raw_name in names {
        name: str = clean_extracted_field(raw_name);
        identity: str = canonical_identity_key(name);
        if name and identity and identity not in output {
            output[identity] = name;
        }
    }
    return output;
}


async def crosscheck_one(
    seed: AtlasSeedRecord,
    raw_dir: Path,
    semaphore: asyncio.Semaphore
) -> FixtureCrosscheck {
    expected_names: list[str] = [
        record.name for record in seed.subprocessors
    ];
    expected: dict[str, str] = names_by_identity(expected_names);
    fixture_path: Path = raw_dir / f"{seed.domain}.txt";
    try {
        fixture: str = fixture_path.read_text();
    } except OSError as exc {
        return FixtureCrosscheck(
            domain=seed.domain,
            fixture_sha256=seed.raw_text_sha,
            expected_count=len(expected),
            expected_names=sorted(
                list(expected.values()),
                key=_name_sort_key
            ),
            missing_names=sorted(
                list(expected.values()),
                key=_name_sort_key
            ),
            error=f"fixture read failed: {str(exc)}"
        );
    }
    async with semaphore {
        try {
            extracted_records = await asyncio.to_thread(
                extract_subprocessors,
                fixture[:80000]
            );
            extracted: dict[str, str] = names_by_identity([
                record.name for record in extracted_records
            ]);
            expected_keys: set[str] = set(expected.keys());
            extracted_keys: set[str] = set(extracted.keys());
            missing_keys: set[str] = expected_keys - extracted_keys;
            unexpected_keys: set[str] = extracted_keys - expected_keys;
            missing: list[str] = sorted([
                expected[key]
                for key in missing_keys
            ], key=_name_sort_key);
            unexpected: list[str] = sorted([
                extracted[key]
                for key in unexpected_keys
            ], key=_name_sort_key);
            return FixtureCrosscheck(
                domain=seed.domain,
                fixture_sha256=sha256(fixture.encode()).hexdigest(),
                expected_count=len(expected),
                extracted_count=len(extracted),
                expected_names=sorted(
                    list(expected.values()),
                    key=_name_sort_key
                ),
                extracted_names=sorted(
                    list(extracted.values()),
                    key=_name_sort_key
                ),
                missing_names=missing,
                unexpected_names=unexpected,
                exact_identity_match=not missing and not unexpected
            );
        } except ByLLMError as exc {
            return FixtureCrosscheck(
                domain=seed.domain,
                fixture_sha256=seed.raw_text_sha,
                expected_count=len(expected),
                expected_names=sorted(
                    list(expected.values()),
                    key=_name_sort_key
                ),
                missing_names=sorted(
                    list(expected.values()),
                    key=_name_sort_key
                ),
                error=f"{type(exc).__name__}: {str(exc)}"[:500]
            );
        } except Exception as exc {
            return FixtureCrosscheck(
                domain=seed.domain,
                fixture_sha256=seed.raw_text_sha,
                expected_count=len(expected),
                expected_names=sorted(
                    list(expected.values()),
                    key=_name_sort_key
                ),
                missing_names=sorted(
                    list(expected.values()),
                    key=_name_sort_key
                ),
                error=f"{type(exc).__name__}: {str(exc)}"[:500]
            );
        }
    }
}


async def run_crosscheck(
    seeds: list[AtlasSeedRecord],
    raw_dir: Path,
    concurrency: int
) -> list[FixtureCrosscheck] {
    semaphore = asyncio.Semaphore(max(1, concurrency));
    tasks: list[Coroutine[None, None, FixtureCrosscheck]] = [
        crosscheck_one(seed, raw_dir, semaphore)
        for seed in seeds
    ];
    return list(await asyncio.gather(*tasks));
}


def crosscheck_payload(
    results: list[FixtureCrosscheck],
    model_name: str
) -> dict[str, object] {
    fixture_hashes: str = "\n".join(
        f"{result.domain}:{result.fixture_sha256}"
        for result in results
    );
    error_count: int = len([
        result for result in results if result.error
    ]);
    exact_count: int = len([
        result for result in results if result.exact_identity_match
    ]);
    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "model": model_name,
        "input_corpus_sha256": sha256(fixture_hashes.encode()).hexdigest(),
        "readable_fixture_count": len(results),
        "completed_fixture_count": len(results) - error_count,
        "exact_identity_match_count": exact_count,
        "error_count": error_count,
        "results": [
            {
                "domain": result.domain,
                "fixture_sha256": result.fixture_sha256,
                "expected_count": result.expected_count,
                "extracted_count": result.extracted_count,
                "expected_names": result.expected_names,
                "extracted_names": result.extracted_names,
                "missing_names": result.missing_names,
                "unexpected_names": result.unexpected_names,
                "exact_identity_match": result.exact_identity_match,
                "error": result.error
            }
            for result in results
        ]
    };
}


def main -> int {
    args = parse_args();
    (all_seeds, errors) = load_seed_directory(
        args.seed_dir as Path,
        args.raw_dir as Path,
        args.manifest as Path
    );
    if errors {
        for error in errors {
            print(f"ERROR: {error}");
        }
        return 1;
    }
    seeds: list[AtlasSeedRecord] = [
        seed for seed in all_seeds if seed.crawl_status == "ok"
    ];
    if args.limit > 0 {
        seeds = seeds[:args.limit];
    }
    results: list[FixtureCrosscheck] = asyncio.run(
        run_crosscheck(
            seeds,
            args.raw_dir as Path,
            max(1, args.concurrency)
        )
    );
    model_name: str = os.environ.get(
        "BYLLM_DEFAULT_MODEL",
        "openrouter/openai/gpt-4.1-mini"
    );
    payload: dict[str, object] = crosscheck_payload(
        results,
        model_name
    );
    output: Path = args.output as Path;
    output.parent.mkdir(parents=True, exist_ok=True);
    temporary: Path = output.with_suffix(".json.tmp");
    _ = temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    );
    temporary.replace(output);
    print(
        f"Cross-checked {payload['completed_fixture_count']}/"
        f"{payload['readable_fixture_count']} readable fixtures; "
        f"exact={payload['exact_identity_match_count']}; "
        f"errors={payload['error_count']}; report={output}"
    );
    return 1 if (payload["error_count"] as int) else 0;
}


with entry:__main__ {
    raise SystemExit(main());
}
