import json;
import from hashlib { sha256 }
import from pathlib { Path }
import from tempfile { TemporaryDirectory }


def _write_test_seed(
    seed_dir: Path,
    raw_dir: Path,
    raw_text_sha: str
) -> Path {
    fixture: str = "Current subprocessors: Amazon Web Services — hosting.";
    raw_dir.mkdir(parents=True, exist_ok=True);
    (raw_dir / "example.com.txt").write_text(fixture);
    seed_dir.mkdir(parents=True, exist_ok=True);
    path: Path = seed_dir / "example.com.json";
    path.write_text(json.dumps({
        "domain": "example.com",
        "name": "Example",
        "subprocessor_url": "https://example.com/legal/subprocessors",
        "fetched_at": "2026-07-26T12:00:00+00:00",
        "raw_text_sha": raw_text_sha,
        "crawl_status": "ok",
        "subprocessors": [
            {
                "name": "Amazon Web Services",
                "purpose": "Hosting",
                "region": ""
            }
        ]
    }));
    return path;
}


test "parses a valid fixture-backed seed" {
    with TemporaryDirectory() as temp_dir {
        base: Path = Path(temp_dir);
        raw_dir: Path = base / "raw";
        fixture: bytes = (
            "Current subprocessors: Amazon Web Services — hosting."
        ).encode();
        path: Path = _write_test_seed(
            base / "atlas",
            raw_dir,
            sha256(fixture).hexdigest()
        );
        (record, errors) = parse_seed_file(path, raw_dir);
        assert errors == [];
        assert record is not None;
        assert record.domain == "example.com";
        assert len(record.subprocessors) == 1;
    }
}


test "rejects a fixture hash mismatch" {
    with TemporaryDirectory() as temp_dir {
        base: Path = Path(temp_dir);
        raw_dir: Path = base / "raw";
        path: Path = _write_test_seed(
            base / "atlas",
            raw_dir,
            "0" * 64
        );
        (record, errors) = parse_seed_file(path, raw_dir);
        assert record is None;
        assert any("does not match fixture" in error for error in errors);
    }
}


test "resolves canonical provider domains" {
    assert canonical_domain_for_name(
        "Amazon Web Services EMEA SARL"
    ) == "amazon.com";
    assert canonical_domain_for_name("Twilio Segment") == "segment.com";
    assert canonical_domain_for_name("Twilio SendGrid") == "sendgrid.com";
    assert canonical_domain_for_name("OpenAI, LLC") == "openai.com";
}


test "search ranking handles exact compact and prefix queries" {
    candidates: list[CompanyCandidate] = [
        CompanyCandidate(
            domain="openai.com",
            name="OpenAI",
            source_url="https://openai.com/policies/sub-processor-list/",
            crawl_status="ok",
            mapped=True
        ),
        CompanyCandidate(
            domain="openrouter.ai",
            name="OpenRouter",
            source_url="https://openrouter.ai/privacy",
            crawl_status="pending",
            mapped=False
        )
    ];
    assert rank_company_matches("openai.com", candidates)[0].score == 100.0;
    assert rank_company_matches("open ai", candidates)[0].domain == "openai.com";
    assert rank_company_matches("openr", candidates)[0].domain == "openrouter.ai";
}


test "search deduplicates domains and prefers mapped metadata" {
    candidates: list[CompanyCandidate] = [
        CompanyCandidate(
            domain="www.example.com",
            name="Example Pending",
            source_url="",
            crawl_status="pending",
            mapped=False
        ),
        CompanyCandidate(
            domain="example.com",
            name="Example",
            source_url="https://example.com/legal/subprocessors",
            crawl_status="ok",
            mapped=True
        )
    ];
    matches = rank_company_matches("example", candidates);
    assert len(matches) == 1;
    assert matches[0].mapped;
    assert matches[0].source_url.startswith("https://");
}


test "search tie order is deterministic" {
    candidates: list[CompanyCandidate] = [
        CompanyCandidate(domain="zeta.example", name="Acme Zeta"),
        CompanyCandidate(domain="alpha.example", name="Acme Alpha")
    ];
    matches = rank_company_matches("acme", candidates);
    assert [match.domain for match in matches] == [
        "alpha.example",
        "zeta.example"
    ];
}
