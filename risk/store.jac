"""Single source of truth for the Blast Radius client — contract v2.

`RiskProvider` is the only module that knows how state is fetched or held.
Every surface consumes the same generic interface: state / actions / meta.

v2: the client reads the REAL atlas. `atlas {}` lists every mapped company,
`graph {domain}` is an unbounded BFS read of one company's disclosed stack,
and every insight walker (chokepoints, fallout, one_look, crawl_progress,
blast_radius) is scoped to the viewed domain. The fabricated demo fixture
path (`detect_vendors` / `DEMO_VENDORS`) is gone.
"""

cl import from react { createContext, use }

cl {
glob RiskCtx = createContext(None);

async def call_walker(name: str, payload: any) -> any {
    resp: any = await fetch("/walker/" + name, {
        "method": "POST",
        "headers": {"content-type": "application/json"},
        "body": JSON.stringify(payload)
    });
    if not resp["ok"] { raise Error("walker " + name + " -> " + str(resp["status"])); }
    body: any = await resp.json();
    reports: any = body["data"]["reports"];
    if reports and (len(reports as list) > 0) { return reports[0]; }
    return None;
}

"""BFS depth from the viewed company over the payload's edges, attached to
every node as `depth`. The server's `tier` collapses distance >= 2 into
"provider"; the renderer wants real columns, so we keep the exact hop count."""
def annotate_depth(raw_nodes: any, raw_edges: any, root_id: str) -> list[any] {
    adj: dict = {};
    for e in raw_edges {
        src: str = e["source"] as str;
        prev: any = adj[src] if src in adj else [];
        adj[src] = (prev as list) + [e["target"]];
    }
    depth: dict = {};
    frontier: list[str] = [];
    if root_id {
        depth[root_id] = 0;
        frontier = [root_id];
    }
    hop = 0;
    while len(frontier) > 0 {
        hop = hop + 1;
        nxt: list[str] = [];
        for s in frontier {
            if s not in adj { continue; }
            for t in (adj[s] as list) {
                tid: str = t as str;
                if tid in depth { continue; }
                depth[tid] = hop;
                nxt.append(tid);
            }
        }
        frontier = nxt;
    }
    out: list[any] = [];
    for n in raw_nodes {
        nid: str = n["id"] as str;
        fallback: int = 0 if n["tier"] == "org" else (1 if n["tier"] == "vendor" else 2);
        d: int = (depth[nid] as int) if nid in depth else fallback;
        out = out + [{**n, "depth": d}];
    }
    return out;
}

def edge_region_codes(l: any) -> list[any] {
    codes: any = l["region_codes"] if "region_codes" in (l as dict) else [];
    return (codes or []) as list;
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
    has companies: list[any] = [];
    has atlas_total: int = 0;
    has company_domain: str = "";
    has org_label: str = "";
    has root_id: str = "";
    has all_nodes: list[any] = [];
    has all_links: list[any] = [];
    has region: str = "";
    has chokes: list[any] = [];
    has fallout: list[any] = [];
    has coverage: any = empty_coverage();
    has headline: any = None;
    has selected: str = "";
    has outage: any = None;
    has outage_hop: int = -1;
    has loading: bool = True;
    has crawling: bool = False;
    has failed: bool = False;
    has s_q: str = "";
    has s_hits: list[any] = [];
    has s_resolved: any = None;
    has s_busy: bool = False;
    has s_discovering: bool = False;
    has s_done: bool = False;
    has s_discovered: bool = False;
    has s_error: str = "";

    async def refresh_insights(domain: str) -> None {
        ranked = await call_walker("chokepoints", {"domain": domain});
        gaps = await call_walker("compliance_fallout", {"domain": domain});
        one = await call_walker("one_look", {"domain": domain});
        prog = await call_walker("crawl_progress", {"domain": domain});
        chokes = ((ranked or []) as list);
        fallout = ((gaps or []) as list);
        headline = one;
        coverage = prog if prog else empty_coverage();
        if ranked and len(ranked as list) > 0 {
            selected = ranked[0]["provider_id"] as str;
        } else {
            selected = "";
        }
    }

    async def view(domain: str) -> None {
        if not domain { return; }
        try {
            loading = True;
            failed = False;
            outage = None;
            outage_hop = -1;
            selected = "";
            region = "";
            g = await call_walker("graph", {"domain": domain});
            company_domain = domain;
            root_id = (g["root"] as str) if g else "";
            org_label = ((g["root_label"] or domain) as str) if g else domain;
            raw_nodes: any = (g["nodes"] if g else []) or [];
            raw_links: any = (g["edges"] if g else []) or [];
            all_nodes = annotate_depth(raw_nodes, raw_links, root_id);
            all_links = (raw_links as list);
            await refresh_insights(domain);
            loading = False;
        } except Exception as e {
            console.error("[blast-radius] load failed", e);
            crawling = False;
            failed = True;
            loading = False;
        }
    }

    async def boot() -> None {
        res = await call_walker("atlas", {});
        if (not res) or ((res["total"] or 0) as int) == 0 {
            # cold start: a fresh deploy has an empty graph until the committed
            # filings are imported. seed_atlas is idempotent, so firing it here
            # is safe even if the server also seeds on boot.
            await call_walker("seed_atlas", {});
            res = await call_walker("atlas", {});
        }
        if res {
            companies = ((res["companies"] or []) as list);
            atlas_total = ((res["total"] or 0) as int);
        }
        if len(companies) > 0 {
            feats: list[any] = [c for c in companies if c["featured"]];
            first: any = feats[0] if len(feats) > 0 else companies[0];
            await view(first["domain"] as str);
        } else {
            loading = False;
        }
    }

    async can with entry {
        try {
            await boot();
        } except Exception as e {
            console.error("[blast-radius] boot failed", e);
            crawling = False;
            failed = True;
            loading = False;
        }
    }

    # ------------------------------------------------------------- search
    async def run_search(q: str) -> None {
        trimmed: str = (q or "").strip();
        s_q = trimmed;
        s_discovered = False;
        s_error = "";
        if not trimmed {
            s_hits = [];
            s_resolved = None;
            s_done = False;
            s_busy = False;
            return;
        }
        s_busy = True;
        try {
            res = await call_walker("search", {"q": trimmed, "limit": 8});
            s_hits = (((res["results"] if res else []) or []) as list);
            s_resolved = res["resolved"] if res else None;
            s_done = True;
            s_busy = False;
        } except Exception as e {
            console.error("[blast-radius] search failed", e);
            s_hits = [];
            s_resolved = None;
            s_error = "Search failed — is the server up?";
            s_done = True;
            s_busy = False;
        }
    }

    # The judge-types-an-unmapped-company path: same walker, agent unlocked.
    # Guarded so a backend without allow_discovery degrades to a clean error.
    async def discover(q: str) -> None {
        trimmed: str = (q or s_q or "").strip();
        if not trimmed { return; }
        s_discovering = True;
        s_error = "";
        try {
            res = await call_walker("search", {"q": trimmed, "limit": 8, "allow_discovery": True});
            if res and res["resolved"] {
                s_hits = ((res["results"] or []) as list);
                s_resolved = res["resolved"];
                s_discovered = ((res["discovered"] or False) as bool);
                atlas_res = await call_walker("atlas", {});
                if atlas_res {
                    companies = ((atlas_res["companies"] or []) as list);
                    atlas_total = ((atlas_res["total"] or 0) as int);
                }
                await view(res["resolved"]["domain"] as str);
            } else {
                s_error = "Nothing found — no readable filing for that name.";
            }
            s_discovering = False;
        } except Exception as e {
            console.error("[blast-radius] discovery failed", e);
            s_discovering = False;
            s_error = "Discovery is not available on this deployment.";
        }
    }

    def clear_search() -> None {
        s_q = "";
        s_hits = [];
        s_resolved = None;
        s_busy = False;
        s_discovering = False;
        s_done = False;
        s_discovered = False;
        s_error = "";
    }

    # The text box for what filings cannot see — internal tools, the warehouse.
    async def add_manual(raw: str) -> None {
        parts: list[str] = [];
        for chunk in raw.split(",") {
            trimmed = chunk.strip();
            if trimmed { parts.append(trimmed); }
        }
        if not parts { return; }
        try {
            loading = True;
            await call_walker("add_vendors", {"domains": parts, "domain": company_domain});
            await view(company_domain);
        } except Exception as e {
            console.error("[blast-radius] add failed", e);
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
        res = await call_walker("blast_radius", {
            "failed_provider": active["provider"],
            "domain": company_domain
        });
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

    def set_region(code: str) -> None {
        region = code or "";
    }

    # -------------------------------------------------- derived, per render
    links_f: list[any] = all_links if not region
        else [l for l in all_links if region in edge_region_codes(l)];
    kept: dict = {};
    if region {
        if root_id { kept[root_id] = True; }
        for l in links_f {
            kept[l["source"] as str] = True;
            kept[l["target"] as str] = True;
        }
    }
    nodes_f: list[any] = all_nodes if not region
        else [n for n in all_nodes if (n["id"] as str) in kept];

    edge_keys: dict = {};
    for l in links_f {
        edge_keys[(l["source"] as str) + ">" + (l["target"] as str)] = True;
    }

    region_seen: dict = {};
    regions: list[str] = [];
    for l in all_links {
        for rc in edge_region_codes(l) {
            code: str = rc as str;
            if code and code not in region_seen {
                region_seen[code] = True;
                regions = regions + [code];
            }
        }
    }
    regions = sorted(regions);

    vendors: list[any] = [n for n in nodes_f if n["tier"] == "vendor"];
    providers: list[any] = [n for n in nodes_f if n["tier"] == "provider"];

    value: any = {
        "state": {
            "companies": companies,
            "atlas_total": atlas_total,
            "company_domain": company_domain,
            "org_label": org_label,
            "root_id": root_id,
            "nodes": nodes_f,
            "links": links_f,
            "edge_keys": edge_keys,
            "vendors": vendors,
            "providers": providers,
            "vendor_total": len(vendors),
            "provider_total": len(providers),
            "regions": regions,
            "region": region,
            "chokes": chokes,
            "fallout": fallout,
            "coverage": coverage,
            "headline": headline,
            "selected": selected,
            "active": choke_for(chokes, selected),
            "top": chokes[0] if len(chokes) > 0 else None,
            "outage": outage,
            "outage_hop": outage_hop,
            "down_ids": (outage["vendor_ids"] as list) if outage else [],
            "search": {
                "q": s_q,
                "hits": s_hits,
                "resolved": s_resolved,
                "busy": s_busy,
                "discovering": s_discovering,
                "done": s_done,
                "discovered": s_discovered,
                "error": s_error
            }
        },
        "actions": {
            "view": view,
            "select": select,
            "simulate": simulate,
            "clear": clear,
            "setRegion": set_region,
            "search": run_search,
            "discover": discover,
            "clearSearch": clear_search,
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
}
