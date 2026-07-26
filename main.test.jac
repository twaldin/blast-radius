"""End-to-end assertions for the deterministic JacHammer demo graph."""

import asyncio;

async def _run_demo_expand() -> list[dict] {
    result = await (root spawn expand());
    return result.reports;
}

async def _run_demo_expand_one(vendor_id: str) -> list[dict] {
    result = await (root spawn expand_one(vendor_id=vendor_id));
    return result.reports;
}

test "builds and traverses the complete JacHammer demo graph" {
    detected = root spawn detect_vendors(
        domain="jachammer.ai",
        org_name="JacHammer"
    );
    assert detected.reports[0]["found"] == 8;

    reports = asyncio.run(_run_demo_expand());
    graph = reports[0];
    assert len(graph["nodes"]) == 14;
    assert len(graph["edges"]) == 19;

    orgs = [root -->[?:Org, domain == "jachammer.ai"]];
    assert len(orgs) == 1;
    vendors = [orgs[0] ->:Uses:->];
    assert len(vendors) == 8;
    assert len([root -->[?:Provider]]) == 5;
    assert len([root -->[?:Feature]]) == 5;
    assert sum([len([v ->:Subprocesses:->]) for v in vendors]) == 11;
    assert sum([len([v ->:Powers:->]) for v in vendors]) == 8;

    ranked = root spawn chokepoints();
    top = ranked.reports[0][0];
    assert top["provider"] == "AWS";
    assert top["vendors_affected"] == 5;
    assert top["share"] == 0.625;
    assert top["exposure"] == 5.75;

    stripe_reports = asyncio.run(_run_demo_expand_one("stripe"));
    stripe = stripe_reports[0];
    assert stripe["status"] == "cached";
    assert len(stripe["subprocessors"]) == 1;

    depth = root spawn expansion_candidates();
    depth_report = depth.reports[0];
    assert depth_report["terminal_providers"] == 3;
    assert depth_report["recommended"] == ["cloudflare"];

    outage = root spawn blast_radius(failed_provider="AWS");
    blast = outage.reports[0];
    assert len(blast["vendors_down"]) == 5;
    features = blast["features_down"] as list[str];
    assert "AI generation" in features;
    assert "payments" in features;
    assert "hosting" in features;
    assert "error monitoring" in features;

    compliance = root spawn compliance_fallout();
    fallout = compliance.reports[0];
    assert len(fallout) == 1;
    assert fallout[0]["vendor"] == "Sentry";
    assert fallout[0]["provider"] == "Fastly";
    assert fallout[0]["handles_pii"];

    summary = root spawn one_look();
    headline = summary.reports[0];
    risk = headline["biggest_risk"] as str;
    suggestion = headline["biggest_suggestion"] as str;
    assert "AWS carries 62%" in risk;
    assert "Sentry off Fastly" in suggestion;
    assert "move Vercel off AWS" in suggestion;
}
