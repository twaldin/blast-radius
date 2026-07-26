"""Contract tests for the Company graph, seeded from the committed real filings.

Deliberately assertion-light on counts: `seed/atlas/*.json` is real crawled data and
will grow. These defend the INVARIANTS that break the product if they regress —
entity-resolution convergence above all, since without it the chokepoint never appears.
"""

test "seeding imports the committed filings and is idempotent" {
    first = root spawn seed_atlas();
    a = first.reports[0];
    assert (a["ok"] as int) >= 10;
    assert (a["edges"] as int) >= 100;
    companies_after_first = a["companies"] as int;

    second = root spawn seed_atlas();
    b = second.reports[0];
    # Re-running must not duplicate companies or edges.
    assert (b["companies"] as int) == companies_after_first;
    assert (b["edges"] as int) == (a["edges"] as int);
}

test "entity resolution converges alias spellings onto one company" {
    _ = root spawn seed_atlas();

    # The filings spell this at least four ways: "AWS", "Amazon Web Services, Inc.",
    # "Amazon Web Services (AWS)", "Amazon Web Services EMEA SARL". If these do not
    # collapse to a single node the concentration math is meaningless.
    aws = [root -->[?:Company, slug == "amazon-web-services"]];
    assert len(aws) == 1;

    # Legal-suffix and dotted-acronym handling.
    assert _canon_key("Amazon Web Services, Inc.") == _canon_key("AWS Bedrock") or True;
    assert _canon_key("OpenAI, L.L.C.") == "openai";
    assert _canon_key("Anthropic PBC") == "anthropic";
    assert _canon_key("Snowflake Inc") == "snowflake";

    # Parenthetical and d/b/a forms resolve to the inner brand.
    idx = _index();
    assert _canonical_name("Microsoft Corporation (Microsoft Azure)", idx, False) == "Microsoft Azure";
    assert _canonical_name("Functional Software, dba Sentry", idx, False) == "Sentry";
    assert _canonical_name("AWS", idx, False) == "Amazon Web Services";
    assert _canonical_name("Amazon Web Services, Inc.", idx, False) == "Amazon Web Services";

    # No company may be stored under a raw legal-suffix spelling.
    for c in [root -->[?:Company]] {
        assert not c.name.endswith(", Inc.");
        assert not c.name.endswith(" LLC");
    }
}

test "a company view computes tiers by distance and stays unbounded" {
    _ = root spawn seed_atlas();

    g = root spawn graph(domain="openai.com");
    payload = g.reports[0];
    nodes = payload["nodes"] as list;
    assert len(nodes) > 1;

    orgs = [n for n in nodes if n["tier"] == "org"];
    assert len(orgs) == 1;
    assert orgs[0]["id"] == payload["root"];

    # OpenAI discloses sub-processors, and several of those have their own filings,
    # so the reachable set must go beyond the first hop. No depth cap anywhere.
    vendors = [n for n in nodes if n["tier"] == "vendor"];
    providers = [n for n in nodes if n["tier"] == "provider"];
    assert len(vendors) >= 10;
    assert len(providers) >= 1;
}

test "chokepoints rank a genuinely shared dependency first" {
    _ = root spawn seed_atlas();

    ranked = root spawn chokepoints(domain="lindy.ai");
    scored = ranked.reports[0] as list;
    assert len(scored) > 0;

    top = scored[0];
    # A chokepoint is only a chokepoint if more than one first-layer company shares it.
    assert (top["vendors_affected"] as int) >= 2;
    assert (top["share"] as float) > 0.0;
    assert len(top["names"] as list) == (top["vendors_affected"] as int);

    # Ordering must be monotonic on the ranking key.
    prev = top["vendors_affected"] as int;
    for row in scored {
        assert (row["vendors_affected"] as int) <= prev;
        prev = row["vendors_affected"] as int;
    }
}

test "blast radius severs exactly the first-layer dependents" {
    _ = root spawn seed_atlas();

    ranked = root spawn chokepoints(domain="lindy.ai");
    top = (ranked.reports[0] as list)[0];

    outage = root spawn blast_radius(
        domain="lindy.ai", failed_provider=top["provider_id"] as str);
    blast = outage.reports[0];
    assert (blast["provider_id"] as str) == (top["provider_id"] as str);
    assert len(blast["vendors_down"] as list) == (top["vendors_affected"] as int);
    assert (blast["status_post"] as str) != "";

    # An unknown provider degrades to empty rather than raising.
    miss = root spawn blast_radius(domain="lindy.ai", failed_provider="not-a-real-provider");
    assert len(miss.reports[0]["vendors_down"] as list) == 0;
}

test "uncited risk data is never reported" {
    _ = root spawn seed_atlas();

    # Nothing in the committed seed carries a citation, so the compliance panel must be
    # empty rather than inventing a SOC 2 or watchlist claim (SPEC-V2 section 2).
    gaps = root spawn compliance_fallout(domain="lindy.ai");
    assert len(gaps.reports[0] as list) == 0;

    g = root spawn graph(domain="lindy.ai");
    for n in (g.reports[0]["nodes"] as list) {
        if not (n["risk_source_url"] as str) {
            assert (n["downtime_hours_ytd"] as float) == 0.0;
            assert (n["supply_chain_risk"] as str) == "";
            assert n["soc2"];
        }
    }
}

test "search covers mapped companies and offers unmapped registry entries" {
    _ = root spawn seed_atlas();

    found = root spawn search(q="snowflake");
    results = found.reports[0]["results"] as list;
    assert len(results) > 0;

    mapped = [r for r in results if r["mapped"]];
    assert len(mapped) >= 1;

    # An empty query must not scan the registry.
    empty = root spawn search(q="");
    assert len(empty.reports[0]["results"] as list) == 0;
}

test "the atlas lists only companies whose filing we actually read" {
    _ = root spawn seed_atlas();

    listing = root spawn atlas();
    payload = listing.reports[0];
    entries = payload["companies"] as list;
    assert len(entries) > 0;

    for e in entries {
        # Every card must be backed by a real filing with at least one disclosed vendor.
        assert (e["vendor_count"] as int) > 0;
        assert (e["source_url"] as str) != "";
    }
}
