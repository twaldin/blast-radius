"""The dependency figure, drawn as SVG.

This used to run on react-force-graph. That was the wrong tool: every position
here is computed exactly, so a physics engine bought us nothing and cost a
great deal -- it re-seeded the simulation on every render, swallowed wheel
events, and repainted the whole canvas per frame, which is what produced the
flashing and the clipped animation.

Plain SVG instead. Deterministic geometry, real DOM nodes for hover and click,
and CSS transitions for the outage choreography.

Flow and massing follow the data-maximalist draft; the orthogonal traces,
squares and blast treatment follow the Swiss memo. The two bands bow toward
each other so the field pinches at the shared provider.
"""

cl {
import from .store { useRisk }
import from .graph_core { burst_layout, node_radius, place_x, place_y, label_side, trace_path, ring_radii }

glob VB_W: float = 1000.0;
glob VB_H: float = 720.0;

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
    down_ids: any = st["down_ids"];
    failed_id: str = (outage["provider_id"] as str) if outage else "";
    active: any = st["active"];

    ranked_ids: list[str] = [c["provider_id"] as str for c in st["chokes"]];
    placed: any = burst_layout(nodes, links, ranked_ids);

    pos: dict = {};
    for n in placed {
        pos[n["id"]] = {"x": place_x(n), "y": place_y(n), "n": n};
    }

    vendor_n: int = len([n for n in nodes if n["tier"] == "vendor"]);
    provider_n: int = len([n for n in nodes if n["tier"] == "provider"]);

    def down_now(n: any) -> bool {
        if not outage { return False; }
        if n["id"] == failed_id { return hop >= 0; }
        if n["tier"] == "vendor" { return hop >= 1 and (down_ids.includes(n["id"]) as bool); }
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
            s = l["source"] as str;
            t = l["target"] as str;
            if s == focus_id { lit[t] = True; }
            if t == focus_id { lit[s] = True; }
        }
    }

    def touches(l: any) -> bool {
        if not focus_id { return False; }
        return (l["source"] as str) == focus_id or (l["target"] as str) == focus_id;
    }

    def cls_for(n: any) -> str {
        c = "gnode gnode-" + (n["tier"] as str);
        if n["id"] == core_id { c = c + " is-core"; }
        if n["id"] == selected { c = c + " is-sel"; }
        if n["id"] == hovered { c = c + " is-hov"; }
        if down_now(n) { c = c + " is-down"; }
        if outage and not down_now(n) { c = c + " is-mute"; }
        # only the pointer dims the field; a selection stays legible in context
        if hovered and not (n["id"] in lit) { c = c + " is-dim"; }
        if n["supply_chain_risk"] or (not n["soc2"]) { c = c + " is-flag"; }
        return c;
    }

    def trace_cls(l: any) -> str {
        if outage {
            if (l["target"] as str) == failed_id and hop >= 1 { return "trace is-hot"; }
            return "trace is-mute";
        }
        if touches(l) { return "trace is-lit"; }
        if hovered { return "trace is-dim"; }
        return "trace";
    }

    def pick(n: any) -> None {
        if n["tier"] == "provider" { acts["select"](n["id"] as str); }
    }
    return <div className="graph-surface">
        <svg className="fig" viewBox={"0 0 " + str(VB_W) + " " + str(VB_H)} preserveAspectRatio="xMidYMid meet">
            {#* ------------------------------------------- ring furniture *#}
            <g className="fig-furniture">
                {for rr in ring_radii(placed) {
                    <ellipse key={"ring-" + str(rr)} className="ring" cx={500} cy={360} rx={rr} ry={rr * 0.92} />
                }}
            </g>

            {#* ------------------------------- affected wedges during a blast *#}
            {if outage and hop >= 1 {
                <g className="fig-wash">
                    {for n in placed {
                        if n["tier"] == "vendor" and down_ids.includes(n["id"]) {
                            <circle key={n["id"]} cx={place_x(n)} cy={place_y(n)} r={26} />
                        }
                    }}
                </g>
                skip;
            }}

            {#* ---------------------------------------------- orthogonal traces *#}
            <g className="fig-traces">
                {for l in links {
                    <path
                        key={(l["source"] as str) + ">" + (l["target"] as str)}
                        className={trace_cls(l)}
                        d={trace_path(pos, l["source"] as str, l["target"] as str, core_id, l["kind"] as str)}
                    />
                }}
            </g>

            {#* ---------------------------------------------- nodes *#}
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
                    <circle
                        className="hit"
                        cx={place_x(n)}
                        cy={place_y(n)}
                        r={node_radius(n, core_id, 1.0) + 16}
                    />
                    {if n["tier"] == "provider" {
                        <circle cx={place_x(n)} cy={place_y(n)} r={node_radius(n, core_id, 1.0)} />
                        skip;
                    }}
                    {if n["tier"] != "provider" {
                        <rect
                            x={place_x(n) - node_radius(n, core_id, 1.0)}
                            y={place_y(n) - node_radius(n, core_id, 1.0)}
                            width={node_radius(n, core_id, 1.0) * 2}
                            height={node_radius(n, core_id, 1.0) * 2}
                        />
                        skip;
                    }}

                    {if n["tier"] == "provider" {
                        <text
                            className={"lbl-name" + (" lbl-end" if label_side(n) < 0 else "")}
                            x={place_x(n) + (node_radius(n, core_id, 1.0) + 12) * label_side(n)}
                            y={place_y(n) - 1}
                        >
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        <text
                            className={"lbl-meta" + (" lbl-end" if label_side(n) < 0 else "")}
                            x={place_x(n) + (node_radius(n, core_id, 1.0) + 12) * label_side(n)}
                            y={place_y(n) + 13}
                        >
                            {"IN-DEGREE " + str(n["inbound_degree"] or 0)}
                        </text>
                        if n["id"] == core_id and not outage {
                            <text
                                className={"lbl-choke" + (" lbl-end" if label_side(n) < 0 else "")}
                                x={place_x(n) + (node_radius(n, core_id, 1.0) + 12) * label_side(n)}
                                y={place_y(n) + 26}
                            >CHOKEPOINT</text>
                            skip;
                        }
                        skip;
                    }}
                    {if n["tier"] == "org" {
                        <text className="lbl-org" x={place_x(n)} y={place_y(n) + node_radius(n, core_id, 1.0) + 18}>
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        skip;
                    }}
                    {if n["tier"] == "vendor" {
                        <text
                            className={"lbl-vend" + (" lbl-end" if label_side(n) < 0 else "")}
                            x={place_x(n) + (node_radius(n, core_id, 1.0) + 9) * label_side(n)}
                            y={place_y(n) + 3}
                        >
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        if down_now(n) {
                            <text className="lbl-x" x={place_x(n)} y={place_y(n) - node_radius(n, core_id, 1.0) - 7}>✕</text>
                            skip;
                        }
                        skip;
                    }}
                </g>
            }}

            {#* ---------------------------------------------- blast stamp *#}
            {if outage and active and failed_id in pos {
                fx: float = pos[failed_id]["x"] as float;
                fy: float = pos[failed_id]["y"] as float;
                <g className="fig-stamp">
                    <rect x={fx - 168.0} y={fy - 26.0} width={116} height={52} />
                    <text className="stamp-pct" x={fx - 110.0} y={fy + 2.0}>
                        {str(round((active["share"] as float) * 100)) + "%"}
                    </text>
                    <text className="stamp-cap" x={fx - 110.0} y={fy + 17.0}>OF STACK DOWN</text>
                </g>
                skip;
            }}
        </svg>
    </div>;
}
}
