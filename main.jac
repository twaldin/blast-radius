"""Blast Radius — Graph & Traversal (Person A's file).

Object-spatial core: the ONLY file that creates nodes and edges. Real graph logic
behind the frozen walker contract (PLAN.md). Vendors/providers are discovered from
B's `extract.jac` exports (detection, crawl, `by llm` extraction + entity resolution);
A turns the returned typed records into a graph and answers every question by
traversal — `[prov <-:Subprocesses:<-]` (who transitively depends on this) is the
whole product in one line.

Run:   jac clean --all && jac start main.jac --port 8000
Then:  curl -s -X POST localhost:8000/walker/detect_vendors -d '{"domain":"jachammer.ai"}'
       curl -s -X POST localhost:8000/walker/expand        -d '{}'
       curl -s -X POST localhost:8000/walker/chokepoints   -d '{}'
Envelope: data.reports[0] is the payload.
"""

import from datetime { datetime }
import from extract {
    resolve_url, fetch_page, extract_and_resolve
}
import from demo_data {
    detect_all,
    provider_profile, vendor_feature,
    draft_status_update, explain_fallout, explain_change, compose_one_look
}

# ------------------------------------------------------------------ graph model
# Typed endpoints so `[org ->:Uses:->]` infers `list[Vendor]` with no [?:Type] filter.
# Provider is a separate type from Vendor: a company can be both, and keeping them
# distinct keeps the concentration math honest.
node Org      { has domain: str; has name: str = ""; }
node Vendor   { has domain: str; has name: str;
                has slug: str = "";                        # stable short id for the UI
                has source_url: str = "";                  # the filing we read (provenance)
                has discovery_method: str = "";            # dns | headers | scripts | manual
                has crawl_status: str = "pending";         # pending | ok | unreadable | notfound
                has last_crawled: str = ""; }              # ISO ts -> drives TTL re-crawl
node Provider { has canonical_name: str; has slug: str = ""; has category: str = "";
                has downtime_hours_ytd: float = 0.0;       # curated historical outage -> risk weight
                has soc2: bool = True; has hipaa: bool = False;
                has supply_chain_risk: str = ""; }         # "" | watchlist | sanctioned | foreign-owned
node Feature  { has name: str; }
node Snapshot { has taken_at: str; has vendor_count: int = 0;
                has provider_count: int = 0; has edges: list[str] = []; }

edge Uses:         Org    --> Vendor   { has added_at: str = ""; }
edge Subprocesses: Vendor --> Provider { has purpose: str = "";
                                         has confidence: float = 1.0;
                                         has handles_pii: bool = False;   # gates compliance fallout
                                         has first_seen: str = "";
                                         has last_seen: str = ""; }
edge Powers:       Vendor  --> Feature   {}
edge CapturedAt:   Org     --> Snapshot  {}

# ------------------------------------------------------------------ graph helpers
def _now() -> str { return datetime.now().isoformat(); }

def _round(x: float, n: int) -> float { return float(f"%.{n}f" % x); }

def _by_exposure(d: dict) -> float { return (d["exposure"] as float); }

def _name_from_domain(dom: str) -> str { return dom.split(".")[0].capitalize(); }

# Stable short id for the UI. Slugging the DISPLAY NAME (not the domain) is what makes
# "Datadog"/datadoghq.com -> `datadog` and "OpenAI" -> `openai`.
def _slugify(s: str) -> str {
    out: list[str] = [];
    prev_dash = False;
    for ch in s.lower() {
        if ch.isalnum() { out.append(ch); prev_dash = False; }
        elif not prev_dash { out.append("-"); prev_dash = True; }
    }
    return "".join(out).strip("-");
}

# A cached crawl older than the TTL is refetched; everything else is served off the graph.
def _is_stale(iso: str, ttl_days: int) -> bool {
    if not iso { return True; }
    try {
        return (datetime.now() - datetime.fromisoformat(iso)).days >= ttl_days;
    } except ValueError {
        return True;
    }
}

def _org() -> Org | None {
    existing = [root -->[?:Org]];
    return existing[0] if existing else None;
}

def _get_or_create_org(dom: str, nm: str) -> Org {
    existing = [root -->[?:Org, domain == dom]];
    if existing {
        found = existing[0];
        if nm { found.name = nm; }
        return found;
    }
    return root ++> Org(domain=dom, name=nm or _name_from_domain(dom));
}

def _org_or_default(dom: str) -> Org {
    existing = [root -->[?:Org]];
    return existing[0] if existing else _get_or_create_org(dom, "");
}

