"""The Atlas canvas — interactive, labelled, and wired to the outage state."""

import from "react-force-graph-2d" { default as ForceGraph2D }
import from react { useEffect, useMemo }
import from .store { useRisk }
import from .graph_core { radial_layout, node_radius, ink, tau }

def:pub DependencyGraph() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];

    has width: int = 900;
    has height: int = 620;
    has hovered: str = "";
    has box: Ref[any] = Ref();

    useEffect(lambda {
        measure: any = lambda {
            if box.current {
                width = box.current.clientWidth;
                height = box.current.clientHeight;
            }
        };
        measure.call(None);
        window.addEventListener("resize", measure);
        return lambda { window.removeEventListener("resize", measure); };
    }, []);

    C: any = ink();
    TAU: float = tau();

    nodes: any = st["nodes"];
    links: any = st["links"];
    top: any = st["top"];
    core_id: str = (top["provider_id"] as str) if top else "";
    selected: str = st["selected"] as str;
    outage: any = st["outage"];
    hop: int = st["outage_hop"] as int;
    down_ids: any = st["down_ids"];
    failed_id: str = (outage["provider_id"] as str) if outage else "";

    data: any = useMemo(lambda {
        return {"nodes": radial_layout(nodes, links, core_id), "links": links};
    }, [nodes, links, core_id]);

    def is_down(n: any) -> bool {
        if not outage { return False; }
        if n.id == failed_id { return hop >= 0; }
        if n.tier == "vendor" { return hop >= 1 and down_ids.includes(n.id); }
        if n.tier == "org" { return hop >= 2; }
        return False;
    }

    def draw_node(n: any, ctx: any, scale: float) {
        r = node_radius(n, core_id, 1.0);
        active = n.id == selected or n.id == hovered;
        down = is_down(n);
        muted = outage and not down;

        if down and n.id == failed_id {
            ctx.beginPath();
            ctx.arc(n.x, n.y, r * 1.9, 0, TAU, False);
            ctx.fillStyle = "rgba(229,35,27,0.12)";
            ctx.fill();
        }

        ctx.beginPath();
        ctx.arc(n.x, n.y, r, 0, TAU, False);

        if down {
            ctx.fillStyle = C["down"];
            ctx.fill();
        } elif muted {
            ctx.fillStyle = C["mute"];
            ctx.fill();
        } elif n.id == core_id {
            ctx.fillStyle = C["core"];
            ctx.fill();
        } elif n.tier == "vendor" {
            ctx.fillStyle = C["vendor"];
            ctx.fill();
            ctx.lineWidth = 1.4 / scale;
            ctx.strokeStyle = C["flag"] if (n.supply_chain_risk or (not n.soc2)) else C["vendorEdge"];
            ctx.stroke();
        } else {
            ctx.fillStyle = C["flag"] if (n.supply_chain_risk or (not n.soc2)) else C["provider"];
            ctx.fill();
        }

        if active and not outage {
            ctx.beginPath();
            ctx.arc(n.x, n.y, r + 5 / scale, 0, TAU, False);
            ctx.lineWidth = 1.2 / scale;
            ctx.strokeStyle = C["core"];
            ctx.stroke();
        }

        if n.tier == "vendor" and outage and not down { return; }

        size = (12.0 if n.id == core_id else 10.0) / scale;
        ctx.font = "600 " + str(size) + "px Archivo, sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        ctx.fillStyle = C["mute"] if muted else (C["labelOn"] if (active or n.id == core_id) else C["label"]);
        label_txt: any = n.label;
        ctx.fillText(label_txt.toUpperCase(), n.x, n.y + r + 7 / scale);

        if n.id == core_id and not outage {
            ctx.font = "500 " + str(8.5 / scale) + "px 'IBM Plex Mono', monospace";
            ctx.fillStyle = C["core"];
            ctx.fillText("CHOKEPOINT", n.x, n.y + r + 22 / scale);
        }
    }

    def link_color(l: any) -> str {
        if not outage { return C["edge"] as str; }
        tid = l.target.id if l.target.id else "";
        sid = l.source.id if l.source.id else "";
        hot = (tid == failed_id and hop >= 1) or (hop >= 2 and down_ids.includes(sid));
        return (C["edgeHot"] as str) if hot else (C["edgeSoft"] as str);
    }

    def link_width(l: any) -> float {
        if not outage { return 1.0; }
        tid = l.target.id if l.target.id else "";
        return 1.8 if tid == failed_id and hop >= 1 else 0.7;
    }

    def handle_tick() {
        span = (Math.min(width, height) * 0.40) as float;
        for n in data["nodes"] {
            n.fx = Math.cos(n.__a) * span * n.__r;
            n.fy = Math.sin(n.__a) * span * n.__r;
        }
    }

    def handle_click(n: any) {
        if n.tier == "provider" { acts["select"](n.id as str); }
    }

    def handle_hover(n: any) {
        hovered = n.id as str if n else "";
    }

    return <div className="graph-surface" ref={box}>
        <ForceGraph2D
            graphData={data}
            width={width}
            height={height}
            backgroundColor="rgba(0,0,0,0)"
            nodeCanvasObject={draw_node}
            nodePointerAreaPaint={lambda (n: any, color: str, ctx: any) {
                ctx.beginPath();
                ctx.arc(n.x, n.y, node_radius(n, core_id, 1.0) + 6, 0, TAU, False);
                ctx.fillStyle = color;
                ctx.fill();
            }}
            linkColor={link_color}
            linkWidth={link_width}
            linkCurvature={0.24}
            cooldownTicks={50}
            enableZoomInteraction={False}
            enablePanInteraction={False}
            onEngineTick={handle_tick}
            onNodeClick={handle_click}
            onNodeHover={handle_hover}
        />
    </div>;
}
