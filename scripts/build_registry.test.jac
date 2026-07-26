def sample_entry(
    name: str,
    domain: str,
    url: str = "https://example.com/legal/subprocessors"
) -> ResearchEntry {
    return ResearchEntry(
        name=name,
        domain=domain,
        subprocessor_url=url,
        source_type="official_website",
        verified_on="2026-07-26",
        notes="Verified fixture",
        location="fixture:1"
    );
}


test "accepts one valid entry at expected count" {
    errors = validate_entries(
        [sample_entry("Example", "example.com")],
        1
    );
    assert errors == [];
}


test "rejects duplicate normalized domains" {
    errors = validate_entries(
        [
            sample_entry("Example One", "example.com"),
            sample_entry(
                "Example Two",
                "example.com",
                "https://example.com/legal/other-subprocessors"
            )
        ],
        2
    );
    assert len(errors) == 1;
    assert "duplicate domain example.com" in errors[0];
}


test "rejects non-authoritative source type" {
    entry = sample_entry("Example", "example.com");
    entry.source_type = "search_snippet";
    errors = validate_entries([entry], 1);
    assert len(errors) == 1;
    assert "source_type must be one of" in errors[0];
}


test "escapes generated Jac strings" {
    assert jac_string("quoted \"name\"") == "\"quoted \\\"name\\\"\"";
}
