"""Geometry and ink for the dependency figure — circuit/schematic edition.

Columns left -> right by BFS depth: the org bar, vendor squares, provider
squares, then one region column synthesized from node region lists. Traces
are orthogonal PCB runs — horizontal, a hard 90-degree bend, horizontal into
the target — each edge in its own channel so parallel fan-in never shares a
vertical.

Everything is deterministic. Positions are a pure function of the payload,
so the figure never jitters and never settles differently between runs.
"""

glob INK: dict = {
    "org": "#16150f",
    "vendor": "#16150f",
    "provider": "#16150f",
    "core": "#e5231b",
    "flag": "#b07d05",
    "down": "#e5231b",
    "edge": "rgba(22,21,15,0.5)",
    "edgeSoft": "rgba(22,21,15,0.07)",
    "edgeHot": "rgba(229,35,27,0.9)",
    "label": "#4d4a42",
    "labelOn": "#16150f",
    "mute": "rgba(22,21,15,0.15)",
    "paper": "#f4f2ed"
};

def:pub ink() -> dict { return INK; }

# ------------------------------------------------------------------ constants
glob COL_PITCH: float = 250.0;
glob MARGIN_L: float = 70.0;
glob MARGIN_R: float = 220.0;
glob HEADER_H: float = 64.0;
glob BOTTOM: float = 48.0;
glob PITCH: float = 38.0;
glob PITCH_DENSE: float = 24.0;
glob DENSE_AT: int = 24;
glob MIN_H: float = 720.0;
glob VEND_H: float = 6.5;
glob PROV_H: float = 8.0;
glob CORE_H: float = 13.0;
glob REGION_H: float = 6.5;
glob ORG_W: float = 7.0;

def _clamp(v: float, lo: float, hi: float) -> float {
    if v < lo { return lo; }
    if v > hi { return hi; }
    return v;
}

def _deg(n: any) -> float {
    return ((n["inbound_degree"] or 0) as float);
}

def _by_y(row: any) -> float { return (row["y"] as float); }

def _col_key(row: any) -> list {
    return [row["best"], row["rank"], row["ndeg"], row["label"]];
}

def _gap_key(row: any) -> list {
    return [row["sy"], row["ty"], row["k"]];
}

"""Rows are centred vertically in the body under the column header."""
def _row_y(row: int, count: int, pitch: float, vb_h: float) -> float {
    top = HEADER_H + (vb_h - HEADER_H - BOTTOM - count * pitch) / 2.0;
    return top + row * pitch + pitch / 2.0;
}

