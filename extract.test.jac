import asyncio;
import from time { monotonic }


test "resolves a registry URL without network access" {
    url = asyncio.run(resolve_url("www.stripe.com"));
    assert url == "https://stripe.com/legal/service-providers";
}


test "returns an empty URL on a complete registry miss" {
    url = asyncio.run(resolve_url("not-in-the-registry.example"));
    assert url == "";
}


test "canonicalizes anchor aliases deterministically" {
    assert canonicalize(
        "Amazon Web Services EMEA SARL",
        []
    ) == "Amazon Web Services";
    assert canonicalize(
        "Google Cloud Platform, Inc.",
        []
    ) == "Google Cloud";
    assert canonicalize("Azure", []) == "Microsoft Azure";
}


test "deduplicates canonical subprocessors and merges details" {
    records: list[SubprocessorRecord] = [
        SubprocessorRecord(
            name="AWS",
            purpose="Hosting",
            hosting_region=""
        ),
        SubprocessorRecord(
            name="Amazon Web Services, Inc.",
            purpose="",
            hosting_region="United States"
        ),
        SubprocessorRecord(
            name="Google Cloud Platform",
            purpose="Analytics",
            hosting_region="EU"
        )
    ];
    resolved = resolve_records(records, []);
    assert len(resolved) == 2;
    assert resolved[0].canonical_name == "Amazon Web Services";
    assert resolved[0].purpose == "Hosting";
    assert resolved[0].region == "United States";
    assert resolved[0].confidence == 1.0;
    assert resolved[0].canonical_domain == "amazon.com";
}


test "learned registry entries are unique by normalized domain" {
    LEARNED_REGISTRY.clear();
    first = remember_discovery(
        "Example",
        "www.example.com",
        ["https://example.com/legal/subprocessors"]
    );
    second = remember_discovery(
        "Example Updated",
        "example.com",
        [
            "https://example.com/legal/subprocessors",
            "https://example.com/legal/subprocessors"
        ]
    );
    assert first is not None;
    assert second is not None;
    assert len(LEARNED_REGISTRY) == 1;
    assert len(second.source_urls) == 1;
}


test "requires a complete named disclosure signal" {
    complete = (
        "Current Subprocessors\n"
        + "Amazon Web Services — hosting\n" * 30
    );
    assert is_complete_disclosure(complete);
    assert not is_complete_disclosure(
        "We may use subprocessors from time to time."
    );
}


test "discovery rejects junk inputs without raising" {
    junk: list[tuple[str, str]] = [
        ("", ""),
        ("   ", "   "),
        ("!!!", "!!!"),
        ("x" * 500, "x" * 500)
    ];
    for (domain, keyword) in junk {
        assert asyncio.run(discover_and_resolve(domain, keyword)) == "";
    }
}


test "discovery fails fast when Browser Harness is unavailable" {
    original_binary: str = os.environ.get(
        "BLAST_RADIUS_BROWSER_HARNESS",
        "browser-harness"
    );
    os.environ["BLAST_RADIUS_BROWSER_HARNESS"] = (
        "blast-radius-browser-harness-does-not-exist"
    );
    started: float = monotonic();
    result: str = asyncio.run(
        discover_and_resolve(
            "does-not-resolve.invalid",
            "Does Not Resolve"
        )
    );
    elapsed: float = monotonic() - started;
    os.environ["BLAST_RADIUS_BROWSER_HARNESS"] = original_binary;
    assert result == "";
    assert elapsed < 5.0;
}
