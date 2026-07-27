"""Figure 1 — the same lens, stripped for reading at a glance.

Static SVG, same geometry helpers as the Atlas figure. No interaction and no
outage state: this one exists to show the convergence, not to be operated.
"""

cl {
import from .store { useRisk }
import from .graph_core { burst_layout, node_radius, place_x, place_y, label_side, trace_path }

def:pub MiniGraph() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];

    nodes: any = st["nodes"];
    links: any = st["links"];
    core_id: str = (st["top"]["provider_id"] as str) if st["top"] else "";
    ranked_ids: list[str] = [c["provider_id"] as str for c in st["chokes"]];

    placed: any = burst_layout(nodes, links, ranked_ids);
    pos: dict = {};
    for n in placed {
        pos[n["id"]] = {"x": place_x(n), "y": place_y(n), "n": n};
    }

    return <div className="graph-surface">
        <svg className="fig fig-mini" viewBox="0 0 1000 720" preserveAspectRatio="xMidYMid meet">
            <g className="fig-traces">
                {for l in links {
                    <path
                        key={(l["source"] as str) + ">" + (l["target"] as str)}
                        className="trace"
                        d={trace_path(pos, l["source"] as str, l["target"] as str, core_id, l["kind"] as str)}
                    />
                }}
            </g>

            {for n in placed {
                <g key={n["id"]} className={"gnode gnode-" + (n["tier"] as str) + (" is-core" if n["id"] == core_id else "")}>
                    {if n["tier"] == "provider" {
                        <circle cx={place_x(n)} cy={place_y(n)} r={node_radius(n, core_id, 1.0)} />
                        <text className="lbl-name" x={place_x(n) + node_radius(n, core_id, 1.0) + 12} y={place_y(n) + 4}>
                            {(n["label"] as any).toUpperCase()}
                        </text>
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
                    {if n["tier"] == "org" {
                        <text className="lbl-name lbl-end" x={place_x(n) - node_radius(n, core_id, 1.0) - 12} y={place_y(n) + 4}>
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
