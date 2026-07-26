"""Single source of truth for the Blast Radius client.

`RiskProvider` is the only module that knows how state is fetched or held.
Every surface consumes the same generic interface: state / actions / meta.

`expand` runs a real depth-2 crawl, so while it is in flight we poll
`crawl_progress` for per-vendor provenance — that is the honest coverage strip,
and it doubles as the live build animation without needing a socket.
"""

import from react { createContext, use }

glob RiskCtx = createContext(None);
glob PRUNE_ABOVE: int = 10;

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

def build_graph(raw_nodes: any, raw_edges: any) -> any {
    providers = [n for n in raw_nodes if n["tier"] == "provider"];
    prune = len(providers) > PRUNE_ABOVE;

    kept = {};
    out_nodes = [];
    folded = 0;

    for n in raw_nodes {
        deg = (n["inbound_degree"] or 0) as int;
        if n["tier"] == "provider" and prune and deg < 2 {
            folded = folded + 1;
            continue;
        }
        kept[n["id"]] = True;
        out_nodes = out_nodes + [n];
    }

    if folded > 0 {
        kept["__other"] = True;
        out_nodes = out_nodes + [{
            "id": "__other",
            "label": "other (" + str(folded) + ")",
            "tier": "provider",
            "inbound_degree": 1,
            "soc2": True,
            "supply_chain_risk": "",
            "downtime_hours_ytd": 0.0,
            "features": []
        }];
    }

    out_links = [];
    for e in raw_edges {
        src = e["source"];
        tgt = e["target"] if kept[e["target"]] else "__other";
        if not kept[src] { continue; }
        out_links = out_links + [{"source": src, "target": tgt, "kind": e["kind"], "handles_pii": e["handles_pii"]}];
    }

    return {"nodes": out_nodes, "links": out_links};
}

def choke_for(rows: any, provider_id: str) -> any {
    for c in rows {
        if c["provider_id"] == provider_id { return c; }
    }
    return None;
}

def empty_coverage() -> any {
    return {"total": 0, "done": 0, "pct": 0.0,
            "counts": {"pending": 0, "ok": 0, "unreadable": 0, "notfound": 0},
            "vendors": []};
}

def:pub RiskProvider(children: any = None) -> JsxElement {
    has nodes: list[any] = [];
    has links: list[any] = [];
    has chokes: list[any] = [];
    has fallout: list[any] = [];
    has coverage: any = empty_coverage();
    has headline: any = None;
    has org_label: str = "";
    has selected: str = "";
    has outage: any = None;
    has outage_hop: int = -1;
    has loading: bool = True;
    has crawling: bool = False;
    has failed: bool = False;

    async def refresh_insights() -> None {
        ranked = await call_walker("chokepoints", {});
        gaps = await call_walker("compliance_fallout", {});
        one = await call_walker("one_look", {});
        chokes = ranked or [];
        fallout = gaps or [];
        headline = one;
        if ranked and len(ranked as list) > 0 and not selected {
            selected = ranked[0]["provider_id"] as str;
        }
    }

    async def poll_progress() -> None {
        prog = await call_walker("crawl_progress", {});
        if prog { coverage = prog; }
    }

    async def load_graph() -> None {
        crawling = True;
        timer: any = setInterval(lambda { poll_progress(); }, 700);
        try {
            graph = await call_walker("expand", {});
            built = build_graph(graph["nodes"], graph["edges"]);
            nodes = built["nodes"];
            links = built["links"];
            org_label = "";
            for n in graph["nodes"] {
                if n["tier"] == "org" { org_label = n["label"] as str; }
            }
        } finally {
            # the poll must die even when expand rejects, or it hammers the
            # server at 700ms behind a failed screen
            clearInterval(timer);
            crawling = False;
        }
        await poll_progress();
        await refresh_insights();
    }

    async can with entry {
        try {
            await load_graph();
            loading = False;
        } except Exception as e {
            console.error("[blast-radius] load failed", e);
            crawling = False;
            failed = True;
            loading = False;
        }
    }

    # The judge-types-their-own-domain path: detection seeds the org and its
    # visible vendors, then the same crawl fills in the second layer.
    async def ingest(domain: str) -> None {
        if not domain { return; }
        try {
            loading = True;
            failed = False;
            selected = "";
            await call_walker("detect_vendors", {"domain": domain});
            await load_graph();
            loading = False;
        } except Exception as e {
            console.error("[blast-radius] detect failed", e);
            crawling = False;
            failed = True;
            loading = False;
        }
    }

    # The text box for what detection cannot see — internal tools, the warehouse.
    async def add_manual(raw: str) -> None {
        parts: list[str] = [];
        for chunk in raw.split(",") {
            trimmed = chunk.strip();
            if trimmed { parts.append(trimmed); }
        }
        if not parts { return; }
        try {
            loading = True;
            await call_walker("add_vendors", {"domains": parts});
            await load_graph();
            loading = False;
        } except Exception as e {
            console.error("[blast-radius] add failed", e);
            crawling = False;
            failed = True;
            loading = False;
        }
    }

    def select(provider_id: str) -> None {
        if outage { return; }
        selected = provider_id;
    }

    async def simulate() -> None {
        active = choke_for(chokes, selected);
        if not active { return; }
        res = await call_walker("blast_radius", {"failed_provider": active["provider"]});
        if not res { return; }
        outage = res;
        outage_hop = 0;
        setTimeout(lambda { outage_hop = 1; }, 620);
        setTimeout(lambda { outage_hop = 2; }, 1240);
    }

    def clear() -> None {
        outage = None;
        outage_hop = -1;
    }

    vendors: any = [n for n in nodes if n["tier"] == "vendor"];
    providers: any = [n for n in nodes if n["tier"] == "provider"];

    value: any = {
        "state": {
            "nodes": nodes,
            "links": links,
            "vendors": vendors,
            "providers": providers,
            "chokes": chokes,
            "fallout": fallout,
            "coverage": coverage,
            "headline": headline,
            "org_label": org_label,
            "vendor_total": len(vendors),
            "provider_total": len(providers),
            "selected": selected,
            "active": choke_for(chokes, selected),
            "top": chokes[0] if chokes and len(chokes as list) > 0 else None,
            "outage": outage,
            "outage_hop": outage_hop,
            "down_ids": outage["vendor_ids"] if outage else []
        },
        "actions": {
            "select": select,
            "simulate": simulate,
            "clear": clear,
            "ingest": ingest,
            "addManual": add_manual
        },
        "meta": {
            "loading": loading,
            "crawling": crawling,
            "failed": failed,
            "ready": (not loading) and (not failed)
        }
    };

    return <RiskCtx.Provider value={value}>{children}</RiskCtx.Provider>;
}

def:pub useRisk() -> any {
    return use(RiskCtx);
}
