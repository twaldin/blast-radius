"""The dependency figure, drawn as a circuit schematic.

Columns of squares left -> right — org bar, vendors, providers, regions —
with orthogonal PCB traces between them. Geometry is a pure function of the
payload (see graph_core); this file is rendering and interaction only:
hover/selection classes, keyboard-operable providers, and the staged outage
cascade, all driven by CSS classes so the blast is a transition, not a
per-frame repaint.
"""

cl import "./circuit.css";

cl {
import from .store { useRisk }
import from .graph_core { circuit_layout, circuit_channels, trace_path }

def:pub DependencyGraph() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];

    has hovered: str = "";

    nodes: any = st["nodes"];
    links: any = st["links"];
    core_id: str = (st["top"]["provider_id"] as str) if st["top"] else "";
    selected: str = st["selected"] as str;
    outage: any = st["outage"];
    hop: int = st["outage_hop"] as int;
    failed_id: str = (outage["provider_id"] as str) if outage else "";
    active: any = st["active"];

    down_set: dict = {};
    for did in (st["down_ids"] as list) { down_set[(did as str)] = True; }

    ranked_ids: list[str] = [c["provider_id"] as str for c in st["chokes"]];

    # ---- region column synthesis: strict dedupe, node lists first, then
    # edge region_codes; nothing anywhere -> no region column at all
    region_codes: list[str] = [];
    for n in nodes {
        if "regions" in (n as dict) and n["regions"] {
            for r in (n["regions"] as list) {
                rc = (r.toUpperCase() as str);
                if rc and rc not in region_codes { region_codes.append(rc); }
            }
        }
    }
    if len(region_codes) == 0 {
        for l in links {
            if "region_codes" in (l as dict) and l["region_codes"] {
                for r in (l["region_codes"] as list) {
                    rc = (r.toUpperCase() as str);
                    if rc and rc not in region_codes { region_codes.append(rc); }
                }
            }
        }
    }
    region_codes = sorted(region_codes);

    model: any = circuit_layout(nodes, links, ranked_ids, region_codes);
    placed: any = model["nodes"];
    vb_w: float = (model["w"] as float);
    vb_h: float = (model["h"] as float);

    pos: dict = {};
    for n in placed {
        pos[(n["id"] as str)] = {
            "x": n["__x"], "y": n["__y"], "h": n["__h"],
            "col": n["__col"], "bh": n["__bh"], "n": n
        };
    }

    all_links: list = [l for l in links] + [r for r in (model["rlinks"] as list)];
    chans: any = circuit_channels(all_links, pos);

    def down_now(n: any) -> bool {
        if not outage { return False; }
        if n["id"] == failed_id { return hop >= 0; }
        if n["tier"] == "vendor" { return hop >= 1 and (n["id"] as str) in down_set; }
        if n["tier"] == "org" { return hop >= 2; }
        return False;
    }

    # hover reads one path at a time; a click keeps that path lit after the
    # pointer leaves, which is what "selected" has to mean on a diagram
    focus_id: str = hovered if hovered else selected;
    lit: dict = {};
    if focus_id {
        lit[focus_id] = True;
        for l in links {
            s = (l["source"] as str);
            t = (l["target"] as str);
            if s == focus_id { lit[t] = True; }
            if t == focus_id { lit[s] = True; }
        }
    }

    def touches(l: any) -> bool {
        if not focus_id { return False; }
        return (l["source"] as str) == focus_id or (l["target"] as str) == focus_id;
    }

    def cls_for(n: any) -> str {
        c = "cir-node cir-node-" + (n["tier"] as str);
        if n["id"] == core_id { c = c + " is-core"; }
        if n["id"] == selected { c = c + " is-sel"; }
        if n["id"] == hovered { c = c + " is-hov"; }
        if down_now(n) { c = c + " is-down"; }
        if outage and not down_now(n) { c = c + " is-mute"; }
        # only the pointer dims the field; a selection stays legible in context
        if hovered and not ((n["id"] as str) in lit) { c = c + " is-dim"; }
        if n["supply_chain_risk"] or n["soc2"] == False { c = c + " is-flag"; }
        return c;
    }

    def trace_cls(l: any) -> str {
        if (l["kind"] as str) == "region" {
            if outage { return "cir-trace is-region is-mute"; }
            if touches(l) { return "cir-trace is-region is-lit"; }
            if hovered { return "cir-trace is-region is-dim"; }
            return "cir-trace is-region";
        }
        if outage {
            if (l["target"] as str) == failed_id and hop >= 1 { return "cir-trace is-hot"; }
            return "cir-trace is-mute";
        }
        if touches(l) { return "cir-trace is-lit"; }
        if hovered { return "cir-trace is-dim"; }
        return "cir-trace";
    }

    def pick(n: any) {
        if n["tier"] == "provider" { acts["select"]((n["id"] as str)); }
    }

    def meta_line(n: any) -> str {
        m = "IN-DEGREE " + str(n["inbound_degree"] or 0);
        dt = n["downtime_hours_ytd"] or 0;
        if dt > 0 { m = m + " · " + str(dt) + "H YTD"; }
        if n["soc2"] == False { m = m + " · NO SOC 2"; }
        return m;
    }

    choke_txt = "";
    if st["top"] and "share" in (st["top"] as dict) {
        choke_txt = "← CHOKEPOINT — CARRIES "
            + str(round((st["top"]["share"] as float) * 100)) + "% OF STACK";
    }

    stamp_pct = "";
    if outage {
        src: any = active if active else st["top"];
        if src and "share" in (src as dict) {
            stamp_pct = str(round((src["share"] as float) * 100)) + "%";
        }
    }

    # precompute trace rows so every drawn link has a channel and a path
    trace_rows: list = [];
    for l in all_links {
        k = (l["source"] as str) + ">" + (l["target"] as str);
        if k in (chans as dict) {
            dpath = trace_path(pos, l["source"] as str, l["target"] as str, chans[k]);
            if dpath { trace_rows.append({"k": k, "d": dpath, "cls": trace_cls(l)}); }
        }
    }

    return <div className="circuit-surface">
        <svg
            className="circuit"
            viewBox={"0 0 " + str(vb_w) + " " + str(vb_h)}
            preserveAspectRatio="xMidYMin meet"
            role="img"
            aria-label="Supply-chain dependency diagram"
        >
            {#* ------------------------------------- column guides + headers *#}
            <g className="cir-grid">
                {for c in (model["cols"] as list) {
                    <line key={"g-" + (c["title"] as str)} x1={c["x"]} y1={44} x2={c["x"]} y2={vb_h - 14} />
                }}
            </g>
            {for c in (model["cols"] as list) {
                <text key={"h-" + (c["title"] as str)} className="cir-head" x={c["x"]} y={30} textAnchor={"middle"}>
                    {c["title"]}
                </text>
            }}

            {#* ------------------------------------------------------ traces *#}
            <g className="cir-traces">
                {for t in trace_rows {
                    <path key={t["k"]} className={t["cls"]} d={t["d"]} />
                }}
            </g>

            {#* -------------------------------------------------------- nodes *#}
            {for n in placed {
                <g
                    key={n["id"]}
                    className={cls_for(n)}
                    role={"button" if n["tier"] == "provider" else "img"}
                    tabIndex={0 if n["tier"] == "provider" else -1}
                    aria-label={(n["label"] as str) + (" — select to trace its blast radius" if n["tier"] == "provider" else "")}
                    onMouseEnter={lambda { hovered = n["id"] as str; }}
                    onMouseLeave={lambda { hovered = ""; }}
                    onFocus={lambda { hovered = n["id"] as str; }}
                    onBlur={lambda { hovered = ""; }}
                    onClick={lambda { pick(n); }}
                    onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Enter" or e.key == " " { pick(n); } }}
                >
                    {#* a generous invisible target: the glyphs are far too
                        small to be a reliable click area on a projector *#}
                    <rect
                        className="hit"
                        x={(n["__x"] as float) - (n["__h"] as float) - 10}
                        y={(n["__y"] as float) - (n["__h"] as float) - 10}
                        width={((n["__h"] as float) + 10) * 2}
                        height={((n["__h"] as float) + 10) * 2}
                    />

                    {if n["tier"] == "org" {
                        <rect
                            className="shape"
                            x={(n["__x"] as float) - 7}
                            y={(n["__y"] as float) - (n["__bh"] as float) / 2}
                            width={14}
                            height={n["__bh"]}
                        />
                        <text
                            className="cir-lbl-org"
                            x={(n["__x"] as float) - 16}
                            y={(n["__y"] as float) - (n["__bh"] as float) / 2 - 8}
                            textAnchor={"end"}
                        >
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        <text
                            className="cir-lbl-orgsub"
                            x={(n["__x"] as float) - 16}
                            y={(n["__y"] as float) - (n["__bh"] as float) / 2 + 6}
                            textAnchor={"end"}
                        >ROOT ORG</text>
                        skip;
                    }}

                    {if n["tier"] == "vendor" {
                        <rect
                            className="shape"
                            x={(n["__x"] as float) - (n["__h"] as float)}
                            y={(n["__y"] as float) - (n["__h"] as float)}
                            width={(n["__h"] as float) * 2}
                            height={(n["__h"] as float) * 2}
                        />
                        <text
                            className="cir-lbl-vend"
                            x={(n["__x"] as float) - 16}
                            y={(n["__y"] as float) - 11}
                            textAnchor={"end"}
                        >
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        if n["__meta"] {
                            <text
                                className="cir-lbl-vmeta"
                                x={(n["__x"] as float) - 16}
                                y={(n["__y"] as float) - 22}
                                textAnchor={"end"}
                            >
                                {meta_line(n)}
                            </text>
                            skip;
                        }
                        if down_now(n) {
                            <text
                                className="cir-x"
                                x={(n["__x"] as float) - (n["__h"] as float) - 5}
                                y={(n["__y"] as float) + 4}
                                textAnchor={"end"}
                            >✕</text>
                            skip;
                        }
                        skip;
                    }}

                    {if n["tier"] == "provider" {
                        <rect
                            className="shape"
                            x={(n["__x"] as float) - (n["__h"] as float)}
                            y={(n["__y"] as float) - (n["__h"] as float)}
                            width={(n["__h"] as float) * 2}
                            height={(n["__h"] as float) * 2}
                        />
                        if n["id"] == core_id and choke_txt and not outage {
                            <text
                                className="cir-lbl-choke"
                                x={(n["__x"] as float) + (n["__h"] as float) + 14}
                                y={(n["__y"] as float) - 14}
                            >
                                {choke_txt}
                            </text>
                            skip;
                        }
                        <text
                            className="cir-lbl-name"
                            x={(n["__x"] as float) + (n["__h"] as float) + 14}
                            y={(n["__y"] as float) + (4 if n["__meta"] else 3)}
                        >
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        if n["__meta"] {
                            <text
                                className="cir-lbl-meta"
                                x={(n["__x"] as float) + (n["__h"] as float) + 14}
                                y={(n["__y"] as float) + 18}
                            >
                                {meta_line(n)}
                            </text>
                            skip;
                        }
                        skip;
                    }}

                    {if n["tier"] == "region" {
                        <rect
                            className="shape"
                            x={(n["__x"] as float) - (n["__h"] as float)}
                            y={(n["__y"] as float) - (n["__h"] as float)}
                            width={(n["__h"] as float) * 2}
                            height={(n["__h"] as float) * 2}
                        />
                        <text
                            className="cir-lbl-region"
                            x={(n["__x"] as float) + (n["__h"] as float) + 10}
                            y={(n["__y"] as float) + 3}
                        >
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        skip;
                    }}
                </g>
            }}

            {#* -------------------------------------------------- blast stamp *#}
            {if outage and failed_id in (pos as dict) {
                fx: float = ((pos[failed_id])["x"] as float);
                fy: float = ((pos[failed_id])["y"] as float);
                fh: float = ((pos[failed_id])["h"] as float);
                <g className="cir-stamp">
                    <rect x={fx - fh - 14 - 118} y={fy - 26} width={118} height={52} />
                    <text className="cir-stamp-pct" x={fx - fh - 14 - 59} y={fy + 4} textAnchor={"middle"}>
                        {stamp_pct}
                    </text>
                    <text className="cir-stamp-cap" x={fx - fh - 14 - 59} y={fy + 18} textAnchor={"middle"}>
                        OF STACK DOWN
                    </text>
                </g>
                skip;
            }}
        </svg>
    </div>;
}
}
