# Person C owns this client shell. It remains fixture-backed until A freezes walker contracts.
import "./app.css";
def demo_graph() -> dict {
    nodes: list[dict] = [
        {"id": "org-1", "label": "Northwind Retail", "tier": "org", "inbound_degree": 0, "status": "complete"},
        {"id": "vendor-1", "label": "Atlas Logistics", "tier": "vendor", "inbound_degree": 1, "status": "complete"},
        {"id": "vendor-2", "label": "Meridian Payments", "tier": "vendor", "inbound_degree": 1, "status": "partial"},
        {"id": "vendor-3", "label": "Solstice Cloud Ops", "tier": "vendor", "inbound_degree": 1, "status": "complete"},
        {"id": "provider-1", "label": "Cascade Data Center", "tier": "provider", "inbound_degree": 2, "status": "complete"},
        {"id": "provider-2", "label": "Vertex Identity Svc", "tier": "provider", "inbound_degree": 1, "status": "partial"},
        {"id": "provider-3", "label": "Harbor Object Store", "tier": "provider", "inbound_degree": 1, "status": "complete"},
    ];
    edges: list[dict] = [
        {"id": "e1", "source": "org-1", "target": "vendor-1"},
        {"id": "e2", "source": "org-1", "target": "vendor-2"},
        {"id": "e3", "source": "org-1", "target": "vendor-3"},
        {"id": "e4", "source": "vendor-1", "target": "provider-1"},
        {"id": "e5", "source": "vendor-2", "target": "provider-1"},
        {"id": "e6", "source": "vendor-2", "target": "provider-2"},
        {"id": "e7", "source": "vendor-3", "target": "provider-3"},
    ];
    return {"nodes": nodes, "edges": edges};
}

def node_by_id(nodes: list[dict], node_id: str) -> dict | None {
    for n in nodes {
        if n["id"] == node_id {
            return n;
        }
    }
    return None;
}

def inbound_edges(edges: list[dict], node_id: str) -> list[dict] {
    return [e for e in edges if e["target"] == node_id];
}

def by_inbound_degree(n: dict) -> int {
    return n["inbound_degree"] as int;
}

