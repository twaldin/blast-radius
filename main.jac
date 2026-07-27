"""Blast Radius — Graph & Traversal (Person A's file).

Object-spatial core: the ONLY file that creates nodes and edges. See `SPEC-V2.md`.

ONE node type. A company is a company: OpenAI is a vendor of yours *and* an org with
its own Article 28 filing *and* a sub-processor of somebody else. Modelling that as
three node types duplicated the node and made an atlas impossible, so `Org`/`Vendor`/
`Provider` collapse into `Company`, keyed by slug, existing exactly once.

`tier` (org|vendor|provider) is therefore **not stored** — it is BFS distance from
whichever company you are looking at, computed per view. The wire contract is unchanged,
so the client does not care that any of this moved.

Depth: **walking is free, crawling costs money.** Reads are an unbounded BFS over a
visited set (O(V+E), microseconds). The budget lives on the crawl instead, as
`max_new` companies. There is no depth cap anywhere.

Honesty rule (SPEC-V2 §2): a risk field is reported only when `risk_source_url` is set.
No citation, no number — we never emit a plausible-looking fake.

Run:   jac clean --all && jac start main.jac --port 8000
       curl -sX POST localhost:8000/walker/seed_atlas -d '{}'
       curl -sX POST localhost:8000/walker/atlas      -d '{}'
       curl -sX POST localhost:8000/walker/graph      -d '{"domain":"openai.com"}'
Envelope: data.reports[0] is the payload.
"""

import from pathlib { Path }
import from datetime { datetime }
import from hashlib { sha256 }
import from atlas_seed {
    canonical_domain_for_name,
    load_seed_directory
}
import from contracts {
    AtlasSeedRecord,
    ProviderEvidence
}
import from extract {
    resolve_url, fetch_page, extract_and_resolve,
    canonicalize, clean_provider_name, PROVIDER_ALIASES
}
import from demo_data {
    detect_all, provider_profile,
    draft_status_update, explain_fallout, explain_change
}
import from provider_evidence { provider_evidence_for }
import from registry { VENDOR_REGISTRY }

# ------------------------------------------------------------------ graph model
node Company {
    has domain: str;
    has name: str = "";
    has slug: str = "";                     # stable identity + the UI's node id
    has category: str = "";
    has subprocessor_url: str = "";         # the filing we read (provenance)
    has discovery_method: str = "";         # seed | registry | manual | dns | headers | scripts
    has crawl_status: str = "pending";      # pending | ok | unreadable | notfound
    has last_crawled: str = "";
    has content_hash: str = "";             # re-extract only when the filing changes
    has is_sink: bool = False;              # terminal hyperscaler
    has featured: bool = False;             # eligible for the landing rotation
    # Curated risk data. Reported ONLY when risk_source_url is set (SPEC-V2 §2).
    has downtime_hours_ytd: float = 0.0;
    has soc2: bool = True;
    has hipaa: bool = False;
    has supply_chain_risk: str = "";
    has risk_source_url: str = "";
}

edge Subprocesses: Company --> Company {
    has purpose: str = "";
    has region: str = "";
    has confidence: float = 1.0;
    has handles_pii: bool = False;
    has first_seen: str = "";
    has last_seen: str = "";
}

node Snapshot { has taken_at: str; has company_count: int = 0;
                has edge_count: int = 0; has edges: list[str] = []; }
edge CapturedAt: Company --> Snapshot {}

obj GraphView {
    has order: list[Company] = [];
    has dist: dict[str, int] = {};
}

# ------------------------------------------------------------------ small helpers
def _now() -> str { return datetime.now().isoformat(); }

# jac's checker rejects round(x, n); format-string round is the working form.
def _round(x: float, n: int) -> float { return float(f"%.{n}f" % x); }

def _by_exposure(d: dict) -> float { return (d["exposure"] as float); }

def _by_affected(d: dict) -> int { return (d["vendors_affected"] as int); }

def _by_indeg(d: dict) -> int { return (d["inbound_degree"] as int); }

def _by_reach(d: dict) -> int { return (d["vendor_count"] as int); }

def _slugify(s: str) -> str {
    out: list[str] = [];
    prev_dash = False;
    for ch in s.lower() {
        if ch.isalnum() { out.append(ch); prev_dash = False; }
        elif not prev_dash { out.append("-"); prev_dash = True; }
    }
    return "".join(out).strip("-");
}

def _name_from_domain(dom: str) -> str {
    bare = dom.replace("www.", "");
    return bare.split(".")[0].capitalize();
}

def _is_stale(iso: str, ttl_days: int) -> bool {
    if not iso { return True; }
    try {
        return (datetime.now() - datetime.fromisoformat(iso)).days >= ttl_days;
    } except ValueError {
        return True;
    }
}

def _handles_pii(purpose: str) -> bool {
    low = purpose.lower();
    for kw in ["pii", "payment", "error", "log", "personal", "customer data", "analytics"] {
        if kw in low { return True; }
    }
    return False;
}

# Filings write the same role a dozen ways ("Cloud Infrastructure", "Cloud hosting and
# infrastructure provider; Cross-region inference..."). Fold case, take the leading
# clause, dedupe, and cap — otherwise the drafted status post is unreadable.
def _summarize(raw: list[str]) -> list[str] {
    seen: dict[str, bool] = {};
    out: list[str] = [];
    for p in raw {
        head = p.split(";")[0].split(",")[0].strip();
        if not head { continue; }
        if len(head) > 60 { head = head[:57].rstrip() + "..."; }
        k = head.casefold();
        if k in seen { continue; }
        seen[k] = True;
        out.append(head);
    }
    return out[:6];
}

def _tier(d: int) -> str {
    if d == 0 { return "org"; }
    if d == 1 { return "vendor"; }
    return "provider";
}

