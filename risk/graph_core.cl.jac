"""Geometry and ink for the dependency figure — circuit/schematic edition.

A free-form circuit tree: the org sits at the left, and every branch steps
out to the right in hard orthogonal elbows — horizontal out of a square,
a 90-degree bend, vertical, bend, horizontal into the next square. Depth
(BFS hop count) sets the x layer; the y packing is a dendrogram: leaves get
even slots in DFS order and every parent sits at the mean of its children,
so connected subtrees stay bundled. Region squares hang as leaves one layer
right of the first node that hosts them.

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
glob DX: float = 210.0;         # x per depth layer
glob MARGIN_L: float = 90.0;
glob MARGIN_R: float = 240.0;   # room for right-side labels (name + meta)
glob TOP: float = 48.0;
glob BOTTOM: float = 48.0;
glob PITCH: float = 38.0;
glob PITCH_DENSE: float = 26.0;
glob DENSE_AT: int = 24;        # above this: no meta lines, smaller labels
glob MIN_H: float = 720.0;
glob GRID: float = 250.0;
glob VEND_H: float = 6.5;
glob PROV_H: float = 8.0;
glob CORE_H: float = 13.0;
glob REGION_H: float = 6.5;
glob ORG_H: float = 10.0;

def _clamp(v: float, lo: float, hi: float) -> float {
    if v < lo { return lo; }
    if v > hi { return hi; }
    return v;
}

def _deg(n: any) -> float {
    return ((n["inbound_degree"] or 0) as float);
}

def _nbr_key(row: any) -> list {
    return [row["ndeg"], row["label"]];
}

def _gap_key(row: any) -> list {
    return [row["sy"], row["ty"], row["k"]];
}

def _by_y(row: any) -> float { return (row["y"] as float); }

"""Dendrogram circuit layout.