def _get_or_create_feature(fname: str) -> Feature {
    existing = [root -->[?:Feature, name == fname]];
    if existing { return existing[0]; }
    return root ++> Feature(name=fname);
}

# Node creation from B's returned canonical strings. Seeds curated risk data (B's asset).
def find_or_create_provider(name: str) -> Provider {
    existing = [root -->[?:Provider, canonical_name == name]];
    if existing { return existing[0]; }
    prof = provider_profile(name);
    return root ++> Provider(
        canonical_name=name, slug=prof.slug or _slugify(name), category=prof.category,
        downtime_hours_ytd=prof.downtime_hours_ytd,
        soc2=prof.soc2, hipaa=prof.hipaa,
        supply_chain_risk=prof.supply_chain_risk
    );
}

# Accepts either the UI slug ("aws", "gcp") or the canonical name ("Google Cloud").
def _lookup_provider(pname: str) -> Provider | None {
    want = pname.lower();
    for p in [root -->[?:Provider]] {
        if p.canonical_name.lower() == want or p.slug == want { return p; }
    }
    return None;
}

def _handles_pii(purpose: str) -> bool {
    low = purpose.lower();
    for kw in ["pii", "payment", "error", "log", "data", "payload", "personal"] {
        if kw in low { return True; }
    }
    return False;
}

# ------------------------------------------------------------------ serialization (frozen Node/Edge shapes)
def _nodes() -> list[dict] {
    out: list[dict] = [];
    org = _org();
    if org {
        out.append({"id": org.domain, "label": org.name or org.domain, "tier": "org",
                    "inbound_degree": 0, "soc2": True, "supply_chain_risk": "",
                    "downtime_hours_ytd": 0.0, "domain": org.domain, "category": "",
                    "features": [], "crawl_status": "", "source_url": ""});
        for v in [org ->:Uses:->] {
            out.append({"id": v.slug, "label": v.name or v.domain, "tier": "vendor",
                        "inbound_degree": len([v <-:Subprocesses:<-]), "soc2": True,
                        "supply_chain_risk": "", "downtime_hours_ytd": 0.0,
                        "domain": v.domain, "category": "",
                        "features": [f.name for f in [v ->:Powers:->]],
                        "crawl_status": v.crawl_status, "source_url": v.source_url});
        }
    }
    for p in [root -->[?:Provider]] {
        out.append({"id": p.slug, "label": p.canonical_name, "tier": "provider",
                    "inbound_degree": len([p <-:Subprocesses:<-]), "soc2": p.soc2,
                    "supply_chain_risk": p.supply_chain_risk,
                    "downtime_hours_ytd": p.downtime_hours_ytd,
                    "domain": "", "category": p.category,
                    "features": [], "crawl_status": "", "source_url": ""});
    }
    return out;
}

def _edges() -> list[dict] {
    out: list[dict] = [];
    org = _org();
    if org {
        for v in [org ->:Uses:->] {
            out.append({"source": org.domain, "target": v.slug, "kind": "uses",
                        "purpose": "", "handles_pii": False});
            for p in [v ->:Subprocesses:->] {
                purpose = "";
                pii = False;
                for e in [edge v ->:Subprocesses:-> p] { purpose = e.purpose; pii = e.handles_pii; }
                out.append({"source": v.slug, "target": p.slug, "kind": "subprocesses",
                            "purpose": purpose, "handles_pii": pii});
            }
        }
    }
    return out;
}

# ------------------------------------------------------------------ core algorithm
# `[prov <-:Subprocesses:<-]` = who transitively depends on this provider. share x
# historical downtime = expected exposure.
def _chokepoints() -> list[dict] {
    org = _org();
    vendors = [org ->:Uses:->] if org else [];
    n = len(vendors);
    scored: list[dict] = [];
    for prov in [root -->[?:Provider]] {
        exposed = [v for v in [prov <-:Subprocesses:<-] if v in vendors];
        if not exposed { continue; }
        share: float = (len(exposed) / n) if n else 0.0;
        scored.append({
            "provider": prov.canonical_name,
            "provider_id": prov.slug,
            "vendors_affected": len(exposed),
            "share": _round(share, 3),
            "downtime_hours_ytd": prov.downtime_hours_ytd,
            "exposure": _round(share * prov.downtime_hours_ytd, 2),
            "names": [v.name for v in exposed],
            "vendor_ids": [v.slug for v in exposed]
        });
    }
    scored.sort(key=_by_exposure, reverse=True);
    return scored;
}

