"""Single source of truth for the Blast Radius client.

`RiskProvider` is the only module that knows how state is fetched or held.
Every surface consumes the same generic interface: state / actions / meta.
"""

import from react { createContext, use }

glob RiskCtx = createContext(None);
glob PRUNE_ABOVE: int = 8;

async def call_walker(name: str, payload: any) -> any {
    resp = await fetch("/walker/" + name, {
        "method": "POST",
        "headers": {"content-type": "application/json"},
        "body": JSON.stringify(payload)
    });
    body = await resp.json();
    reports: any = body["data"]["reports"];
    if reports and (len(reports as list) > 0) { return reports[0]; }
    return None;
}

def inbound_counts(edges: any) -> any {
    counts = {};
    for e in edges {
        tgt = e["target"];
        counts[tgt] = (counts[tgt] or 0) + 1;
    }
    return counts;
}

def build_graph(raw_nodes: any, raw_edges: any) -> any {
    counts = inbound_counts(raw_edges);
    providers = [n for n in raw_nodes if n["tier"] == "provider"];
    prune = len(providers) > PRUNE_ABOVE;

    kept = {};
    out_nodes = [];
    folded = 0;

    for n in raw_nodes {
        nid = n["id"];
        deg = (counts[nid] or 0) as int;
        if n["tier"] == "provider" and prune and deg < 2 {
            folded = folded + 1;
            continue;
        }
        kept[nid] = True;
        out_nodes = out_nodes + [{
            "id": nid,
            "label": n["label"],
            "tier": n["tier"],
            "inbound_degree": deg,
            "flagged": (not n["soc2"]) or (n["supply_chain_risk"] != "")
        }];
    }

    if folded > 0 {
        kept["__other"] = True;
        out_nodes = out_nodes + [{
            "id": "__other",
            "label": "other (" + str(folded) + ")",
            "tier": "provider",
            "inbound_degree": 1,
            "flagged": False
        }];
    }

    out_links = [];
    for e in raw_edges {
        src = e["source"];
        tgt = e["target"] if kept[e["target"]] else "__other";
        if not kept[src] { continue; }
        if not kept[tgt] { continue; }
        out_links = out_links + [{"source": src, "target": tgt}];
    }

    return {"nodes": out_nodes, "links": out_links};
}

def choke_for(chokes: any, provider_label: str) -> any {
    for c in chokes {
        if c["provider"] == provider_label { return c; }
    }
    return None;
}

def:pub RiskProvider(children: any = None) -> JsxElement {
    has nodes: list[any] = [];
    has links: list[any] = [];
    has chokes: list[any] = [];
    has fallout: list[any] = [];
    has headline: any = None;
    has org_label: str = "";
    has vendor_total: int = 0;
    has provider_total: int = 0;
    has selected: str = "";
    has outage: any = None;
    has outage_hop: int = -1;
    has loading: bool = True;
    has failed: bool = False;

    async can with entry {
        try {
            graph = await call_walker("expand", {});
            ranked = await call_walker("chokepoints", {});
            gaps = await call_walker("compliance_fallout", {});
            one = await call_walker("one_look", {});

            raw_nodes = graph["nodes"];
            raw_edges = graph["edges"];
            built = build_graph(raw_nodes, raw_edges);

            nodes = built["nodes"];
            links = built["links"];
            chokes = ranked or [];
            fallout = gaps or [];
            headline = one;
            org_label = "";
            for n in raw_nodes {
                if n["tier"] == "org" { org_label = n["label"] as str; }
            }
            vendor_total = len([n for n in raw_nodes if n["tier"] == "vendor"]);
            provider_total = len([n for n in raw_nodes if n["tier"] == "provider"]);
            if ranked and len(ranked as list) > 0 { selected = ranked[0]["provider"] as str; }
            loading = False;
        } except Exception as e {
            console.error("[blast-radius] load failed", e);
            failed = True;
            loading = False;
        }
    }

    def select(label: str) -> None {
        if outage { return; }
        selected = label;
    }

    def select_node(node_id: str) -> None {
        for n in nodes {
            if n["id"] == node_id and n["tier"] == "provider" {
                select(n["label"] as str);
            }
        }
    }

    async def simulate() -> None {
        if not selected { return; }
        res = await call_walker("blast_radius", {"failed_provider": selected});
        if not res { return; }
        outage = res;
        outage_hop = 0;
        setTimeout(lambda { outage_hop = 1; }, 700);
        setTimeout(lambda { outage_hop = 2; }, 1400);
    }

    def clear() -> None {
        outage = None;
        outage_hop = -1;
    }

    value: any = {
        "state": {
            "nodes": nodes,
            "links": links,
            "chokes": chokes,
            "fallout": fallout,
            "headline": headline,
            "org_label": org_label,
            "vendor_total": vendor_total,
            "provider_total": provider_total,
            "selected": selected,
            "active": choke_for(chokes, selected),
            "outage": outage,
            "outage_hop": outage_hop,
            "down_vendors": outage["vendors_down"] if outage else []
        },
        "actions": {
            "select": select,
            "selectNode": select_node,
            "simulate": simulate,
            "clear": clear
        },
        "meta": {
            "loading": loading,
            "failed": failed,
            "ready": (not loading) and (not failed)
        }
    };

    return <RiskCtx.Provider value={value}>{children}</RiskCtx.Provider>;
}

def:pub useRisk() -> any {
    return use(RiskCtx);
}
