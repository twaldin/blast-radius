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

Rings are dynamic: vendors fill the inner ring(s), providers the outer. When
a band holds more members than a ring can space legibly, node i spills onto
sub-ring i % m (m rings for that band), up to MAX_RINGS total. With one ring
per band the radii are exactly the classic 178/292 pair, so small graphs
render identically to before.

Returns nodes carrying __a (bearing, radians), __band (0 org, 1 vendor,
2 provider) and __r (ring radius, px).
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

    # ring budget: vendors get the inner rings, providers the outer ones
    nv = len(vendors as list);
    np = len(ordered);
    mv = _rings_needed(nv, R_VENDOR, MAX_RINGS - 1);
    mp = _rings_needed(np, R_PROVIDER, MAX_RINGS - mv);
    radii = _radii(mv + mp);
    vend_radii = radii[0:mv];
    prov_radii = radii[mv:];

    # providers: heaviest starts on the right-hand axis and the band walks
    # round; overflow spills onto outer sub-rings, each re-spaced evenly
    pcounts = _bucket_counts(np, mp);
    pseen = _zeros(mp);
    prov_a: dict = {};
    prov_r: dict = {};
    i = 0;
    for p in ordered {
        ridx = i % mp;
        cnt = (pcounts[ridx] as int) or 1;
        prov_a[p["id"]] = 0.0 - 0.42 + ((pseen[ridx] as int) / cnt) * TAU;
        prov_r[p["id"]] = prov_radii[ridx];
        pseen[ridx] = (pseen[ridx] as int) + 1;
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
            bearing = (j / (len(vendors as list) or 1)) * TAU;
        }
        if bearing < 0.0 { bearing = bearing + TAU; }
        keyed.append({"node": v, "k": bearing});
        j = j + 1;
    }
    keyed = sorted(keyed, key=_by_k);

    placed: list[any] = [];
    vcounts = _bucket_counts(len(keyed), mv);
    vseen = _zeros(mv);
    i2 = 0;
    for row in keyed {
        vridx = i2 % mv;
        vcnt = (vcounts[vridx] as int) or 1;
        placed.append({
            **row["node"],
            "__a": 0.0 - 0.42 + ((vseen[vridx] as int) / vcnt) * TAU,
            "__band": 1,
            "__r": vend_radii[vridx]
        });
        vseen[vridx] = (vseen[vridx] as int) + 1;
        i2 = i2 + 1;
    }
    for p in ordered {
        placed.append({**p, "__a": prov_a[p["id"]], "__band": 2, "__r": prov_r[p["id"]]});
    }
    for n in nodes {
        if n["tier"] == "org" { placed.append({**n, "__a": 0.0, "__band": 0, "__r": 0.0}); }
    }
    return placed;
}

# ------------------------------------------------------------------ svg geometry
# Fixed 1000x560 viewBox, scaled by the browser. Pure functions only: no
# measurement, no simulation, so the figure is identical on every render.

glob CX: float = 500.0;
glob CY: float = 360.0;
glob R_VENDOR: float = 178.0;    # classic inner ring — kept when one ring per band
glob R_PROVIDER: float = 292.0;  # classic outer ring
glob R_INNER: float = 150.0;     # ladder bounds once rings multiply
glob R_OUTER: float = 330.0;
glob MAX_RINGS: int = 4;         # hard cap on total rings across both bands
glob ARC_MIN: float = 46.0;      # min arc length per node before spilling over

def _zeros(k: int) -> list[int] {
    out: list[int] = [];
    i = 0;
    while i < k { out.append(0); i = i + 1; }
    return out;
}

"""Node i of `count` lands in bucket i % m; returns per-bucket totals."""
def _bucket_counts(count: int, m: int) -> list[int] {
    out = _zeros(m);
    i = 0;
    while i < count {
        out[i % m] = (out[i % m] as int) + 1;
        i = i + 1;
    }
    return out;
}

def _ring_capacity(r: float) -> int {
    c = Math.floor(TAU * r / ARC_MIN) as int;
    return c if c > 4 else 4;
}

"""Sub-rings a band of `count` nodes needs at roughly radius r0, never more
than the ring budget left."""
def _rings_needed(count: int, r0: float, budget: int) -> int {
    m = 1;
    while m < budget and count > _ring_capacity(r0) * m { m = m + 1; }
    return m;
}

"""Radii for k rings. Two rings — the common case — reproduce the exact
classic geometry; beyond that the ladder spreads evenly to R_OUTER."""
def _radii(k: int) -> list[float] {
    if k <= 1 { return [R_PROVIDER]; }
    if k == 2 { return [R_VENDOR, R_PROVIDER]; }
    out: list[float] = [];
    i = 0;
    while i < k {
        out.append(R_INNER + (i / (k - 1)) * (R_OUTER - R_INNER));
        i = i + 1;
    }
    return out;
}

"""Distinct ring radii actually in use, inner first — the ring furniture."""
def:pub ring_radii(placed: any) -> list[float] {
    seen: dict = {};
    out: list[float] = [];
    for n in placed {
        if ((n["__band"] or 0) as int) == 0 { continue; }
        r = ((n["__r"] or 0.0) as float);
        key = str(r);
        if r > 0.0 and key not in seen {
            seen[key] = True;
            out.append(r);
        }
    }
    return sorted(out);
}

def:pub place_x(n: any) -> float {
    band = (n["__band"] or 0) as int;
    if band == 0 { return CX; }
    r = ((n["__r"] or (R_VENDOR if band == 1 else R_PROVIDER)) as float);
    return CX + Math.cos((n["__a"] or 0.0) as float) * r;
}

def:pub place_y(n: any) -> float {
    band = (n["__band"] or 0) as int;
    if band == 0 { return CY; }
    r = ((n["__r"] or (R_VENDOR if band == 1 else R_PROVIDER)) as float);
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