Returns {"w", "h", "dense", "guides", "nodes", "rlinks"}. Every placed node
carries __x, __y, __h (half-size), __col (x layer), __meta (show a meta
line), and label slots: __lx/__ly/__la (name x, baseline y, anchor), __lmy
(meta baseline), __lcy (choke annotation baseline), __xx/__xy/__xa (outage
✕ marker).
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

    by_id: dict = {};
    org_id = "";
    for n in nodes {
        by_id[(n["id"] as str)] = n;
        if n["tier"] == "org" { org_id = (n["id"] as str); }
    }

    # ---- DFS tree from the org, heavy neighbours first; first visit parents
    adj: dict = {};
    adj_keys: list = [];
    for l in links {
        s = (l["source"] as str);
        t = (l["target"] as str);
        if s not in adj { adj[s] = []; adj_keys.append(s); }
        (adj[s] as list).append(t);
    }
    adj_sorted: dict = {};
    for s in adj_keys {
        rows: list = [];
        for t in (adj[s] as list) {
            ndeg = 0.0;
            lab = (t as str);
            if t in by_id {
                ndeg = 0.0 - _deg(by_id[t]);
                lab = ((by_id[t])["label"] or t) as str;
            }
            rows.append({"id": t, "ndeg": ndeg, "label": lab});
        }
        rows = sorted(rows, key=_nbr_key);
        adj_sorted[s] = [r["id"] for r in rows];
    }

    visited: dict = {};
    order: list = [];
    children_of: dict = {};
    child_keys: list = [];
    stack: list = [];
    if org_id { stack.append(["", org_id]); }
    while len(stack as list) > 0 {
        item = stack.pop();
        par = (item[0] as str);
        cur = (item[1] as str);
        if cur in visited { continue; }
        visited[cur] = True;
        order.append(cur);
        if par {
            if par not in children_of { children_of[par] = []; child_keys.append(par); }
            (children_of[par] as list).append(cur);
        }
        if cur in adj_sorted {
            nbrs = (adj_sorted[cur] as list);
            ni = len(nbrs) - 1;
            while ni >= 0 {
                stack.append([cur, nbrs[ni]]);
                ni = ni - 1;
            }
        }
    }

    # ---- region links, strictly deduped on "node>region::CODE"
    # (a dict membership check + parallel list: dict comprehensions do not
    # survive the client JS compile)
    rlink_seen: dict = {};
    rlinks: list = [];
    ref_ids: dict = {};
    if len(region_codes) > 0 {
        for n in nodes {
            if n["tier"] == "org" { continue; }
            if "regions" in (n as dict) and n["regions"] {
                for r in (n["regions"] as list) {
                    rc = (r.toUpperCase() as str);
                    if rc in region_codes {
                        rkey = (n["id"] as str) + ">region::" + rc;
                        if rkey not in rlink_seen {
                            rlink_seen[rkey] = True;
                            rlinks.append({
                                "source": n["id"], "target": "region::" + rc, "kind": "region"
                            });
                        }
                        if rc not in ref_ids { ref_ids[rc] = []; }
                        (ref_ids[rc] as list).append((n["id"] as str));
                    }
                }
            }
        }
        for l in links {
            if "region_codes" in (l as dict) and l["region_codes"] {
                for r in (l["region_codes"] as list) {
                    rc = (r.toUpperCase() as str);
                    if rc in region_codes {
                        rkey = (l["target"] as str) + ">region::" + rc;
                        if rkey not in rlink_seen {
                            rlink_seen[rkey] = True;
                            rlinks.append({
                                "source": l["target"], "target": "region::" + rc, "kind": "region"
                            });
                        }
                        if rc not in ref_ids { ref_ids[rc] = []; }
                        (ref_ids[rc] as list).append((l["target"] as str));
                    }
                }
            }
        }
    }

    # ---- region squares hang as leaves off their first host in DFS order
    orphans: list = [];
    for rc in region_codes {
        code = (rc as str);
        ids: list = [];
        if code in ref_ids { ids = [x for x in (ref_ids[code] as list)]; }
        host = "";
        for oid2 in order {
            if (oid2 as str) in ids { host = (oid2 as str); break; }
        }
        if host {
            if host not in children_of { children_of[host] = []; child_keys.append(host); }
            (children_of[host] as list).append("region::" + code);
        } else {
            orphans.append("region::" + code);
        }
    }
    # companies the walk could not reach keep the tree complete
    for n in nodes {
        nid = (n["id"] as str);
        if nid not in visited { orphans.append(nid); }
    }

    # ---- depth layers for x
    col_of: dict = {};
    max_col = 0;
    for n in nodes {
        c = ((n["depth"] or 1) as int);
        if n["tier"] == "org" { c = 0; }
        if c < 0 { c = 0; }
        col_of[(n["id"] as str)] = c;
        if c > max_col { max_col = c; }
    }
    # regions sit one layer right of their host (clamped past the deepest)
    for pid2 in child_keys {
        for kid in (children_of[pid2] as list) {
            ks = (kid as str);
            if ks.startswith("region::") {
                hc = ((col_of[pid2] or 0) as int) + 1;
                col_of[ks] = hc;
                if hc > max_col { max_col = hc; }
            }
        }
    }
    for oid3 in orphans {
        os = (oid3 as str);
        if os.startswith("region::") {
            col_of[os] = max_col + 1;
        }
    }
    for oid4 in orphans {
        os4 = (oid4 as str);
        if os4.startswith("region::") {
            if ((col_of[os4]) as int) > max_col { max_col = (col_of[os4] as int); }
        }
    }

    # ---- dendrogram y: leaves take even slots in DFS order, parents sit at
    # the mean of their children (reversed pre-order visits children first)
    dense = len(nodes as list) + len(region_codes) > DENSE_AT;
    pitch = PITCH;
    if dense { pitch = PITCH_DENSE; }

    y_of: dict = {};
    slot = 0;
    seq: list = [];
    for oid7 in order { seq.append(oid7); }
    for oid8 in orphans { seq.append(oid8); }
    si2 = len(seq) - 1;
    while si2 >= 0 {
        cur2 = (seq[si2] as str);
        if cur2 in children_of {
            kids = (children_of[cur2] as list);
            total = 0.0;
            kc = 0;
            for kid3 in kids {
                ks3 = (kid3 as str);
                if ks3 in y_of {
                    total = total + ((y_of[ks3]) as float);
                    kc = kc + 1;
                }
            }
            if kc > 0 {
                y_of[cur2] = total / kc;
            } else {
                y_of[cur2] = slot;
                slot = slot + 1;
            }
        } else {
            y_of[cur2] = slot;
            slot = slot + 1;
        }
        si2 = si2 - 1;
    }

    vb_h = TOP + slot * pitch + BOTTOM;
    if vb_h < MIN_H { vb_h = MIN_H; }
    # recentre the whole packing vertically inside the viewBox
    yoff = TOP + (vb_h - TOP - BOTTOM - slot * pitch) / 2.0;

    vb_w = MARGIN_L + max_col * DX + MARGIN_R;

    guides: list = [];
    gx = GRID;
    while gx < vb_w {
        guides.append(gx);
        gx = gx + GRID;
    }

    # ---- placement + label slots
    placed: list = [];
    for cur3 in seq {
        cs = (cur3 as str);
        n: any = None;
        h = VEND_H;
        if cs.startswith("region::") {
            n = ({
                "id": cs, "label": cs[8:], "tier": "region",
                "inbound_degree": 0, "soc2": True,
                "supply_chain_risk": False, "downtime_hours_ytd": 0
            } as any);
            h = REGION_H;
        } else {
            n = (by_id[cs] as any);
            if n["tier"] == "org" { h = ORG_H; }
            if n["tier"] == "provider" { h = PROV_H; }
            if (n["id"] as str) == core_id { h = CORE_H; }
        }
        x = MARGIN_L + ((col_of[cs]) as int) * DX;
        y = yoff + ((y_of[cs]) as float) * pitch + pitch / 2.0;
        internal = cs in children_of and not cs.startswith("region::");

        # labels sit right of the square, straddling the outgoing trunk:
        # name above it, meta below; leaves centre the name on the trunk line
        lx = x + h + 10.0;
        la = "start";
        ly = y + 3.0;
        lmy = y + 15.0;
        lcy = y - 19.0;
        if internal { ly = y - 8.0; }
        placed.append({
            **n,
            "__x": x, "__y": y, "__h": h,
            "__col": ((col_of[cs]) as int), "__meta": not dense,
            "__lx": lx, "__ly": ly, "__la": la,
            "__lmy": lmy, "__lcy": lcy,
            "__xx": x - h - 6.0, "__xy": y + 3.0, "__xa": "end"
        });
    }

    return {
        "w": vb_w, "h": vb_h, "dense": dense,
        "guides": guides, "nodes": placed, "rlinks": rlinks
    };
}

