"""The memo's figure — the same radial shape, stripped for reading at a glance.

No interaction, no outage state, provider labels only. It exists to show the
convergence in one look, not to be operated.
"""

import from "react-force-graph-2d" { default as ForceGraph2D }
import from react { useEffect, useMemo }
import from .store { useRisk }
import from .graph_core { radial_layout, node_radius, ink, tau }

def:pub MiniGraph() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];

    has width: int = 640;
    has height: int = 380;
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

    data: any = useMemo(lambda {
        return {"nodes": radial_layout(nodes, links, core_id), "links": links};
    }, [nodes, links, core_id]);

    def draw_node(n: any, ctx: any, scale: float) {
        r = node_radius(n, core_id, 0.8);

        ctx.beginPath();
        ctx.arc(n.x, n.y, r, 0, TAU, False);
        if n.id == core_id {
            ctx.fillStyle = C["core"];
            ctx.fill();
        } elif n.tier == "vendor" {
            ctx.fillStyle = C["vendor"];
            ctx.fill();
            ctx.lineWidth = 1.2 / scale;
            ctx.strokeStyle = C["vendorEdge"];
            ctx.stroke();
        } else {
            ctx.fillStyle = C["provider"];
            ctx.fill();
        }

        if n.tier == "vendor" { return; }

        ctx.font = "600 " + str(9.5 / scale) + "px Archivo, sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        ctx.fillStyle = C["labelOn"] if n.id == core_id else C["label"];
        label_txt: any = n.label;
        ctx.fillText(label_txt.toUpperCase(), n.x, n.y + r + 6 / scale);
    }

    def handle_tick() {
        span = (Math.min(width, height) * 0.38) as float;
        for n in data["nodes"] {
            n.fx = Math.cos(n.__a) * span * n.__r;
            n.fy = Math.sin(n.__a) * span * n.__r;
        }
    }

    return <div className="graph-surface" ref={box}>
        <ForceGraph2D
            graphData={data}
            width={width}
            height={height}
            backgroundColor="rgba(0,0,0,0)"
            nodeCanvasObject={draw_node}
            linkColor={lambda (l: any) { return C["edge"]; }}
            linkWidth={0.9}
            linkCurvature={0.24}
            cooldownTicks={40}
            enableZoomInteraction={False}
            enablePanInteraction={False}
            enableNodeDrag={False}
            onEngineTick={handle_tick}
        />
    </div>;
}
