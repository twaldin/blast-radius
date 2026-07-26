"""Shared geometry and ink for both graph surfaces.

Layout is contagion's radial idea — the chokepoint is the centre, everything
orbits it — rendered in the Swiss memo's language: hairline curves, solid ink
nodes, one red. Positions are deterministic so nothing drifts on a projector.
"""

glob TAU: float = 6.283185307179586;

glob INK: dict = {
    "org": "#16150f",
    "vendor": "#fbfaf7",
    "vendorEdge": "#16150f",
    "provider": "#16150f",
    "core": "#e5231b",
    "flag": "#b07d05",
    "edge": "rgba(22,21,15,0.26)",
    "edgeSoft": "rgba(22,21,15,0.10)",
    "edgeHot": "rgba(229,35,27,0.85)",
    "down": "#e5231b",
    "label": "#4d4a42",
    "labelOn": "#16150f",
    "mute": "rgba(22,21,15,0.18)"
};

def:pub tau() -> float {
    return TAU;
}

def:pub ink() -> dict {
    return INK;
}

def:pub node_radius(n: any, core_id: str, scale: float) -> float {
    if n["id"] == core_id { return 26.0 * scale; }
    if n["tier"] == "provider" {
        deg = ((n["inbound_degree"] or 1) as float);
        return (7.0 + 3.4 * Math.sqrt(deg)) * scale;
    }
    if n["tier"] == "org" { return 11.0 * scale; }
    return 6.5 * scale;
}

"""Place every node on a ring keyed to the provider it depends on.

Vendors inherit the angle of their first provider, so each provider pulls its
dependents into a visible spoke and the shared one is visibly overloaded.
"""
def:pub radial_layout(nodes: any, links: any, core_id: str) -> list[any] {
    providers: any = [n for n in nodes if n["tier"] == "provider" and n["id"] != core_id];
    vendors: any = [n for n in nodes if n["tier"] == "vendor"];

    angle_of: dict = {};
    pcount = len(providers);
    i = 0;
    for p in providers {
        angle_of[p["id"]] = ((i / pcount) * TAU - TAU / 4) if pcount else 0.0;
        i = i + 1;
    }
    angle_of[core_id] = 0.0;

    vendor_angle: dict = {};
    for l in links {
        if l["kind"] != "subprocesses" { continue; }
        src = l["source"];
        tgt = l["target"];
        if src in vendor_angle { continue; }
        if tgt == core_id { continue; }
        if tgt in angle_of { vendor_angle[src] = angle_of[tgt]; }
    }

    placed: list[any] = [];
    j = 0;
    vcount = len(vendors);
    for v in vendors {
        fallback = ((j / vcount) * TAU - TAU / 4) if vcount else 0.0;
        a = vendor_angle[v["id"]] if v["id"] in vendor_angle else fallback;
        a = a + ((j % 3) - 1) * 0.28;
        placed = placed + [{**v, "__a": a, "__r": 1.0}];
        j = j + 1;
    }
    for p in providers {
        placed = placed + [{**p, "__a": angle_of[p["id"]], "__r": 0.52}];
    }
    for n in nodes {
        if n["id"] == core_id { placed = placed + [{**n, "__a": 0.0, "__r": 0.0}]; }
        if n["tier"] == "org" { placed = placed + [{**n, "__a": 0 - TAU / 4, "__r": 1.32}]; }
    }
    return placed;
}
