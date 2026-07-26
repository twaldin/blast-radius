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
    detect_all, resolve_url, fetch_page, extract_and_resolve,
    provider_profile, vendor_feature,
    draft_status_update, explain_fallout, explain_change, compose_one_look
}

# ------------------------------------------------------------------ graph model
# Typed endpoints so `[org ->:Uses:->]` infers `list[Vendor]` with no [?:Type] filter.
# Provider is a separate type from Vendor: a company can be both, and keeping them
# distinct keeps the concentration math honest.
node Org      { has domain: str; has name: str = ""; }
node Vendor   { has domain: str; has name: str;
                has source_url: str = "";
                has discovery_method: str = "";           # dns | headers | scripts | manual
                has crawl_status: str = "pending"; }       # pending | ok | unreadable | notfound
node Provider { has canonical_name: str; has category: str = "";
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

def _org() -> Org | None {
    existing = [root -->[?:Org]];
    return existing[0] if existing else None;
}

def _get_or_create_org(dom: str) -> Org {
    existing = [root -->[?:Org, domain == dom]];
    if existing { return existing[0]; }
    return (root ++> Org(domain=dom, name=_name_from_domain(dom)))[0];
}

def _org_or_default(dom: str) -> Org {
    existing = [root -->[?:Org]];
    return existing[0] if existing else _get_or_create_org(dom);
}

def _get_or_create_feature(fname: str) -> Feature {
    existing = [root -->[?:Feature, name == fname]];
    if existing { return existing[0]; }
    return (root ++> Feature(name=fname))[0];
}

# Node creation from B's returned canonical strings. Seeds curated risk data (B's asset).
def find_or_create_provider(name: str) -> Provider {
    existing = [root -->[?:Provider, canonical_name == name]];
    if existing { return existing[0]; }
    prof = provider_profile(name);
    return (root ++> Provider(
        canonical_name=name, category=prof.category,
        downtime_hours_ytd=prof.downtime_hours_ytd,
        soc2=prof.soc2, hipaa=prof.hipaa,
        supply_chain_risk=prof.supply_chain_risk
    ))[0];
}

def _lookup_provider(pname: str) -> Provider | None {
    for p in [root -->[?:Provider]] {
        if p.canonical_name.lower() == pname.lower() { return p; }
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
                    "inbound_degree": 0, "soc2": True, "supply_chain_risk": "", "downtime_hours_ytd": 0.0});
        for v in [org ->:Uses:->] {
            out.append({"id": v.domain, "label": v.name or v.domain, "tier": "vendor",
                        "inbound_degree": len([v <-:Subprocesses:<-]), "soc2": True,
                        "supply_chain_risk": "", "downtime_hours_ytd": 0.0});
        }
    }
    for p in [root -->[?:Provider]] {
        out.append({"id": p.canonical_name, "label": p.canonical_name, "tier": "provider",
                    "inbound_degree": len([p <-:Subprocesses:<-]), "soc2": p.soc2,
                    "supply_chain_risk": p.supply_chain_risk, "downtime_hours_ytd": p.downtime_hours_ytd});
    }
    return out;
}

def _edges() -> list[dict] {
    out: list[dict] = [];
    org = _org();
    if org {
        for v in [org ->:Uses:->] {
            out.append({"source": org.domain, "target": v.domain, "kind": "uses"});
            for p in [v ->:Subprocesses:->] {
                out.append({"source": v.domain, "target": p.canonical_name, "kind": "subprocesses"});
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
            "vendors_affected": len(exposed),
            "share": _round(share, 3),
            "downtime_hours_ytd": prov.downtime_hours_ytd,
            "exposure": _round(share * prov.downtime_hours_ytd, 2),
            "names": [v.name for v in exposed]
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
            flagged.append({
                "vendor": v.name, "provider": prov.canonical_name,
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
            for p in [v ->:Subprocesses:->] { sig.append(v.domain + "->" + p.canonical_name); }
        }
    }
    return sig;
}

# ------------------------------------------------------------------ walkers = REST endpoints
# POST /walker/detect_vendors  {"domain": "jachammer.ai"}
walker:pub detect_vendors {
    has domain: str = "jachammer.ai";
    can run with Root entry {
        org = _get_or_create_org(self.domain);
        found = detect_all(self.domain);
        for d in found {
            if [org ->:Uses:->[?:Vendor, domain == d.domain]] { continue; }
            v = (org +>:Uses(added_at=_now()):+> Vendor(
                domain=d.domain, name=d.name, discovery_method=d.method))[0];
            feat = vendor_feature(d.domain);
            if feat { v +>:Powers:+> _get_or_create_feature(feat); }
        }
        report {"found": len(found),
                "vendors": [{"domain": d.domain, "name": d.name, "method": d.method} for d in found]};
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
            v = (org +>:Uses(added_at=_now()):+> Vendor(
                domain=dom, name=nm, discovery_method="manual"))[0];
            feat = vendor_feature(dom);
            if feat { v +>:Powers:+> _get_or_create_feature(feat); }
            added.append({"domain": dom, "name": nm, "method": "manual"});
        }
        report {"found": len([org ->:Uses:->]), "vendors": added};
    }
}

# POST /walker/expand  {}   -> BFS crawl, depth 2, then the full graph for the canvas.
# BFS is the language default: `visit [-->]` appends to the queue. The `seen` guard is
# required (the graph has real cycles), not defensive; crawl_status makes re-runs cheap.
async walker:pub expand {
    has seen: list[str] = [];
    can enter with Root entry { visit [-->[?:Org]]; }
    async can crawl_org with Org entry { visit [->:Uses:->]; }
    async can crawl_vendor with Vendor entry {
        if here.crawl_status == "ok" or jid(here) in self.seen { skip; }
        self.seen.append(jid(here));
        url = resolve_url(here.domain);
        if not url { here.crawl_status = "notfound"; skip; }
        text = await fetch_page(url);
        if not text { here.crawl_status = "unreadable"; skip; }
        here.source_url = url;
        here.crawl_status = "ok";
        known = [p.canonical_name for p in [root -->[?:Provider]]];
        for rec in extract_and_resolve(text, known) {
            prov = find_or_create_provider(rec.canonical_name);
            here +>:Subprocesses(
                purpose=rec.purpose, confidence=rec.confidence,
                handles_pii=_handles_pii(rec.purpose), first_seen=_now(), last_seen=_now()
            ):+> prov;
        }
    }
    can finish with Root exit { report {"nodes": _nodes(), "edges": _edges()}; }
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
        if prov {
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
            "provider": self.failed_provider,
            "vendors_down": [v.name for v in hit],
            "features_down": features,
            "status_post": draft_status_update(self.failed_provider, features)
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