# ------------------------------------------------------------------ company identity
#
# THE load-bearing step. Stripe files "Amazon Web Services, Inc.", Notion files "AWS",
# Vercel files "Amazon Web Services (AWS)", Slack files "Cloudfront (on Amazon Web
# Services, Inc.)". Those are one company. Store them raw and the graph shows four
# providers with one dependent each and THE CHOKEPOINT NEVER APPEARS.
#
# So nothing un-canonical is ever written. Every name entering the graph resolves
# here first: candidate keys -> alias table -> existing company index -> (optional) LLM
# -> otherwise it becomes a new canonical entry. Reads are then pure traversal.

# True corporate-form suffixes only. Deliberately conservative: over-merging two real
# companies is a much worse error than leaving two spellings apart.
glob LEGAL_TOKENS: set[str] = {
    "inc", "incorporated", "llc", "llp", "lp", "ltd", "limited", "gmbh", "sarl",
    "sa", "sas", "srl", "spa", "bv", "nv", "ab", "oy", "ag", "plc", "pbc", "pte",
    "pty", "kk", "kg", "co", "corp", "corporation", "company", "aps", "oyj"
};

# Brand-level merges observed in the real filings, layered over B's PROVIDER_ALIASES.
glob ALIAS_EXTRA: dict[str, str] = {
    "amazon web services emea sarl": "Amazon Web Services",
    "amazon bedrock": "Amazon Web Services",
    "aws bedrock": "Amazon Web Services",
    "amazon chime": "Amazon Web Services",
    "amazon transcribe": "Amazon Web Services",
    "cloudfront": "Amazon Web Services",
    "google": "Google Cloud",
    "google workspace": "Google Cloud",
    "microsoft": "Microsoft Azure",
    "functional software": "Sentry",
    "anthropic": "Anthropic",
    "openai opco": "OpenAI",
    "honeycombio": "Honeycomb",
    "hound technology": "Honeycomb",
    "mailgun technologies": "Mailgun",
    "sinch email": "Mailgun"
};

def _all_companies() -> list[Company] { return [root -->[?:Company]]; }

# Normalized identity key: dots folded (so "L.L.C." -> "llc"), punctuation to spaces,
# trailing corporate-form tokens dropped.
def _canon_key(raw: str) -> str {
    s = raw.casefold().replace(".", "");
    cleaned: list[str] = [];
    for ch in s {
        cleaned.append(ch if ch.isalnum() else " ");
    }
    tokens = "".join(cleaned).split();
    while tokens and tokens[-1] in LEGAL_TOKENS { _ = tokens.pop(); }
    return " ".join(tokens);
}

# One filed string can hide several usable names: the outer name, a parenthetical
# ("Microsoft Corporation (Microsoft Azure)"), or a d/b/a tail ("Functional Software,
# dba Sentry"). Try each; first resolution wins.
def _canon_candidates(raw: str) -> list[str] {
    out: list[str] = [];
    base = raw.strip();
    low = base.casefold();
    for marker in [" dba ", " d/b/a ", " doing business as "] {
        if marker in low {
            idx = low.find(marker) + len(marker);
            tail = base[idx:].strip(" ()");
            if tail { out.append(tail); }
        }
    }
    if "(" in base and ")" in base {
        op = base.find("(");
        cl = base.find(")", op);
        if cl > op {
            inner = base[op + 1:cl].strip();
            for lead in ["by ", "on ", "dba ", "d/b/a "] {
                if inner.casefold().startswith(lead) { inner = inner[len(lead):].strip(); }
            }
            if inner { out.append(inner); }
            outer = (base[:op] + base[cl + 1:]).strip();
            if outer { out.append(outer); }
        }
    }
    out.append(base);
    return out;
}

def _index() -> dict[str, Company] {
    idx: dict[str, Company] = {};
    for c in _all_companies() {
        k = _canon_key(c.name or c.domain);
        if k and k not in idx { idx[k] = c; }
    }
    return idx;
}

def _alias_for(key: str) -> str {
    if key in ALIAS_EXTRA { return ALIAS_EXTRA[key]; }
    if key in PROVIDER_ALIASES { return PROVIDER_ALIASES[key]; }
    return "";
}

# Resolve a raw filed name to the canonical name we will actually store.
def _canonical_name(raw: str, idx: dict[str, Company], use_llm: bool) -> str {
    for cand in _canon_candidates(raw) {
        k = _canon_key(cand);
        if not k { continue; }
        hit = _alias_for(k);
        if hit { return hit; }
        if k in idx { return idx[k].name; }
    }
    if use_llm {
        try {
            known = [c.name for c in _all_companies()];
            resolved = canonicalize(raw, known);
            if resolved { return resolved; }
        } except Exception {}
    }
    return clean_provider_name(raw) or raw.strip();
}

# Resolve any user-supplied identifier to a company. MUST stay consistent with the
# search ladder and the write path: the alias table is what makes "aws", "gcp" and
# "azure" reach their canonical node, and every caller (dependents, blast_radius,
# expand_one, map_company) depends on that.
def _find_company(key: str) -> Company | None {
    k = key.lower().strip();
    if not k { return None; }
    for c in _all_companies() {
        if c.slug == k or c.domain.lower() == k { return c; }
    }
    ks = _slugify(k);
    ck = _canon_key(key);
    for c in _all_companies() {
        if c.slug == ks or c.name.lower() == k { return c; }
        if ck and _canon_key(c.name or c.domain) == ck { return c; }
    }
    aliased = _alias_for(ck) or _alias_for(_despace(key));
    if aliased {
        ak = _canon_key(aliased);
        for c in _all_companies() {
            if _canon_key(c.name or c.domain) == ak { return c; }
        }
    }
    return None;
}

# Space-insensitive key: "open ai" and "openai" share a key.
def _despace(s: str) -> str { return _canon_key(s).replace(" ", ""); }

