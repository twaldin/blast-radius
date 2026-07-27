"""Figure 1 — the circuit schematic, stripped for reading at a glance.

Static SVG, same geometry helpers as the Atlas figure. No interaction, no
outage state, no region column: this one exists to show the convergence,
not to be operated.
"""

cl import "./circuit.css";

cl {
import from .store { useRisk }
import from .graph_core { circuit_layout, circuit_channels, trace_path }

def:pub MiniGraph() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];

    nodes: any = st["nodes"];
    links: any = st["links"];
    core_id: str = (st["top"]["provider_id"] as str) if st["top"] else "";
    ranked_ids: list[str] = [c["provider_id"] as str for c in st["chokes"]];

    model: any = circuit_layout(nodes, links, ranked_ids, []);
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

    chans: any = circuit_channels(links, pos);
    trace_rows: list = [];
    for l in links {
        k = (l["source"] as str) + ">" + (l["target"] as str);
        if k in (chans as dict) {
            dpath = trace_path(pos, l["source"] as str, l["target"] as str, chans[k]);
            if dpath { trace_rows.append({"k": k, "d": dpath}); }
        }
    }

    choke_txt = "";
    if st["top"] and "share" in (st["top"] as dict) {
        choke_txt = "← CHOKEPOINT — CARRIES "
            + str(round((st["top"]["share"] as float) * 100)) + "% OF STACK";
    }

    # vendor names only while they stay legible at landing-figure scale
    show_vend = len([n for n in placed if n["tier"] == "vendor"]) <= 10;

    return <div className="circuit-surface is-static">
        <svg
            className="circuit circuit-mini"
            viewBox={"0 0 " + str(vb_w) + " " + str(vb_h)}
            preserveAspectRatio="xMidYMid meet"
            role="img"
            aria-label="Supply-chain dependency diagram"
        >
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

            <g className="cir-traces">
                {for t in trace_rows {
                    <path key={t["k"]} className="cir-trace" d={t["d"]} />
                }}
            </g>

            {for n in placed {
                <g key={n["id"]} className={"cir-node cir-node-" + (n["tier"] as str) + (" is-core" if n["id"] == core_id else "")}>
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
                        if show_vend {
                            <text
                                className="cir-lbl-vend"
                                x={(n["__x"] as float) - 16}
                                y={(n["__y"] as float) - 11}
                                textAnchor={"end"}
                            >
                                {(n["label"] as any).toUpperCase()}
                            </text>
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
                        if n["id"] == core_id and choke_txt {
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
                            y={(n["__y"] as float) + 3}
                        >
                            {(n["label"] as any).toUpperCase()}
                        </text>
                        skip;
                    }}
                </g>
            }}
        </svg>
    </div>;
}
}
