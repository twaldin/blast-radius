test "accepts an official company source" {
    assert is_authoritative_source(
        "https://trust.linear.app/subprocessors",
        "linear.app",
        "Linear"
    );
}


test "rejects an aggregator source" {
    assert not is_authoritative_source(
        "https://vendor-directory.example/linear-subprocessors",
        "linear.app",
        "Linear"
    );
}


test "accepts a matching official GitHub disclosure" {
    assert is_authoritative_source(
        "https://github.com/linear/subprocessors/blob/main/list.md",
        "linear.app",
        "Linear"
    );
}


test "rejects an unrelated GitHub disclosure" {
    assert not is_authoritative_source(
        "https://github.com/random-user/subprocessors/blob/main/linear.md",
        "linear.app",
        "Linear"
    );
}


test "parses a typed Browser Harness result" {
    output = (
        "browser-harness diagnostic\n"
        + BROWSER_RESULT_PREFIX
        + "{\"status\":\"found\",\"final_url\":\"https://linear.app/dpa\","
        + "\"page_text\":\"Subprocessors list\","
        + "\"source_urls\":[\"https://linear.app/dpa\"],\"error\":\"\"}"
    );
    result = parse_browser_worker_output(output);
    assert result.status == "found";
    assert result.final_url == "https://linear.app/dpa";
    assert len(result.source_urls) == 1;
}


test "reports a missing Browser Harness without spawning it" {
    original_binary: str = os.environ.get(
        "BLAST_RADIUS_BROWSER_HARNESS",
        "browser-harness"
    );
    os.environ["BLAST_RADIUS_BROWSER_HARNESS"] = (
        "blast-radius-browser-harness-does-not-exist"
    );
    assert not browser_harness_available();
    result = _run_browser_worker(
        {"action": "search", "query": "Vercel subprocessors"},
        45
    );
    os.environ["BLAST_RADIUS_BROWSER_HARNESS"] = original_binary;
    assert result.status == "error";
    assert result.error == "Browser Harness is unavailable";
}