"""Columnar circuit layout.

Nodes land in the column of their BFS depth (org = 0). Each column is
ordered to minimise crossings: deepest column first by chokepoint rank,
then each shallower column by the row of whatever it feeds into. Region
codes (already deduped by the caller) become one final column of stroked
squares; region links connect any node whose regions list — or whose edges'
region_codes — names the code.

Returns {"w", "h", "cols", "nodes", "rlinks"}; every placed node carries
__x, __y, __h (half-size), __col, __row, __bh (org bar height), __meta
(whether the column is sparse enough for a meta line).
"""
def:pub circuit_layout(nodes: any, links: any, ranked_ids: any, region_codes: list) -> dict {
    rank: dict = {};
    ri = 0;
    for pid in ranked_ids {
        rank[(pid as str)] = ri;
        ri = ri + 1;
    }
    core_id = "";
    if len(ranked_ids as list) > 0 { core_id = (ranked_ids[0] as str); }

    org: any = None;
    by_depth: dict = {};
    max_depth = 1;
    for n in nodes {
        if n["tier"] == "org" { org = n; continue; }
        d = ((n["depth"] or 1) as int);
        if d < 1 { d = 1; }
        if d not in by_depth { by_depth[d] = []; }
        (by_depth[d] as list).append(n);
        if d > max_depth { max_depth = d; }
    }

    # order columns deepest-first so each column can sort by the row of what
    # it feeds; ties break by chokepoint rank, inbound degree, then label
    row_of: dict = {};
    ordered: dict = {};
    d = max_depth;
    while d >= 1 {
        col: list = [];
        if d in by_depth { col = [x for x in (by_depth[d] as list)]; }
        keyed: list = [];
        for n in col {
            best = 1000000.0;
            nid = (n["id"] as str);
            for l in links {
                if (l["source"] as str) == nid {
                    t = (l["target"] as str);
                    if t in row_of {
                        r = ((row_of[t]) as float);
                        if r < best { best = r; }
                    }
                }
            }
            rk = 5000.0;
            if nid in rank { rk = ((rank[nid]) as float); }
            keyed.append({
                "n": n,
                "best": best,
                "rank": rk,
                "ndeg": 0.0 - _deg(n),
                "label": ((n["label"] or "") as str)
            });
        }
        keyed = sorted(keyed, key=_col_key);
        i = 0;
        final: list = [];
        for row in keyed {
            nn = row["n"];
            row_of[(nn["id"] as str)] = i;
            final.append(nn);
            i = i + 1;
        }
        ordered[d] = final;
        d = d - 1;
    }

    # region links, strictly deduped on "node>region::CODE"
    rlink_map: dict = {};
    if len(region_codes) > 0 {
        for n in nodes {
            if n["tier"] == "org" { continue; }
            if "regions" in (n as dict) and n["regions"] {
                for r in (n["regions"] as list) {
                    rc = (r.toUpperCase() as str);
                    if rc in region_codes {
                        rlink_map[(n["id"] as str) + ">region::" + rc] = {
                            "source": n["id"], "target": "region::" + rc, "kind": "region"
                        };
                    }
                }
            }
        }
        for l in links {
            if "region_codes" in (l as dict) and l["region_codes"] {
                for r in (l["region_codes"] as list) {
                    rc = (r.toUpperCase() as str);
                    if rc in region_codes {
                        rlink_map[(l["target"] as str) + ">region::" + rc] = {
                            "source": l["target"], "target": "region::" + rc, "kind": "region"
                        };
                    }
                }
            }
        }
    }
    rlinks: list = [rlink_map[k] for k in rlink_map];

    # viewBox height comes from the tallest column; dense columns pack tighter
    has_regions = len(region_codes) > 0;
    ncols = max_depth + 1;
    if has_regions { ncols = ncols + 1; }

    tallest = 0.0;
    pitches: dict = {};
    d = 1;
    while d <= max_depth {
        c = len((ordered[d]) as list);
        p = PITCH;
        if c > DENSE_AT { p = PITCH_DENSE; }
        pitches[d] = p;
        if c * p > tallest { tallest = c * p; }
        d = d + 1;
    }
    rp = PITCH;
    if has_regions {
        if len(region_codes) > DENSE_AT { rp = PITCH_DENSE; }
        if len(region_codes) * rp > tallest { tallest = len(region_codes) * rp; }
    }
    vb_h = MIN_H;
    if HEADER_H + tallest + BOTTOM > vb_h { vb_h = HEADER_H + tallest + BOTTOM; }
    vb_w = MARGIN_L + (ncols - 1) * COL_PITCH + MARGIN_R;

    placed: list = [];
    if org {
        oedges = 0;
        oid = (org["id"] as str);
        for l in links {
            if (l["source"] as str) == oid { oedges = oedges + 1; }
        }
        bh = _clamp(26.0 + oedges * 7.0, 26.0, vb_h - HEADER_H - BOTTOM - 80.0);
        oy = HEADER_H + (vb_h - HEADER_H - BOTTOM) / 2.0;
        placed.append({
            **org,
            "__x": MARGIN_L, "__y": oy, "__h": ORG_W,
            "__col": 0, "__row": 0, "__bh": bh, "__meta": True
        });
    }
    d = 1;
    while d <= max_depth {
        col = (ordered[d] as list);
        p = ((pitches[d]) as float);
        c = len(col);
        meta = c <= DENSE_AT;
        i = 0;
        for n in col {
            h = VEND_H;
            if n["tier"] == "provider" { h = PROV_H; }
            if (n["id"] as str) == core_id { h = CORE_H; }
            placed.append({
                **n,
                "__x": MARGIN_L + d * COL_PITCH, "__y": _row_y(i, c, p, vb_h),
                "__h": h, "__col": d, "__row": i, "__bh": 0.0, "__meta": meta
            });
            i = i + 1;
        }
        d = d + 1;
    }
    if has_regions {
        rcount = len(region_codes);
        ri = 0;
        for code in region_codes {
            placed.append({
                "id": "region::" + (code as str), "label": code, "tier": "region",
                "depth": ncols - 1, "inbound_degree": 0, "soc2": True,
                "supply_chain_risk": False, "downtime_hours_ytd": 0,
                "__x": MARGIN_L + (ncols - 1) * COL_PITCH,
                "__y": _row_y(ri, rcount, rp, vb_h),
                "__h": REGION_H, "__col": ncols - 1, "__row": ri,
                "__bh": 0.0, "__meta": True
            });
            ri = ri + 1;
        }
    }

    cols: list = [{"x": MARGIN_L, "title": "ORG"}];
    d = 1;
    while d <= max_depth {
        c = len((ordered[d]) as list);
        title = "TIER " + str(d) + " — " + str(c);
        if d == 1 { title = "VENDORS — " + str(c); }
        if d == 2 { title = "PROVIDERS — " + str(c); }
        cols.append({"x": MARGIN_L + d * COL_PITCH, "title": title});
        d = d + 1;
    }
    if has_regions {
        cols.append({
            "x": MARGIN_L + (ncols - 1) * COL_PITCH,
            "title": "REGIONS — " + str(len(region_codes))
        });
    }

    return {"w": vb_w, "h": vb_h, "cols": cols, "nodes": placed, "rlinks": rlinks};
}

