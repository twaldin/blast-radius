"""Tier-pinned dependency canvas (spec 6.1).

x is locked per tier; the simulation only resolves y, so convergence onto a
shared provider reads structurally instead of as a hairball. Appearance is
supplied as a palette object so each surface can restyle it without new flags.
"""

import from "react-force-graph-2d" { default as ForceGraph2D }
import from react { useEffect, useMemo }
import from .store { useRisk }

glob TIER_X: dict = {"org": 0.13, "vendor": 0.47, "provider": 0.85};

glob DEFAULT_PALETTE: dict = {
    "org": "#e8eef7",
    "vendor": "#8fa6c0",
    "provider": "#5ec8ff",
    "flag": "#e0a44a",
    "down": "#ff4d4d",
    "edge": "rgba(120,150,180,0.22)",
    "edgeHot": "rgba(255,77,77,0.75)",
    "dim": "rgba(120,138,160,0.16)",
    "label": "rgba(232,238,247,0.72)",
    "labelOn": "rgba(232,238,247,0.96)",
    "font": "-apple-system, Segoe UI, Roboto, sans-serif"
};

def tier_x(tier: str) -> float {
    if tier == "org" { return TIER_X["org"] as float; }
    if tier == "vendor" { return TIER_X["vendor"] as float; }
    return TIER_X["provider"] as float;
}

def:pub DependencyGraph(palette: any = None) -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];

    has width: int = 900;
    has height: int = 560;
    has hovered: str = "";
    has box: Ref[any] = Ref();
    has fg: Ref[any] = Ref();

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

    useEffect(lambda {
        if fg.current {
            charge: any = fg.current.d3Force("charge");
            if charge { charge.strength(-320).distanceMax(520); }
            link: any = fg.current.d3Force("link");
            if link { link.distance(150).strength(0.22); }
        }
    }, []);

    nodes: any = st["nodes"];
    links: any = st["links"];
    selected: str = st["selected"] as str;
    outage: any = st["outage"];
    hop: int = st["outage_hop"] as int;
    down: any = st["down_vendors"];
    failed_label: str = (outage["provider"] as str) if outage else "";

    pal: any = palette or DEFAULT_PALETTE;
    data: any = useMemo(lambda { return {"nodes": nodes, "links": links}; }, [nodes, links]);

    def is_down(n: any) -> bool {
        if not outage { return False; }
        if n.tier == "provider" { return n.label == failed_label and hop >= 0; }
        if n.tier == "vendor" { return hop >= 1 and down.includes(n.label); }
        return hop >= 2;
    }

    def node_radius(n: any) -> float {
        if n.tier == "provider" {
            deg = (n.inbound_degree or 1) as float;
            return 6.0 + 7.5 * Math.sqrt(deg);
        }
        if n.tier == "org" { return 11.0; }
        return 6.0;
    }

    def node_color(n: any) -> str {
        if is_down(n) { return pal["down"] as str; }
        if outage { return pal["dim"] as str; }
        if n.tier == "org" { return pal["org"] as str; }
        if n.tier == "vendor" { return pal["vendor"] as str; }
        if n.flagged { return pal["flag"] as str; }
        return pal["provider"] as str;
    }

    def draw_node(n: any, ctx: any, scale: float) {
        r = node_radius(n);
        active = n.label == selected or n.id == hovered;

        if is_down(n) {
            ctx.beginPath();
            ctx.arc(n.x, n.y, r + 8, 0, 2 * Math.PI, False);
            ctx.fillStyle = "rgba(255,77,77,0.13)";
            ctx.fill();
        }

        ctx.beginPath();
        ctx.arc(n.x, n.y, r, 0, 2 * Math.PI, False);
        ctx.fillStyle = node_color(n);
        ctx.fill();

        if active {
            ctx.lineWidth = 1.6 / scale;
            ctx.strokeStyle = pal["labelOn"] as str;
            ctx.stroke();
        }

        size = 11.5 / scale;
        ctx.font = str(size) + "px " + (pal["font"] as str);
        ctx.textBaseline = "middle";
        ctx.fillStyle = (pal["dim"] as str) if (outage and not is_down(n)) else ((pal["labelOn"] as str) if active else (pal["label"] as str));
        pad = r + 8;

        if n.tier == "provider" {
            ctx.textAlign = "left";
            ctx.fillText(n.label, n.x + pad, n.y);
        } elif n.tier == "org" {
            ctx.textAlign = "right";
            ctx.fillText(n.label, n.x - pad, n.y);
        } else {
            ctx.textAlign = "center";
            ctx.fillText(n.label, n.x, n.y - pad - 2);
        }
    }

    def link_color(l: any) -> str {
        if not outage { return pal["edge"] as str; }
        tgt = l.target.label if l.target.label else "";
        hot = (tgt == failed_label and hop >= 1) or (hop >= 2 and down.includes(tgt));
        return (pal["edgeHot"] as str) if hot else "rgba(120,150,180,0.06)";
    }

    def handle_tick() {
        span = (width - 380) as float;
        if span < 320.0 { span = 320.0; }
        ylim = (height / 2 - 46) as float;
        for n in nodes {
            n.fx = (tier_x(n.tier) - 0.5) * span;
            if n.y > ylim { n.y = ylim; n.vy = 0; }
            if n.y < 0 - ylim { n.y = 0 - ylim; n.vy = 0; }
        }
    }

    def handle_click(n: any) {
        acts["selectNode"](n.id as str);
    }

    def handle_hover(n: any) {
        hovered = n.id as str if n else "";
    }

    return <div className="graph-surface" ref={box}>
        <ForceGraph2D
            ref={fg}
            graphData={data}
            width={width}
            height={height}
            backgroundColor="rgba(0,0,0,0)"
            nodeCanvasObject={draw_node}
            nodePointerAreaPaint={lambda (n: any, color: str, ctx: any) {
                ctx.beginPath();
                ctx.arc(n.x, n.y, node_radius(n) + 5, 0, 2 * Math.PI, False);
                ctx.fillStyle = color;
                ctx.fill();
            }}
            linkColor={link_color}
            linkWidth={1}
            linkCurvature={0.14}
            d3VelocityDecay={0.35}
            cooldownTicks={260}
            enableZoomInteraction={False}
            enablePanInteraction={False}
            onEngineTick={handle_tick}
            onNodeClick={handle_click}
            onNodeHover={handle_hover}
        />
    </div>;
}