"""Per-edge routing channels.

Every edge gets a private vertical channel inside the gap just left of its
target's layer (edges ordered by source y then target y), a fanned exit
along the source's right edge, and a fanned entry on the target's left
edge, so parallel fan-in steps into the square instead of merging into one
fat line. Returns "src>tgt" -> {"x", "y0off", "y1off"}.
"""
def:pub circuit_channels(links: any, pos: any) -> dict {
    by_src: dict = {};
    by_tgt: dict = {};
    src_keys: list = [];
    tgt_keys: list = [];
    gaps: dict = {};
    gap_keys: list = [];
    for l in links {
        s = (l["source"] as str);
        t = (l["target"] as str);
        if s not in (pos as dict) or t not in (pos as dict) { continue; }
        if s not in by_src { by_src[s] = []; src_keys.append(s); }
        (by_src[s] as list).append(t);
        if t not in by_tgt { by_tgt[t] = []; tgt_keys.append(t); }
        (by_tgt[t] as list).append(s);
        tc = (((pos[t])["col"]) as int);
        if tc not in gaps { gaps[tc] = []; gap_keys.append(tc); }
        (gaps[tc] as list).append(l);
    }

    # rank each endpoint's peers by the other end's y
    src_idx: dict = {};
    for s in src_keys {
        srows = [{"id": t, "y": (((pos[t])["y"]) as float)} for t in (by_src[s] as list)];
        srows = sorted(srows, key=_by_y);
        sm: dict = {};
        si = 0;
        for r in srows { sm[(r["id"] as str)] = si; si = si + 1; }
        src_idx[s] = {"order": sm, "n": si};
    }
    tgt_idx: dict = {};
    for t in tgt_keys {
        trows = [{"id": s, "y": (((pos[s])["y"]) as float)} for s in (by_tgt[t] as list)];
        trows = sorted(trows, key=_by_y);
        tm: dict = {};
        ti = 0;
        for r in trows { tm[(r["id"] as str)] = ti; ti = ti + 1; }
        tgt_idx[t] = {"order": tm, "n": ti};
    }

    chans: dict = {};
    for tc in gap_keys {
        rows = [{
            "k": (l["source"] as str) + ">" + (l["target"] as str),
            "s": (l["source"] as str),
            "t": (l["target"] as str),
            "sy": (((pos[(l["source"] as str)])["y"]) as float),
            "ty": (((pos[(l["target"] as str)])["y"]) as float)
        } for l in (gaps[tc] as list)];
        rows = sorted(rows, key=_gap_key);
        count = len(rows);
        right_x = MARGIN_L + (tc as int) * DX - 16.0;
        left_x = right_x - DX + 32.0;
        j = 0;
        for r in rows {
            s = (r["s"] as str);
            t = (r["t"] as str);
            ch = left_x + (j + 1) / (count + 1) * (right_x - left_x);

            esi = ((((src_idx[s])["order"])[t]) as int);
            esn = (((src_idx[s])["n"]) as int);
            y0 = 0.0;
            if esn > 1 {
                maxoff = (((pos[s])["h"]) as float) - 1.5;
                y0 = _clamp((esi - (esn - 1) / 2.0) * 5.0, 0.0 - maxoff, maxoff);
            }

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

"""One orthogonal trace: out of the source square's right edge, horizontal
to the edge's private channel, a hard 90-degree bend, vertical, bend, and
horizontal into the target square's left edge. Flush with both squares.
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