"""Per-edge routing channels.

Every edge gets: a private vertical channel x inside the gap just left of
its target's column (edges ordered by source y then target y), a fanned
exit offset along the source's right edge (spread along the whole bar for
the org), and a fanned entry offset on the target's left edge. Returns
"src>tgt" -> {"x", "y0off", "y1off"}.
"""
def:pub circuit_channels(links: any, pos: any) -> dict {
    by_src: dict = {};
    by_tgt: dict = {};
    gaps: dict = {};
    for l in links {
        s = (l["source"] as str);
        t = (l["target"] as str);
        if s not in (pos as dict) or t not in (pos as dict) { continue; }
        if s not in by_src { by_src[s] = []; }
        (by_src[s] as list).append(t);
        if t not in by_tgt { by_tgt[t] = []; }
        (by_tgt[t] as list).append(s);
        tc = (((pos[t])["col"]) as int);
        if tc not in gaps { gaps[tc] = []; }
        (gaps[tc] as list).append(l);
    }

    # rank each endpoint's peers by the other end's y
    src_idx: dict = {};
    for s in by_src {
        srows = [{"id": t, "y": (((pos[t])["y"]) as float)} for t in (by_src[s] as list)];
        srows = sorted(srows, key=_by_y);
        sm: dict = {};
        si = 0;
        for r in srows { sm[(r["id"] as str)] = si; si = si + 1; }
        src_idx[s] = {"order": sm, "n": si};
    }
    tgt_idx: dict = {};
    for t in by_tgt {
        trows = [{"id": s, "y": (((pos[s])["y"]) as float)} for s in (by_tgt[t] as list)];
        trows = sorted(trows, key=_by_y);
        tm: dict = {};
        ti = 0;
        for r in trows { tm[(r["id"] as str)] = ti; ti = ti + 1; }
        tgt_idx[t] = {"order": tm, "n": ti};
    }

    chans: dict = {};
    for tc in gaps {
        rows = [{
            "k": (l["source"] as str) + ">" + (l["target"] as str),
            "s": (l["source"] as str),
            "t": (l["target"] as str),
            "sy": (((pos[(l["source"] as str)])["y"]) as float),
            "ty": (((pos[(l["target"] as str)])["y"]) as float)
        } for l in (gaps[tc] as list)];
        rows = sorted(rows, key=_gap_key);
        count = len(rows);
        left_x = MARGIN_L + ((tc as int) - 1) * COL_PITCH + 16.0;
        right_x = MARGIN_L + (tc as int) * COL_PITCH - 16.0;
        j = 0;
        for r in rows {
            s = (r["s"] as str);
            t = (r["t"] as str);
            ch = left_x + (j + 1) / (count + 1) * (right_x - left_x);

            # fanned exit along the source's right edge
            esi = ((((src_idx[s])["order"])[t]) as int);
            esn = (((src_idx[s])["n"]) as int);
            y0 = 0.0;
            if esn > 1 {
                bh = (((pos[s])["bh"]) as float);
                step = 5.0;
                maxoff = (((pos[s])["h"]) as float) - 1.5;
                if bh > 0.0 {
                    step = (bh - 20.0) / (esn - 1);
                    if step > 15.0 { step = 15.0; }
                    maxoff = bh / 2.0 - 8.0;
                }
                y0 = _clamp((esi - (esn - 1) / 2.0) * step, 0.0 - maxoff, maxoff);
            }

            # fanned entry on the target's left edge
            eti = ((((tgt_idx[t])["order"])[s]) as int);
            etn = (((tgt_idx[t])["n"]) as int);
            y1 = 0.0;
            if etn > 1 {
                maxin = (((pos[t])["h"]) as float) - 2.0;
                y1 = _clamp((eti - (etn - 1) / 2.0) * 6.0, 0.0 - maxin, maxin);
            }

            chans[(r["k"] as str)] = {"x": ch, "y0off": y0, "y1off": y1};
            j = j + 1;
        }
    }
    return chans;
}

"""One orthogonal trace: right edge of source, hard bend in the edge's
private channel, into the left edge of the target. Flush with the squares.
"""
def:pub trace_path(pos: any, src: str, tgt: str, chan: any) -> str {
    if src not in (pos as dict) or tgt not in (pos as dict) { return ""; }
    a = pos[src];
    b = pos[tgt];
    x0 = ((a["x"]) as float) + ((a["h"]) as float);
    y0 = ((a["y"]) as float) + ((chan["y0off"]) as float);
    x1 = ((b["x"]) as float) - ((b["h"]) as float);
    y1 = ((b["y"]) as float) + ((chan["y1off"]) as float);
    if x1 <= x0 + 2.0 { return f"M {x0} {y0} L {x1} {y1}"; }
    ch = _clamp(((chan["x"]) as float), x0 + 4.0, x1 - 4.0);
    return f"M {x0} {y0} H {ch} V {y1} H {x1}";
}