# Bounded Levenshtein: is edit distance(a, b) <= budget? The length-gap bailout
# skips hopeless pairs; two-row DP over char lists keeps it simple and typed.
def _edit_within(a: str, b: str, budget: int) -> bool {
    gap = len(a) - len(b);
    if gap < 0 { gap = -gap; }
    if gap > budget { return False; }
    ca: list[str] = [ch for ch in a];
    cb: list[str] = [ch for ch in b];
    prev: list[int] = [];
    for j = 0 while j <= len(cb) with j += 1 { prev.append(j); }
    for i = 1 while i <= len(ca) with i += 1 {
        curr: list[int] = [i];
        for j = 1 while j <= len(cb) with j += 1 {
            cost = 0 if ca[i - 1] == cb[j - 1] else 1;
            best = prev[j] + 1;
            if curr[j - 1] + 1 < best { best = curr[j - 1] + 1; }
            if prev[j - 1] + cost < best { best = prev[j - 1] + cost; }
            curr.append(best);
        }
        prev = curr;
    }
    return prev[len(cb)] <= budget;
}

# mapped = we read its own filing; known = it only appears in others' filings.
def _state_of(c: Company) -> str {
    if len([c ->:Subprocesses:->]) > 0 { return "mapped"; }
    if len([c <-:Subprocesses:<-]) > 0 { return "known"; }
    return "known";
}

# One search-result row for a graph company (the /walker/search Result shape).
def _result_for(c: Company, how: str) -> dict {
    return {
        "id": c.slug, "domain": c.domain, "name": c.name or c.domain,
        "state": _state_of(c),
        "filing_count": len([c ->:Subprocesses:->]),
        "dependent_count": len([c <-:Subprocesses:<-]),
        "crawl_status": c.crawl_status, "source_url": c.subprocessor_url,
        "match": how
    };
}

def _by_name_len(d: dict) -> int { return len((d["name"] as str)); }

# The single write chokepoint. Nothing else may create a Company.
def _upsert_company(domain: str, name: str, idx: dict[str, Company], use_llm: bool) -> Company {
    dom = domain.lower().replace("www.", "").strip();
    label = _canonical_name(name, idx, use_llm) if name else _name_from_domain(dom);
    key = _canon_key(label);
    if key in idx {
        found = idx[key];
        if dom and not found.domain { found.domain = dom; }
        return found;
    }
    if dom {
        for c in _all_companies() {
            if c.domain == dom { idx[key] = c; return c; }
        }
    }
    prof = provider_profile(label);
    made: Company = root ++> Company(
        domain=dom, name=label, slug=prof.slug or _slugify(label) or _slugify(dom),
        category=prof.category, is_sink=prof.is_sink
    );
    idx[key] = made;
    return made;
}

def _get_or_create_company(domain: str, name: str) -> Company {
    return _upsert_company(domain, name, _index(), False);
}

# The root of a view. Explicit domain wins; otherwise the most-connected mapped company,
# so the client's existing no-argument calls keep working.
def _resolve_root(domain: str) -> Company | None {
    if domain {
        hit = _find_company(domain);
        if hit { return hit; }
    }
    best: Company | None = None;
    best_n = -1;
    for c in _all_companies() {
        n = len([c ->:Subprocesses:->]);
        if n == 0 { continue; }
        score = n + (100 if c.featured else 0);
        if score > best_n { best_n = score; best = c; }
    }
    return best;
}

# ------------------------------------------------------------------ the traversal
# BFS over a visited set. `max_hops = 0` means UNBOUNDED — each company appears exactly
# once, so it terminates on the number of distinct companies, not on a hop budget.
# A bound is passed only where the caller genuinely needs less (an atlas card shows
# "vendors and their vendors", so it asks for 2). It is never a cap on the real graph.
def _view(start: Company, max_hops: int) -> GraphView {
    dist: dict[str, int] = {start.slug: 0};
    order: list[Company] = [start];
    frontier: list[Company] = [start];
    hop = 0;
    while frontier {
        if max_hops and hop >= max_hops { break; }
        hop += 1;
        nxt: list[Company] = [];
        for c in frontier {
            for t in [c ->:Subprocesses:->] {
                if t.slug in dist { continue; }
                dist[t.slug] = hop;
                order.append(t);
                nxt.append(t);
            }
        }
        frontier = nxt;
    }
    return GraphView(order=order, dist=dist);
}

def _node_payload(c: Company, tier: str, indeg: int) -> dict {
    evidence: ProviderEvidence | None = provider_evidence_for(
        c.domain,
        c.name
    );
    soc2_cited: bool = (
        evidence is not None
        and evidence.soc2_status != ""
        and evidence.soc2_source_url != ""
    );
    risk_source_url: str = (
        evidence.soc2_source_url
        if soc2_cited and evidence is not None
        else c.risk_source_url
    );
    return {
        "id": c.slug,
        "label": c.name or c.domain,
        "tier": tier,
        "inbound_degree": indeg,
        "soc2": True if soc2_cited else c.soc2,
        "soc2_status": (
            evidence.soc2_status
            if soc2_cited and evidence is not None
            else ""
        ),
        "supply_chain_risk": (
            c.supply_chain_risk if c.risk_source_url else ""
        ),
        "downtime_hours_ytd": 0.0,
        "domain": c.domain,
        "category": c.category,
        "crawl_status": c.crawl_status,
        "source_url": c.subprocessor_url,
        "risk_source_url": risk_source_url
    };
}

def _graph_payload(start: Company) -> dict {
    view = _view(start, 0);
    inview: dict[str, bool] = {};
    for c in view.order { inview[c.slug] = True; }

    edges: list[dict] = [];
    indeg: dict[str, int] = {};
    for c in view.order {
        for t in [c ->:Subprocesses:->] {
            if t.slug not in inview { continue; }
            purpose = "";
            region = "";
            pii = False;
            for e in [edge c ->:Subprocesses:-> t] {
                purpose = e.purpose; region = e.region; pii = e.handles_pii;
            }
            edges.append({
                "source": c.slug, "target": t.slug,
                "kind": "uses" if view.dist[c.slug] == 0 else "subprocesses",
                "purpose": purpose, "region": region, "handles_pii": pii
            });
            indeg[t.slug] = (indeg[t.slug] if t.slug in indeg else 0) + 1;
        }
    }
    nodes: list[dict] = [];
    for c in view.order {
        nodes.append(_node_payload(
            c, _tier(view.dist[c.slug]), indeg[c.slug] if c.slug in indeg else 0));
    }
    return {"nodes": nodes, "edges": edges,
            "root": start.slug, "root_domain": start.domain, "root_label": start.name};
}