def:pub app() -> JsxElement {
    graph: dict = demo_graph();
    nodes: list[dict] = graph["nodes"];
    edges: list[dict] = graph["edges"];

    has domain_query: str = "";
    has selected_id: str = "provider-1";

    def handle_domain_change(e: ChangeEvent) {
        domain_query = e.target.value;
    }

    def select_provider(node_id: str) {
        selected_id = node_id;
    }

    vendors: list[dict] = [n for n in nodes if n["tier"] == "vendor"];
    providers: list[dict] = [n for n in nodes if n["tier"] == "provider"];
    ranked_providers: list[dict] = sorted(providers, key=by_inbound_degree, reverse=True);
    selected_node: dict | None = node_by_id(nodes, selected_id);
    selected_inbound: list[dict] = inbound_edges(edges, selected_id) if selected_node else [];

    return <div className="shell">
        <header className="shell-header">
            <div className="brand">
                <span className="brand-mark">BR</span>
                <div className="brand-copy">
                    <h1 className="brand-title">Blast Radius</h1>
                    <span className="brand-sub">Risk Command Center</span>
                </div>
            </div>
            <div className="header-status">
                <span className="status-pill status-pill-fixture">Fixture Mode</span>
                <span className="status-pill">{str(len(nodes)) + " nodes"}</span>
                <span className="status-pill">{str(len(edges)) + " edges"}</span>
            </div>
        </header>

        <div className="shell-body">
            <aside className="rail rail-left">
                <section className="rail-section">
                    <h2 className="rail-title">Domain Intake</h2>
                    <input
                        className="domain-input"
                        type="text"
                        placeholder="Enter org domain..."
                        value={domain_query}
                        onChange={handle_domain_change}
                    />
                    <p className="rail-hint">Fixture-backed. No crawl is triggered.</p>
                </section>
                <section className="rail-section">
                    <h2 className="rail-title">Vendor Queue</h2>
                    <ul className="queue-list">
                        {for v in vendors {
                            <li key={v["id"]} className="queue-item">
                                <span className={"status-dot status-dot-" + str(v["status"])}></span>
                                <span className="queue-label">{v["label"]}</span>
                            </li>
                        }}
                    </ul>
                </section>
            </aside>

            <main className="canvas">
                <div className="canvas-header">
                    <h2 className="canvas-title">Dependency Map</h2>
                    <span className="canvas-sub">Org &rarr; Vendors &rarr; Providers</span>
                </div>
                <div className="canvas-tiers">
                    <div className="canvas-tier">
                        <span className="tier-label">Org</span>
                        {for n in nodes {
                            if n["tier"] == "org" {
                                <button
                                    key={n["id"]}
                                    className={"node-chip node-chip-org " + ("node-chip-selected" if selected_id == n["id"] else "")}
                                    onClick={lambda { select_provider(n["id"] as str); }}
                                >
                                    {n["label"]}
                                </button>
                            }
                        }}
                    </div>
                    <div className="canvas-tier">
                        <span className="tier-label">Vendors</span>
                        {for n in vendors {
                            <button
                                key={n["id"]}
                                className={"node-chip node-chip-vendor " + ("node-chip-selected" if selected_id == n["id"] else "")}
                                onClick={lambda { select_provider(n["id"] as str); }}
                            >
                                {n["label"]}
                            </button>
                        }}
                    </div>
                    <div className="canvas-tier">
                        <span className="tier-label">Providers</span>
                        {for n in providers {
                            <button
                                key={n["id"]}
                                className={"node-chip node-chip-provider " + ("node-chip-shared" if (n["inbound_degree"] as int) >= 2 else "") + " " + ("node-chip-selected" if selected_id == n["id"] else "")}
                                onClick={lambda { select_provider(n["id"] as str); }}
                            >
                                {n["label"]}
                                {(n["inbound_degree"] as int) >= 2 and <span className="chip-badge">shared</span>}
                            </button>
                        }}
                    </div>
                </div>
            </main>

            <aside className="rail rail-right">
                <section className="rail-section">
                    <h2 className="rail-title">Concentration Ranking</h2>
                    <ol className="ranking-list">
                        {for p in ranked_providers {
                            <li key={p["id"]}>
                                <button
                                    className={"ranking-item " + ("ranking-item-selected" if selected_id == p["id"] else "")}
                                    onClick={lambda { select_provider(p["id"] as str); }}
                                >
                                    <span className="ranking-label">{p["label"]}</span>
                                    <span className="ranking-degree">{str(p["inbound_degree"]) + " in"}</span>
                                </button>
                            </li>
                        }}
                    </ol>
                </section>
            </aside>
        </div>

        <footer className="incident-drawer">
            <div className="incident-header">
                <h2 className="incident-title">Incident Preview</h2>
                {selected_node and <span className={"status-pill status-pill-" + str(selected_node["status"])}>{selected_node["status"]}</span>}
            </div>
            {if selected_node {
                <div className="incident-body">
                    <div className="incident-col">
                        <span className="incident-label">Selected Node</span>
                        <span className="incident-value">{selected_node["label"]}</span>
                    </div>
                    <div className="incident-col">
                        <span className="incident-label">Tier</span>
                        <span className="incident-value">{selected_node["tier"]}</span>
                    </div>
                    <div className="incident-col">
                        <span className="incident-label">Inbound Dependencies</span>
                        <span className="incident-value">{str(len(selected_inbound))}</span>
                    </div>
                </div>
                skip;
            }}
            {if not selected_node {
                <p className="incident-empty">Select a node from the map or ranking to preview impact.</p>
                skip;
            }}
        </footer>
    </div>;
}