# Compliance gap propagates UP the inbound edges, exactly like an outage.
def _fallout() -> list[dict] {
    org = _org();
    vendors = [org ->:Uses:->] if org else [];
    flagged: list[dict] = [];
    for prov in [root -->[?:Provider]] {
        if prov.soc2 and not prov.supply_chain_risk { continue; }
        parts: list[str] = [];
        if prov.supply_chain_risk { parts.append("supply-chain " + prov.supply_chain_risk); }
        if not prov.soc2 { parts.append("no valid SOC 2"); }
        reason = "; ".join(parts);
        for v in [prov <-:Subprocesses:<-] {
            if v not in vendors { continue; }
            pii = False;
            for e in [edge v ->:Subprocesses:-> prov] { pii = e.handles_pii; }
            flagged.append({
                "vendor": v.name, "vendor_id": v.slug,
                "provider": prov.canonical_name, "provider_id": prov.slug,
                "handles_pii": pii,
                "reason": reason, "breaks": explain_fallout(v.name, prov.canonical_name)
            });
        }
    }
    return flagged;
}

def _edge_signature() -> list[str] {
    org = _org();
    sig: list[str] = [];
    if org {
        for v in [org ->:Uses:->] {
            for p in [v ->:Subprocesses:->] { sig.append(v.slug + "->" + p.slug); }
        }
    }
    return sig;
}

# ------------------------------------------------------------------ walkers = REST endpoints
# POST /walker/detect_vendors  {"domain": "jachammer.ai"}
walker:pub detect_vendors {
    has domain: str = "jachammer.ai";
    has org_name: str = "";              # display name; derived from the domain when blank
    can run with Root entry {
        org = _get_or_create_org(self.domain, self.org_name);
        found = detect_all(self.domain);
        rows: list[dict] = [];
        for d in found {
            rows.append({"id": _slugify(d.name), "domain": d.domain, "name": d.name, "method": d.method});
            if [org ->:Uses:->[?:Vendor, domain == d.domain]] { continue; }
            v: Vendor = org +>:Uses(added_at=_now()):+> Vendor(
                domain=d.domain, name=d.name, slug=_slugify(d.name),
                discovery_method=d.method);
            feat = vendor_feature(d.domain);
            if feat { v +>:Powers:+> _get_or_create_feature(feat); }
        }
        report {"found": len(found), "vendors": rows};
    }
}

# POST /walker/add_vendors  {"domains": ["notion.so", ...]}   -> the manual text box
walker:pub add_vendors {
    has domains: list[str];
    can run with Root entry {
        org = _org_or_default("jachammer.ai");
        added: list[dict] = [];
        for dom in self.domains {
            if [org ->:Uses:->[?:Vendor, domain == dom]] { continue; }
            nm = _name_from_domain(dom);
            v: Vendor = org +>:Uses(added_at=_now()):+> Vendor(
                domain=dom, name=nm, slug=_slugify(nm), discovery_method="manual");
            feat = vendor_feature(dom);
            if feat { v +>:Powers:+> _get_or_create_feature(feat); }
            added.append({"id": v.slug, "domain": dom, "name": nm, "method": "manual"});
        }
        report {"found": len([org ->:Uses:->]), "vendors": added};
    }
}

# POST /walker/expand  {}   -> BFS crawl, depth 2, then the full graph for the canvas.
# BFS is the language default: `visit [-->]` appends to the queue. The `seen` guard is
# required (the graph has real cycles), not defensive; crawl_status makes re-runs cheap.
async walker:pub expand {
    has ttl_days: int = 7;               # a cached crawl older than this is refetched
    has force: bool = False;             # ignore the cache entirely
    has seen: list[str] = [];
    can enter with Root entry { visit [-->[?:Org]]; }
    async can crawl_org with Org entry { visit [->:Uses:->]; }
    async can crawl_vendor with Vendor entry {
        cached = here.crawl_status == "ok" and not _is_stale(here.last_crawled, self.ttl_days);
        if (cached and not self.force) or jid(here) in self.seen { skip; }
        self.seen.append(jid(here));
        url = await resolve_url(
            here.domain,
            prefer_demo_cache=here.discovery_method != "manual"
        );
        if not url { here.crawl_status = "notfound"; here.last_crawled = _now(); skip; }
        text = await fetch_page(url);
        if not text { here.crawl_status = "unreadable"; here.last_crawled = _now(); skip; }
        here.source_url = url;
        here.crawl_status = "ok";
        here.last_crawled = _now();
        # Re-crawl replaces this vendor's edges, but first_seen survives so the weekly
        # diff still knows which sub-processors are genuinely new.
        prior: dict[str, str] = {};
        for p in [here ->:Subprocesses:->] {
            for e in [edge here ->:Subprocesses:-> p] { prior[p.canonical_name] = e.first_seen; }
        }
        for e in [edge here ->:Subprocesses:->] { del e; }
        known = [p.canonical_name for p in [root -->[?:Provider]]];
        for rec in extract_and_resolve(text, known) {
            prov = find_or_create_provider(rec.canonical_name);
            seen_at = prior[rec.canonical_name] if rec.canonical_name in prior else _now();
            here +>:Subprocesses(
                purpose=rec.purpose, confidence=rec.confidence,
                handles_pii=_handles_pii(rec.purpose), first_seen=seen_at, last_seen=_now()
            ):+> prov;
        }
    }
    can finish with Root exit { report {"nodes": _nodes(), "edges": _edges()}; }
}