# The mirror of _graph_payload: BFS over INBOUND edges — "who depends on this".
# Same Node/Edge shape so the client reuses one canvas; edges keep their REAL
# direction (source = the dependent), so arrows point INTO the centre.
def _inbound_payload(center: Company, max_hops: int) -> dict {
    dist: dict[str, int] = {center.slug: 0};
    order: list[Company] = [center];
    frontier: list[Company] = [center];
    hop = 0;
    while frontier {
        if max_hops and hop >= max_hops { break; }
        hop += 1;
        nxt: list[Company] = [];
        for c in frontier {
            for d in [c <-:Subprocesses:<-] {
                if d.slug in dist { continue; }
                dist[d.slug] = hop;
                order.append(d);
                nxt.append(d);
            }
        }
        frontier = nxt;
    }
    inview: dict[str, bool] = {};
    for c in order { inview[c.slug] = True; }

    edges: list[dict] = [];
    indeg: dict[str, int] = {};
    for d in order {
        for t in [d ->:Subprocesses:->] {
            if t.slug not in inview { continue; }
            purpose = "";
            region = "";
            pii = False;
            for e in [edge d ->:Subprocesses:-> t] {
                purpose = e.purpose; region = e.region; pii = e.handles_pii;
            }
            edges.append({
                "source": d.slug, "target": t.slug,
                "kind": "subprocesses",
                "purpose": purpose, "region": region, "handles_pii": pii
            });
            indeg[t.slug] = (indeg[t.slug] if t.slug in indeg else 0) + 1;
        }
    }
    nodes: list[dict] = [];
    for c in order {
        nodes.append(_node_payload(
            c, _tier(dist[c.slug]), indeg[c.slug] if c.slug in indeg else 0));
    }
    return {"nodes": nodes, "edges": edges,
            "root": center.slug, "root_domain": center.domain,
            "root_label": center.name, "direction": "inbound",
            "dependent_count": len([center <-:Subprocesses:<-])};
}

# ------------------------------------------------------------------ the core algorithm
# "who depends on this" is the whole product. Computed by tallying the FORWARD edges of
# the first layer rather than running an inbound query per provider: same answer, but
# O(edges out of layer 1) instead of O(providers x inbound), which is the difference
# between a 24-second atlas and a sub-second one.
def _layer1(view: GraphView) -> list[Company] {
    out: list[Company] = [];
    for c in view.order {
        if view.dist[c.slug] == 1 { out.append(c); }
    }
    return out;
}

def _chokepoints_view(view: GraphView) -> list[dict] {
    layer1 = _layer1(view);
    n = len(layer1);
    tally: dict[str, int] = {};
    names: dict[str, list[str]] = {};
    ids: dict[str, list[str]] = {};
    hold: dict[str, Company] = {};
    for v in layer1 {
        vlabel = v.name or v.domain;
        for t in [v ->:Subprocesses:->] {
            if view.dist[t.slug] < 2 { continue; }
            if t.slug not in tally {
                tally[t.slug] = 0; names[t.slug] = []; ids[t.slug] = []; hold[t.slug] = t;
            }
            tally[t.slug] = tally[t.slug] + 1;
            names[t.slug].append(vlabel);
            ids[t.slug].append(v.slug);
        }
    }
    scored: list[dict] = [];
    any_cited = False;
    for slug in tally {
        p = hold[slug];
        hits = tally[slug];
        share: float = (hits / n) if n else 0.0;
        cited = p.risk_source_url != "";
        if cited { any_cited = True; }
        dt: float = p.downtime_hours_ytd if cited else 0.0;
        scored.append({
            "provider": p.name or p.domain,
            "provider_id": p.slug,
            "vendors_affected": hits,
            "share": _round(share, 3),
            "downtime_hours_ytd": dt,
            "exposure": _round(share * dt, 2),
            "downtime_cited": cited,
            "names": names[slug],
            "vendor_ids": ids[slug]
        });
    }
    if any_cited { scored.sort(key=_by_exposure, reverse=True); }
    else { scored.sort(key=_by_affected, reverse=True); }
    return scored;
}

def _chokepoints_for(start: Company) -> list[dict] {
    return _chokepoints_view(_view(start, 2));
}

# A compliance gap propagates UP the inbound edges exactly like an outage does.
# Gated on citation: an uncited flag is an invention, and we do not ship inventions.
def _fallout_for(start: Company) -> list[dict] {
    view = _view(start, 2);
    layer1: list[Company] = [];
    for c in view.order {
        if view.dist[c.slug] == 1 { layer1.append(c); }
    }
    flagged: list[dict] = [];
    for p in view.order {
        if view.dist[p.slug] < 2 { continue; }
        if not p.risk_source_url { continue; }
        if p.soc2 and not p.supply_chain_risk { continue; }
        parts: list[str] = [];
        if p.supply_chain_risk { parts.append("supply-chain " + p.supply_chain_risk); }
        if not p.soc2 { parts.append("no valid SOC 2"); }
        reason = "; ".join(parts);
        for v in [p <-:Subprocesses:<-] {
            if v not in layer1 { continue; }
            pii = False;
            for e in [edge v ->:Subprocesses:-> p] { pii = e.handles_pii; }
            flagged.append({
                "vendor": v.name or v.domain, "vendor_id": v.slug,
                "provider": p.name or p.domain, "provider_id": p.slug,
                "handles_pii": pii, "reason": reason,
                "source_url": p.risk_source_url,
                "breaks": explain_fallout(v.name or v.domain, p.name or p.domain)
            });
        }
    }
    return flagged;
}

