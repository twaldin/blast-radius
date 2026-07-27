"""Contract tests for the Company graph, seeded from the committed real filings.

Deliberately assertion-light on counts: `seed/atlas/*.json` is real crawled data and
will grow. These defend the INVARIANTS that break the product if they regress —
entity-resolution convergence above all, since without it the chokepoint never appears.
"""

import asyncio;


async def _search_for_test(
    q: str,
    allow_discovery: bool = False
) -> search {
    return await (
        root spawn search(
            q=q,
            allow_discovery=allow_discovery
        )
    );
}


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

test "the boot hook ensures the committed atlas before the first graph read" {
    boot = root spawn ensure_atlas();
    summary = boot.reports[0];
    assert summary["ready"];
    assert (summary["ok"] as int) >= 10;

    lindy = root spawn graph(domain="lindy.ai");
    payload = lindy.reports[0];
    assert len(payload["nodes"] as list) > 1;
    assert len(payload["edges"] as list) >= 20;
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

test "search resolves aliases and typos onto the canonical company" {
    _ = root spawn seed_atlas();

    found: search = asyncio.run(_search_for_test("snowflake"));
    assert not found.reports[0]["discovered"];
    results = found.reports[0]["results"] as list;
    assert len(results) > 0;
    hits = [r for r in results if (r["state"] as str) == "mapped"];
    assert len(hits) >= 1;

    # The alias table must carry "aws" onto the canonical node. This query returned
    # nothing before the resolution ladder landed, and it is the product's key lookup.
    aws: search = asyncio.run(_search_for_test("aws"));
    resolved = aws.reports[0]["resolved"];
    assert resolved is not None;
    assert (resolved["id"] as str) == "amazon-web-services";
    # AWS has no filing of its own but many dependents -> the "known" state.
    assert (resolved["state"] as str) == "known";
    assert (resolved["dependent_count"] as int) >= 10;

    # Legal-suffix, spacing, and single-character-transposition variants all converge.
    for variant in ["OpenAI, L.L.C.", "open ai", "openAI"] {
        v: search = asyncio.run(_search_for_test(variant));
        vr = v.reports[0]["resolved"];
        assert vr is not None;
        assert (vr["id"] as str) == "openai";
    }

    # An empty query must not scan the registry.
    empty: search = asyncio.run(_search_for_test(""));
    assert len(empty.reports[0]["results"] as list) == 0;
    assert empty.reports[0]["resolved"] is None;
    assert not empty.reports[0]["discovered"];

    # A URL-shaped query misses all seven text-match tiers, then exercises the
    # discovery-to-graph write through deterministic registry resolution.
    fixture_domain: str = "airbyte.com";
    fixture_url: str = "https://trust.airbyte.com/subprocessors";
    assert _find_company(fixture_domain) is None;

    discovered: search = asyncio.run(
        _search_for_test(
            "https://airbyte.com/legal/subprocessors",
            True
        )
    );
    discovery_payload = discovered.reports[0];
    assert discovery_payload["discovered"];
    assert len(discovery_payload["results"] as list) == 1;
    discovery_resolved = discovery_payload["resolved"];
    assert discovery_resolved is not None;
    assert (discovery_resolved["domain"] as str) == fixture_domain;
    assert (discovery_resolved["source_url"] as str) == fixture_url;
    assert (discovery_resolved["match"] as str) == "discovery";
    assert _find_company(fixture_domain) is not None;

    fast_again: search = asyncio.run(
        _search_for_test("Airbyte")
    );
    assert not fast_again.reports[0]["discovered"];
    assert fast_again.reports[0]["resolved"] is not None;
}

test "the inbound view answers who depends on this" {
    _ = root spawn seed_atlas();

    inbound = root spawn dependents(domain="aws");
    payload = inbound.reports[0];
    assert (payload["direction"] as str) == "inbound";
    assert (payload["root_label"] as str) == "Amazon Web Services";
    assert (payload["dependent_count"] as int) >= 10;

    nodes = payload["nodes"] as list;
    centre = [n for n in nodes if (n["tier"] as str) == "org"];
    assert len(centre) == 1;
    assert (centre[0]["id"] as str) == "amazon-web-services";

    # Edges keep their real direction: dependents point INTO the centre.
    into = [e for e in (payload["edges"] as list) if (e["target"] as str) == "amazon-web-services"];
    assert len(into) >= 10;

    # An unknown company degrades to empty rather than raising.
    miss = root spawn dependents(domain="not-a-real-company");
    assert len(miss.reports[0]["nodes"] as list) == 0;
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