# POST /walker/crawl_progress  {}  -> per-vendor crawl state + provenance for the
# "searching..." UI and the honest coverage strip (ok / unreadable / notfound).
walker:pub crawl_progress {
    can run with Root entry {
        org = _org();
        vendors = [org ->:Uses:->] if org else [];
        counts: dict[str, int] = {"pending": 0, "ok": 0, "unreadable": 0, "notfound": 0};
        rows: list[dict] = [];
        for v in vendors {
            if v.crawl_status in counts { counts[v.crawl_status] = counts[v.crawl_status] + 1; }
            rows.append({"id": v.slug, "domain": v.domain, "name": v.name,
                         "crawl_status": v.crawl_status, "source_url": v.source_url,
                         "last_crawled": v.last_crawled,
                         "subprocessors": len([v ->:Subprocesses:->])});
        }
        total = len(vendors);
        done = total - counts["pending"];
        report {"total": total, "done": done,
                "pct": _round((done / total) * 100.0, 1) if total else 0.0,
                "counts": counts, "vendors": rows};
    }
}

# POST /walker/chokepoints  {}  -> ranked shared providers (share x downtime = exposure)
walker:pub chokepoints {
    can run with Root entry { report _chokepoints(); }
}

# POST /walker/blast_radius  {"failed_provider": "AWS"}  -> backward traversal
walker:pub blast_radius {
    has failed_provider: str = "AWS";
    can run with Root entry {
        org = _org();
        vendors = [org ->:Uses:->] if org else [];
        prov = _lookup_provider(self.failed_provider);
        hit: list[Vendor] = [];
        label = self.failed_provider;
        pid = _slugify(self.failed_provider);
        if prov {
            label = prov.canonical_name;
            pid = prov.slug;
            for v in [prov <-:Subprocesses:<-] {
                if v in vendors { hit.append(v); }
            }
        }
        features: list[str] = [];
        for v in hit {
            for f in [v ->:Powers:->] { features.append(f.name); }
        }
        features = list(set(features));
        report {
            "provider": label,
            "provider_id": pid,
            "vendors_down": [v.name for v in hit],
            "vendor_ids": [v.slug for v in hit],
            "features_down": features,
            "status_post": draft_status_update(label, features)
        };
    }
}

# POST /walker/compliance_fallout  {}  -> SOC2/HIPAA/watchlist gaps that propagate up
walker:pub compliance_fallout {
    can run with Root entry { report _fallout(); }
}

# POST /walker/one_look  {}  -> the two-sentence headline (calls B/C's narrative one_look)
walker:pub one_look {
    can run with Root entry {
        head = compose_one_look(_chokepoints(), _fallout());
        report {"biggest_risk": head.biggest_risk, "biggest_suggestion": head.biggest_suggestion};
    }
}

# Scheduled diff (Action 2): persistence-by-reachability means the monitor needs no
# database — last week's graph is still on `root`, so a diff is just a re-read.
@schedule(cron="0 9 * * 1")
walker:priv diff_monitor {
    can run with Root entry {
        org = _org();
        if org {
            current = _edge_signature();
            snaps = [org ->:CapturedAt:->];
            prev: list[str] = snaps[-1].edges if snaps else [];
            added = [e for e in current if e not in prev];
            org +>:CapturedAt:+> Snapshot(
                taken_at=_now(), vendor_count=len([org ->:Uses:->]),
                provider_count=len([root -->[?:Provider]]), edges=current);
            report {"new_subprocessors": added, "notice": explain_change(added) if added else ""};
        } else {
            report {"new_subprocessors": [], "notice": ""};
        }
    }
}