# Deterministic so the rehearsed path never depends on a model being up.
# B can swap this body for `by llm` without touching the caller.
def _one_look_for(chokes: list[dict], fallout: list[dict], org: str) -> dict {
    if not chokes {
        return {"biggest_risk": f"No shared dependency found for {org} yet — map its sub-processors to see concentration.",
                "biggest_suggestion": "Expand this company's filing, or pick another from the atlas."};
    }
    top = chokes[0];
    pname = top["provider"];
    n = top["vendors_affected"];
    pct = int((top["share"] as float) * 100);
    risk = f"{pname} sits underneath {n} of {org}'s disclosed sub-processors — {pct}% of the first layer converges on a single provider.";
    if top["downtime_cited"] {
        risk = f"{pname} sits underneath {n} of {org}'s disclosed sub-processors ({pct}% of the first layer) and logged {top['downtime_hours_ytd']}h of downtime — the highest expected-exposure dependency.";
    }
    names = top["names"] as list;
    tail = names[-1] if names else "one of them";
    sug = f"Re-homing {tail} off {pname} severs one of {n} shared paths — the single change that most reduces {org}'s concentration.";
    if fallout {
        f0 = fallout[0];
        sug = f"Start with {f0['vendor']}: it routes through {f0['provider']}, which carries a documented compliance gap, and moving it also breaks a shared {pname} path.";
    }
    return {"biggest_risk": risk, "biggest_suggestion": sug};
}

def _edge_signature() -> list[str] {
    sig: list[str] = [];
    for c in _all_companies() {
        for t in [c ->:Subprocesses:->] { sig.append(c.slug + "->" + t.slug); }
    }
    return sig;
}

# ------------------------------------------------------------------ crawl
# The TTL says WHEN to look again; the content hash says whether looking cost anything.
# A refresh of an unchanged filing is one fetch and zero LLM calls, which is what makes
# a short TTL affordable on a graph shared by every caller.
async def _crawl_company(c: Company, ttl_days: int, force: bool) -> str {
    if c.crawl_status == "ok" and not _is_stale(c.last_crawled, ttl_days) and not force {
        return "cached";
    }
    url = await resolve_url(c.domain);
    if not url { c.crawl_status = "notfound"; c.last_crawled = _now(); return "notfound"; }
    text = await fetch_page(url);
    if not text { c.crawl_status = "unreadable"; c.last_crawled = _now(); return "unreadable"; }
    digest = sha256(text.encode("utf-8")).hexdigest();
    c.subprocessor_url = url;
    c.last_crawled = _now();
    if digest == c.content_hash and c.crawl_status == "ok" { return "unchanged"; }
    c.content_hash = digest;
    c.crawl_status = "ok";
    # Rebuild this company's edges, but carry first_seen across so the weekly diff
    # still distinguishes a genuinely new sub-processor from the whole list.
    prior: dict[str, str] = {};
    for t in [c ->:Subprocesses:->] {
        for e in [edge c ->:Subprocesses:-> t] { prior[t.slug] = e.first_seen; }
    }
    for e in [edge c ->:Subprocesses:->] { del e; }
    known = [k.name for k in _all_companies()];
    for rec in extract_and_resolve(text, known) {
        target = _get_or_create_company(
            rec.canonical_domain,
            rec.canonical_name
        );
        seen_at = prior[target.slug] if target.slug in prior else _now();
        c +>:Subprocesses(
            purpose=rec.purpose, region=rec.region, confidence=rec.confidence,
            handles_pii=_handles_pii(rec.purpose), first_seen=seen_at, last_seen=_now()
        ):+> target;
    }
    return "ok";
}

# ------------------------------------------------------------------ seeding
# SPEC-V2 §11. `.jac/` is gitignored and a redeploy starts empty, so the atlas has to
# come from committed files or the deployed instance has nothing in it.
def _seed_one(seed: AtlasSeedRecord, idx: dict[str, Company]) -> dict {
    c: Company = _upsert_company(seed.domain, seed.name, idx, False);
    c.discovery_method = "seed";
    c.featured = seed.crawl_status == "ok";
    c.crawl_status = seed.crawl_status;
    c.subprocessor_url = seed.subprocessor_url;
    c.last_crawled = seed.fetched_at;
    c.content_hash = seed.raw_text_sha;

    prior: dict[str, str] = {};
    for target in [c ->:Subprocesses:->] {
        for edge_value in [edge c ->:Subprocesses:-> target] {
            prior[target.slug] = edge_value.first_seen;
        }
    }
    for edge_value in [edge c ->:Subprocesses:->] {
        del edge_value;
    }
    if seed.crawl_status != "ok" {
        return {
            "domain": seed.domain,
            "status": seed.crawl_status,
            "edges": 0
        };
    }

    made: int = 0;
    seen_targets: set[str] = set();
    for subprocessor in seed.subprocessors {
        target_domain: str = canonical_domain_for_name(subprocessor.name);
        target: Company = _upsert_company(
            target_domain,
            subprocessor.name,
            idx,
            False
        );
        if target.slug in seen_targets {
            continue;
        }
        seen_targets.add(target.slug);
        seen_at: str = (
            prior[target.slug]
            if target.slug in prior
            else seed.fetched_at
        );
        c +>:Subprocesses(
            purpose=subprocessor.purpose,
            region=subprocessor.region,
            handles_pii=_handles_pii(subprocessor.purpose),
            first_seen=seen_at,
            last_seen=seed.fetched_at
        ):+> target;
        made += 1;
    }
    return {
        "domain": seed.domain,
        "status": seed.crawl_status,
        "edges": made
    };
}

# ------------------------------------------------------------------ walkers = endpoints
# Resolve the seed directory next to THIS module first, falling back to the
# process working directory. `Path("seed/atlas")` alone is relative to wherever
# the server happens to be started from, and when it misses, load_seed_directory
# returns nothing and the caller reports `seeded: 0` without an error -- an empty
# graph that looks perfectly healthy.
def _seed_dir(rel: str) -> Path {
    beside = Path(str(__file__)).parent / rel;
    return beside if beside.exists() else Path(rel);
}

