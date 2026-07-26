"""Geometry and ink for the dependency figure.

Base is the data-maximalist draft: a left-to-right flow, you -> vendors ->
shared providers, circles massed by inbound degree. The silhouette is ours:
both bands are bowed into opposing arcs, so the field reads as a lens closing
on the providers rather than as three flat columns.

Everything is deterministic. Positions are a pure function of the payload, so
the figure never jitters, never settles differently between runs, and never
overlaps on a projector.
"""

glob TAU: float = 6.283185307179586;

glob INK: dict = {
    "org": "#16150f",
    "vendor": "#16150f",
    "provider": "#16150f",
    "core": "#e5231b",
    "flag": "#b07d05",
    "down": "#e5231b",
    "edge": "rgba(22,21,15,0.28)",
    "edgeSoft": "rgba(22,21,15,0.07)",
    "edgeHot": "rgba(229,35,27,0.9)",
    "ring": "rgba(22,21,15,0.14)",
    "label": "#4d4a42",
    "labelOn": "#16150f",
    "mute": "rgba(22,21,15,0.16)",
    "paper": "#f4f2ed"
};

def:pub tau() -> float { return TAU; }
def:pub ink() -> dict { return INK; }

def:pub node_radius(n: any, core_id: str, scale: float) -> float {
    if n["tier"] == "org" { return 7.5 * scale; }
    if n["tier"] == "provider" {
        deg = ((n["inbound_degree"] or 1) as float);
        base = 5.4 + 3.6 * Math.sqrt(deg);
        return (base * 1.15 if n["id"] == core_id else base) * scale;
    }
    return 5.0 * scale;
}

"""Slot order that puts the heaviest item on the centre line and alternates
outward, so the chokepoint sits in the middle of the band instead of at a
random edge."""
def _centred_order(count: int) -> list[int] {
    mid = (count - 1) / 2.0;
    order: list[int] = [];
    step = 0;
    while step <= count {
        lo = Math.floor(mid - step) as int;
        hi = Math.ceil(mid + step) as int;
        if lo >= 0 and lo < count and lo not in order { order.append(lo); }
        if hi >= 0 and hi < count and hi not in order { order.append(hi); }
        step = step + 1;
    }
    return order;
}

"""Even slots across [-1, 1]; a single item sits on the centre line."""
def _slots(count: int) -> list[float] {
    if count <= 0 { return []; }
    if count == 1 { return [0.0]; }
    out: list[float] = [];
    i = 0;
    while i < count {
        out.append(0 - 1.0 + (i / (count - 1)) * 2.0);
        i = i + 1;
    }
    return out;
}

"""Radial burst: the company sits at the centre and its stack expands out.

Providers take evenly spaced bearings around the full circle; each vendor is
placed on the circular mean of the providers it depends on, so a shared
provider visibly gathers its dependents into one wedge. Ties are fanned apart
so nothing stacks.

Returns nodes carrying __a (bearing, radians) and __band (0 org, 1 vendor,
2 provider).
"""
def:pub burst_layout(nodes: any, links: any, ranked_ids: any) -> list[any] {
    providers: any = [n for n in nodes if n["tier"] == "provider"];
    vendors: any = [n for n in nodes if n["tier"] == "vendor"];

    ordered: list[any] = [];
    for pid in ranked_ids {
        for p in providers {
            if p["id"] == pid { ordered.append(p); }
        }
    }
    for p in providers {
        if p not in ordered { ordered.append(p); }
    }

    # start the heaviest provider on the right-hand axis and walk round
    count = len(ordered);
    prov_a: dict = {};
    i = 0;
    for p in ordered {
        prov_a[p["id"]] = 0.0 - 0.42 + (i / (count or 1)) * TAU;
        i = i + 1;
    }

    # circular mean of a vendor's providers, so it sits under its own wedge
    sums: dict = {};
    for l in links {
        if l["kind"] != "subprocesses" { continue; }
        src = l["source"];
        tgt = l["target"];
        if tgt not in prov_a { continue; }
        a = prov_a[tgt] as float;
        prev = sums[src] if src in sums else [0.0, 0.0];
        sums[src] = [(prev[0] as float) + Math.cos(a), (prev[1] as float) + Math.sin(a)];
    }

    # Rank vendors by the bearing of what they depend on, then space them
    # evenly around the whole circle in that order. Placing each one *at* its
    # provider's bearing piles every AWS dependent onto one spoke; ordering by
    # it keeps the association while guaranteeing they never collide.
    keyed: list[any] = [];
    j = 0;
    for v in vendors {
        bearing = 0.0;
        if v["id"] in sums {
            s = sums[v["id"]];
            bearing = Math.atan2(s[1] as float, s[0] as float);
        } else {
            bearing = (j / (len(vendors) or 1)) * TAU;
        }
        if bearing < 0.0 { bearing = bearing + TAU; }
        keyed.append({"node": v, "k": bearing});
        j = j + 1;
    }
    keyed = sorted(keyed, key=_by_k);

    placed: list[any] = [];
    total = len(keyed) or 1;
    i2 = 0;
    for row in keyed {
        placed.append({**row["node"], "__a": 0.0 - 0.42 + (i2 / total) * TAU, "__band": 1});
        i2 = i2 + 1;
    }
    for p in ordered {
        placed.append({**p, "__a": prov_a[p["id"]], "__band": 2});
    }
    for n in nodes {
        if n["tier"] == "org" { placed.append({**n, "__a": 0.0, "__band": 0}); }
    }
    return placed;
}

# ------------------------------------------------------------------ svg geometry
# Fixed 1000x560 viewBox, scaled by the browser. Pure functions only: no
# measurement, no simulation, so the figure is identical on every render.

glob CX: float = 500.0;
glob CY: float = 360.0;
glob R_VENDOR: float = 178.0;
glob R_PROVIDER: float = 292.0;

def:pub place_x(n: any) -> float {
    band = (n["__band"] or 0) as int;
    if band == 0 { return CX; }
    r = R_VENDOR if band == 1 else R_PROVIDER;
    return CX + Math.cos((n["__a"] or 0.0) as float) * r;
}

def:pub place_y(n: any) -> float {
    band = (n["__band"] or 0) as int;
    if band == 0 { return CY; }
    r = R_VENDOR if band == 1 else R_PROVIDER;
    return CY + Math.sin((n["__a"] or 0.0) as float) * r * 0.92;
}

"""Labels flip to the outward side of the burst so they never cross it."""
def:pub label_side(n: any) -> int {
    if ((n["__band"] or 0) as int) == 0 { return 0; }
    return 1 if Math.cos((n["__a"] or 0.0) as float) >= 0.0 else 0 - 1;
}

"""Straight radial spokes. The burst is the drawing; elbows and curves both
fought it."""
def:pub trace_path(pos: any, src: str, tgt: str, core_id: str, kind: str) -> str {
    if src not in pos { return ""; }
    if tgt not in pos { return ""; }
    a = pos[src];
    b = pos[tgt];
    ax = a["x"] as float;
    ay = a["y"] as float;
    bx = b["x"] as float;
    by = b["y"] as float;
    dx = bx - ax;
    dy = by - ay;
    d = Math.sqrt(dx * dx + dy * dy);
    if d < 1.0 { return ""; }
    ra = node_radius(a["n"], core_id, 1.0) + 4.0;
    rb = node_radius(b["n"], core_id, 1.0) + 4.0;
    x0 = ax + dx / d * ra;
    y0 = ay + dy / d * ra;
    x1 = bx - dx / d * rb;
    y1 = by - dy / d * rb;
    return "M " + str(x0) + " " + str(y0) + " L " + str(x1) + " " + str(y1);
}

def _by_k(row: any) -> float {
    return row["k"] as float;
}