"""Load the committed filings if, and only if, the graph is empty.

`seed_atlas` is idempotent and safe to call by hand, but nothing ever called it,
so a container with a fresh database served an empty atlas until a human
remembered the curl. This is the missing caller. It is a no-op the moment any
company exists, so a crawled or already-seeded graph is never touched.
"""
def _ensure_seeded() -> None {
    if _all_companies() { return; }
    (seeds, validation_errors) = load_seed_directory(_seed_dir("seed/atlas"));
    if validation_errors { return; }
    idx: dict[str, Company] = _index();
    for seed in seeds {
        _seed_one(seed, idx);
    }
}

# POST /walker/seed_atlas {}  -> import committed seed/atlas/*.json. Idempotent.
walker:pub seed_atlas {
    has directory: str = "seed/atlas";
    can run with Root entry {
        (seeds, validation_errors) = load_seed_directory(
            _seed_dir(self.directory)
        );
        if validation_errors {
            report {
                "seeded": 0,
                "ok": 0,
                "edges": 0,
                "companies": len(_all_companies()),
                "detail": [],
                "errors": validation_errors
            };
            disengage;
        }
        rows: list[dict] = [];
        idx: dict[str, Company] = _index();
        for seed in seeds {
            rows.append(_seed_one(seed, idx));
        }
        ok: int = 0;
        edges: int = 0;
        for row in rows {
            if row["status"] == "ok" {
                ok += 1;
            }
            edges += row["edges"] as int;
        }
        report {
            "seeded": len(rows),
            "ok": ok,
            "edges": edges,
            "companies": len(_all_companies()),
            "detail": rows,
            "errors": []
        };
    }
}

# POST /walker/atlas {}  -> the landing rotation: every company we have actually mapped.
walker:pub atlas {
    has limit: int = 60;
    can run with Root entry {
        _ensure_seeded();
        out: list[dict] = [];
        for c in _all_companies() {
            direct = [c ->:Subprocesses:->];
            if not direct { continue; }
            view = _view(c, 2);
            chokes = _chokepoints_view(view);
            top = chokes[0] if chokes else None;
            label = c.name or c.domain;
            out.append({
                "id": c.slug, "domain": c.domain, "name": label,
                "featured": c.featured,
                "vendor_count": len(direct),
                "provider_count": len(view.order) - 1 - len(direct),
                "top_chokepoint": top["provider"] if top else "",
                "top_chokepoint_id": top["provider_id"] if top else "",
                "top_share": top["share"] if top else 0.0,
                "vendors_affected": top["vendors_affected"] if top else 0,
                "source_url": c.subprocessor_url
            });
        }
        out.sort(key=_by_reach, reverse=True);
        report {"total": len(out), "companies": out[:self.limit]};
    }
}

# POST /walker/graph {"domain": "openai.com"}  -> unbounded BFS read, computed tiers.
walker:pub graph {
    has domain: str = "";
    can run with Root entry {
        _ensure_seeded();
        start = _resolve_root(self.domain);
        if start { report _graph_payload(start); }
        else { report {"nodes": [], "edges": [], "root": "", "root_domain": "", "root_label": ""}; }
    }
}

# POST /walker/expand {"domain": ..., "max_new": 40}
# Budget-bounded crawl. The cap is on NEW companies fetched, never on depth.
async walker:pub expand {
    has domain: str = "";
    has max_new: int = 40;
    has ttl_days: int = 7;
    has force: bool = False;
    has spent: int = 0;
    has seen: list[str] = [];
    async can run with Root entry {
        start = _resolve_root(self.domain);
        if not start {
            report {"nodes": [], "edges": [], "root": "", "root_domain": "", "root_label": ""};
            disengage;
        }
        queue: list[Company] = [start];
        while queue and self.spent < self.max_new {
            head = queue[0];
            queue = queue[1:];
            if head.slug in self.seen { continue; }
            self.seen.append(head.slug);
            if head.is_sink { continue; }
            status = await _crawl_company(head, self.ttl_days, self.force);
            if status == "ok" or status == "unchanged" { self.spent += 1; }
            for t in [head ->:Subprocesses:->] {
                if t.slug not in self.seen { queue.append(t); }
            }
        }
        report _graph_payload(start);
    }
}

# POST /walker/expand_one {"domain": "stripe.com"}  -> crawl exactly one company.
# Lets the client drive its own per-company spinner with no streaming infrastructure.
async walker:pub expand_one {
    has domain: str;
    has ttl_days: int = 7;
    has force: bool = False;
    async can run with Root entry {
        target = _find_company(self.domain);
        if not target {
            report {"id": self.domain, "name": "", "status": "unknown",
                    "subprocessors": [], "source_url": "", "last_crawled": ""};
        } else {
            status = await _crawl_company(target, self.ttl_days, self.force);
            report {"id": target.slug, "name": target.name, "status": status,
                    "subprocessors": [t.name for t in [target ->:Subprocesses:->]],
                    "source_url": target.subprocessor_url,
                    "last_crawled": target.last_crawled};
        }
    }
}

# POST /walker/crawl_progress {"domain": ...}  -> per-company state + the coverage strip.
walker:pub crawl_progress {
    has domain: str = "";
    can run with Root entry {
        _ensure_seeded();
        start = _resolve_root(self.domain);
        members: list[Company] = _view(start, 0).order if start else [];
        counts: dict[str, int] = {"pending": 0, "ok": 0, "unreadable": 0, "notfound": 0};
        rows: list[dict] = [];
        for c in members {
            if c.crawl_status in counts { counts[c.crawl_status] = counts[c.crawl_status] + 1; }
            rows.append({"id": c.slug, "domain": c.domain, "name": c.name,
                         "crawl_status": c.crawl_status, "source_url": c.subprocessor_url,
                         "last_crawled": c.last_crawled,
                         "subprocessors": len([c ->:Subprocesses:->])});
        }
        total = len(members);
        done = total - counts["pending"];
        report {"total": total, "done": done,
                "pct": _round((done / total) * 100.0, 1) if total else 0.0,
                "counts": counts, "companies": rows, "vendors": rows};
    }
}

# POST /walker/chokepoints {"domain": ...}
walker:pub chokepoints {
    has domain: str = "";
    can run with Root entry {
        _ensure_seeded();
        start = _resolve_root(self.domain);
        report _chokepoints_for(start) if start else [];
    }
}

# POST /walker/blast_radius {"domain": ..., "failed_provider": "aws"}
walker:pub blast_radius {
    has failed_provider: str = "";
    has domain: str = "";
    can run with Root entry {
        start = _resolve_root(self.domain);
        label = self.failed_provider;
        pid = _slugify(self.failed_provider);
        hit: list[Company] = [];
        purposes: list[str] = [];
        if start {
            view = _view(start, 2);
            layer1: list[Company] = [];
            for c in view.order {
                if view.dist[c.slug] == 1 { layer1.append(c); }
            }
            target = _find_company(self.failed_provider);
            if target {
                label = target.name or target.domain;
                pid = target.slug;
                for v in [target <-:Subprocesses:<-] {
                    if v not in layer1 { continue; }
                    hit.append(v);
                    for e in [edge v ->:Subprocesses:-> target] {
                        if e.purpose { purposes.append(e.purpose); }
                    }
                }
            }
        }
        report {
            "provider": label,
            "provider_id": pid,
            "vendors_down": [v.name or v.domain for v in hit],
            "vendor_ids": [v.slug for v in hit],
            "features_down": _summarize(purposes),
            "status_post": draft_status_update(label, _summarize(purposes))
        };
    }
}

# POST /walker/compliance_fallout {"domain": ...}  -> [] unless a claim is cited.
walker:pub compliance_fallout {
    has domain: str = "";
    can run with Root entry {
        _ensure_seeded();
        start = _resolve_root(self.domain);
        report _fallout_for(start) if start else [];
    }
}

# POST /walker/one_look {"domain": ...}
walker:pub one_look {
    has domain: str = "";
    can run with Root entry {
        _ensure_seeded();
        start = _resolve_root(self.domain);
        if start {
            report _one_look_for(_chokepoints_for(start), _fallout_for(start),
                                 start.name or start.domain);
        } else {
            report {"biggest_risk": "Nothing mapped yet — seed the atlas.",
                    "biggest_suggestion": "POST /walker/seed_atlas to import the committed filings."};
        }
    }
}

# POST /walker/search {"q": "aws"}  -> canonicalization-backed resolution ladder.
# Strongest tier wins; we never fall through to weaker tiers once one matched.
walker:pub search {
    has q: str = "";
    has limit: int = 20;
    can run with Root entry {
        _ensure_seeded();
        ql = self.q.lower().strip();
        if not ql {
            report {"query": self.q, "resolved": None, "results": []};
            disengage;
        }
        qk = _canon_key(self.q);
        companies = _all_companies();
        results: list[dict] = [];
        seen: dict[str, bool] = {};
        # T1 exact: canonical keys match ("Amazon Web Services, Inc." == the node).
        for c in companies {
            if qk and _canon_key(c.name or c.domain) == qk and c.slug not in seen {
                seen[c.slug] = True;
                results.append(_result_for(c, "exact"));
            }
        }
        # T2 alias: the alias table resolves ("aws" -> Amazon Web Services).
        if not results {
            canon2 = _alias_for(qk);
            if canon2 {
                ak = _canon_key(canon2);
                for c in companies {
                    if _canon_key(c.name or c.domain) == ak and c.slug not in seen {
                        seen[c.slug] = True;
                        results.append(_result_for(c, "alias"));
                    }
                }
            }
        }
        # T3 despaced: spacing differences vanish ("open ai" == "openai").
        if not results {
            dq = _despace(self.q);
            for c in companies {
                if dq and _despace(c.name or c.domain) == dq and c.slug not in seen {
                    seen[c.slug] = True;
                    results.append(_result_for(c, "alias"));
                }
            }
            if not results {
                canon3 = _alias_for(dq);
                if canon3 {
                    dk = _canon_key(canon3);
                    for c in companies {
                        if _canon_key(c.name or c.domain) == dk and c.slug not in seen {
                            seen[c.slug] = True;
                            results.append(_result_for(c, "alias"));
                        }
                    }
                }
            }
        }
        # T4 slug / domain exact ("openai.com", "amazon-web-services").
        if not results {
            for c in companies {
                if (c.slug == ql or c.domain.lower() == ql) and c.slug not in seen {
                    seen[c.slug] = True;
                    results.append(_result_for(c, "exact"));
                }
            }
        }
        # T5 typo-tolerant fuzzy ("openia" ~ "openai"); skip very short queries.
        if not results and len(qk) >= 4 {
            for c in companies {
                ck = _canon_key(c.name or c.domain);
                if ck and _edit_within(qk, ck, 2) and c.slug not in seen {
                    seen[c.slug] = True;
                    results.append(_result_for(c, "fuzzy"));
                }
            }
        }
        # T6 substring, shortest name first so the parent brand outranks its
        # own long-tail affiliates ("Amazon Web Services" over "...MediaConvert").
        if not results {
            sub: list[dict] = [];
            for c in companies {
                nm = c.name or c.domain;
                sub_hit = ql in nm.lower() or ql in c.domain.lower() or ql in c.slug;
                if sub_hit and c.slug not in seen {
                    seen[c.slug] = True;
                    sub.append(_result_for(c, "fuzzy"));
                }
            }
            sub.sort(key=_by_name_len);
            results.extend(sub);
        }
        # T7 registry offers: known vendors we have not mapped yet.
        if not results {
            for dom in VENDOR_REGISTRY {
                rentry = VENDOR_REGISTRY[dom];
                rid = _slugify(rentry.name);
                if (ql in dom.lower() or ql in rentry.name.lower()) and rid not in seen {
                    seen[rid] = True;
                    results.append({
                        "id": rid, "domain": dom, "name": rentry.name,
                        "state": "registry", "filing_count": 0, "dependent_count": 0,
                        "crawl_status": "pending",
                        "source_url": rentry.subprocessor_url,
                        "match": "registry"
                    });
                }
            }
        }
        results = results[:self.limit];
        resolved: dict | None = None;
        if results and (results[0]["match"] == "exact" or results[0]["match"] == "alias") {
            resolved = results[0];
        }
        report {"query": self.q, "resolved": resolved, "results": results};
    }
}

# POST /walker/industry_map {"min_degree": 2}  -> every company, every disclosed edge.
walker:pub industry_map {
    has min_degree: int = 0;
    can run with Root entry {
        _ensure_seeded();
        indeg: dict[str, int] = {};
        raw: list[dict] = [];
        for c in _all_companies() {
            for t in [c ->:Subprocesses:->] {
                raw.append({"source": c.slug, "target": t.slug, "kind": "subprocesses"});
                indeg[t.slug] = (indeg[t.slug] if t.slug in indeg else 0) + 1;
            }
        }
        keep: dict[str, bool] = {};
        nodes: list[dict] = [];
        for c in _all_companies() {
            d = indeg[c.slug] if c.slug in indeg else 0;
            out_n = len([c ->:Subprocesses:->]);
            if d < self.min_degree and out_n == 0 { continue; }
            keep[c.slug] = True;
            nodes.append(_node_payload(c, _tier(d if d < 2 else 2), d));
        }
        edges = [e for e in raw if (e["source"] in keep) and (e["target"] in keep)];
        mapped = 0;
        for c in _all_companies() {
            if len([c ->:Subprocesses:->]) > 0 { mapped += 1; }
        }
        report {"nodes": nodes, "edges": edges,
                "stats": {"companies": len(nodes), "dependencies": len(edges),
                          "mapped_filings": mapped}};
    }
}

# POST /walker/detect_vendors {"domain": "jachammer.ai"}  -> declared/detected first layer.
walker:pub detect_vendors {
    has domain: str = "jachammer.ai";
    has org_name: str = "";
    can run with Root entry {
        org = _get_or_create_company(self.domain, self.org_name);
        org.featured = True;
        found = detect_all(self.domain);
        rows: list[dict] = [];
        for d in found {
            target = _get_or_create_company(d.domain, d.name);
            target.discovery_method = d.method;
            rows.append({"id": target.slug, "domain": d.domain, "name": d.name, "method": d.method});
            if [org ->:Subprocesses:-> target] { continue; }
            org +>:Subprocesses(first_seen=_now(), last_seen=_now()):+> target;
        }
        report {"found": len(found), "vendors": rows};
    }
}

# POST /walker/add_vendors {"domain": ..., "domains": [...]}  -> the manual/BYO path.
walker:pub add_vendors {
    has domains: list[str];
    has domain: str = "";
    can run with Root entry {
        org = _get_or_create_company(self.domain or "jachammer.ai", "");
        org.featured = True;
        added: list[dict] = [];
        for dom in self.domains {
            target = _get_or_create_company(dom, "");
            target.discovery_method = "manual";
            if [org ->:Subprocesses:-> target] { continue; }
            org +>:Subprocesses(first_seen=_now(), last_seen=_now()):+> target;
            added.append({"id": target.slug, "domain": target.domain,
                          "name": target.name, "method": "manual"});
        }
        report {"found": len([org ->:Subprocesses:->]), "vendors": added};
    }
}

# POST /walker/dependents {"domain": "aws", "max_hops": 2}  -> the INBOUND view:
# "who depends on this". Same Node/Edge shape as graph so the client reuses one canvas.
walker:pub dependents {
    has domain: str = "";
    has max_hops: int = 2;
    can run with Root entry {
        _ensure_seeded();
        target = _find_company(self.domain);
        if target {
            report _inbound_payload(target, self.max_hops);
        } else {
            report {"nodes": [], "edges": [], "root": "", "root_domain": "",
                    "root_label": "", "direction": "inbound", "dependent_count": 0};
        }
    }
}

# POST /walker/map_company {"domain": "figma.com"}  -> on-demand mapping for a
# company we do not have a filing for: resolve-or-create, crawl, report fresh counts.
async walker:pub map_company {
    has domain: str;
    has name: str = "";
    has ttl_days: int = 7;
    async can run with Root entry {
        found = _find_company(self.domain);
        if found {
            target = found;
        } else {
            target = _get_or_create_company(self.domain, self.name);
        }
        status = await _crawl_company(target, self.ttl_days, False);
        report {"id": target.slug, "domain": target.domain, "name": target.name,
                "status": status,
                "filing_count": len([target ->:Subprocesses:->]),
                "dependent_count": len([target <-:Subprocesses:<-]),
                "source_url": target.subprocessor_url};
    }
}

# Persistence-by-reachability: last week's graph is still on root, so a diff is a re-read.
@schedule(cron="0 9 * * 1")
walker:priv diff_monitor {
    has domain: str = "";
    can run with Root entry {
        start = _resolve_root(self.domain);
        if start {
            current = _edge_signature();
            snaps = [start ->:CapturedAt:->];
            prev: list[str] = snaps[-1].edges if snaps else [];
            added = [e for e in current if e not in prev];
            start +>:CapturedAt:+> Snapshot(
                taken_at=_now(), company_count=len(_all_companies()),
                edge_count=len(current), edges=current);
            report {"new_subprocessors": added,
                    "notice": explain_change(added) if added else ""};
        } else {
            report {"new_subprocessors": [], "notice": ""};
        }
    }
}

# ------------------------------------------------------------------ client mount (C)
def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
