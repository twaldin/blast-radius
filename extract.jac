"""Blast Radius — Data & Extraction (Person B's file).

*** STUB — placeholder so Person A's graph slice compiles + demos standalone. ***
Person B replaces every body below with the real detection / crawl / `by llm`
extraction + entity-resolution + ReAct discovery agent. The SIGNATURES here are the
frozen A<->B boundary — do not rename a function, parameter, or return type without a
group call. Bodies return the curated jachammer.ai demo dataset so `main.jac` builds
the exact contract graph (jachammer.ai -> 8 vendors -> 5 providers, AWS = chokepoint)
off cache, with no network call.

Contract additions this stub introduces (agreed with A, needed by the graph):
  - provider_profile(name) -> ProviderProfile   (curated provider risk/downtime asset)
  - vendor_feature(domain)  -> str              (what the vendor powers for the org)
  - compose_one_look / explain_fallout / explain_change / draft_status_update
    are the narrative outputs A's walkers call; B/C swap the bodies to `by llm`.
"""

import from contracts { DetectedVendor, ResolvedSubprocessor, RiskHeadline }

# ------------------------------------------------------------------ curated demo asset
obj ProviderProfile {
    has category: str = "";
    has downtime_hours_ytd: float = 0.0;
    has soc2: bool = True;
    has hipaa: bool = False;
    has supply_chain_risk: str = "";      # "" | watchlist | sanctioned | foreign-owned
}

# jachammer.ai's externally-visible SaaS stack (the "I found your vendors" moment).
glob DEMO_VENDORS: list[DetectedVendor] = [
    DetectedVendor(domain="openai.com",     name="OpenAI",     method="scripts"),
    DetectedVendor(domain="anthropic.com",  name="Anthropic",  method="headers"),
    DetectedVendor(domain="openrouter.ai",  name="OpenRouter", method="headers"),
    DetectedVendor(domain="github.com",     name="GitHub",     method="dns"),
    DetectedVendor(domain="stripe.com",     name="Stripe",     method="scripts"),
    DetectedVendor(domain="datadoghq.com",  name="Datadog",    method="scripts"),
    DetectedVendor(domain="vercel.com",     name="Vercel",     method="dns"),
    DetectedVendor(domain="sentry.io",      name="Sentry",     method="scripts")
];

# vendor domain -> its disclosed sub-processors, already entity-resolved to canonical.
# (Real B: extract via `by llm`, then canonicalize via `by llm` against `known`.)
glob DEMO_SUBPROCESSORS: dict[str, list[ResolvedSubprocessor]] = {
    "openai.com":    [ResolvedSubprocessor(canonical_name="Microsoft Azure", purpose="model hosting / compute",      region="us")],
    "anthropic.com": [ResolvedSubprocessor(canonical_name="AWS",             purpose="model hosting / compute",      region="us"),
                      ResolvedSubprocessor(canonical_name="Google Cloud",    purpose="training infrastructure",      region="us")],
    "openrouter.ai": [ResolvedSubprocessor(canonical_name="AWS",             purpose="API gateway / compute",        region="us"),
                      ResolvedSubprocessor(canonical_name="Cloudflare",      purpose="edge routing / CDN",           region="global")],
    "github.com":    [ResolvedSubprocessor(canonical_name="Microsoft Azure", purpose="source + CI hosting",          region="us")],
    "stripe.com":    [ResolvedSubprocessor(canonical_name="AWS",             purpose="payment processing / compute", region="us")],
    "datadoghq.com": [ResolvedSubprocessor(canonical_name="AWS",             purpose="error + log ingestion (PII)",  region="us")],
    "vercel.com":    [ResolvedSubprocessor(canonical_name="AWS",             purpose="serverless compute",           region="us"),
                      ResolvedSubprocessor(canonical_name="Cloudflare",      purpose="edge network / CDN",           region="global")],
    "sentry.io":     [ResolvedSubprocessor(canonical_name="Fastly",          purpose="error payload delivery (PII)", region="us")]
};

# curated provider risk/downtime asset (same curated data as the registry).
glob PROVIDER_REGISTRY: dict[str, ProviderProfile] = {
    "AWS":             ProviderProfile(category="cloud", downtime_hours_ytd=9.2, soc2=True,  hipaa=True,  supply_chain_risk=""),
    "Microsoft Azure": ProviderProfile(category="cloud", downtime_hours_ytd=5.1, soc2=True,  hipaa=True,  supply_chain_risk=""),
    "Google Cloud":    ProviderProfile(category="cloud", downtime_hours_ytd=3.4, soc2=True,  hipaa=True,  supply_chain_risk=""),
    "Cloudflare":      ProviderProfile(category="cdn",   downtime_hours_ytd=7.7, soc2=True,  hipaa=False, supply_chain_risk=""),
    "Fastly":          ProviderProfile(category="cdn",   downtime_hours_ytd=4.3, soc2=False, hipaa=False, supply_chain_risk="watchlist")
};

glob VENDOR_FEATURES: dict[str, str] = {
    "openai.com":    "AI generation",
    "anthropic.com": "AI generation",
    "openrouter.ai": "AI generation",
    "github.com":    "source + CI",
    "stripe.com":    "payments",
    "datadoghq.com": "error monitoring",
    "vercel.com":    "hosting",
    "sentry.io":     "error monitoring"
};

# ------------------------------------------------------------------ frozen A<->B API
def detect_all(domain: str) -> list[DetectedVendor] {
    # Real B: MX / SPF-DMARC / CNAME / HTTP headers / <script> tags + IP-range -> cloud.
    return DEMO_VENDORS if domain == "jachammer.ai" else [];
}

def resolve_url(domain: str) -> str {
    # Real B: exact registry -> fuzzy match -> ReAct `find_dpa_url` agent.
    return f"cache://{domain}" if domain in DEMO_SUBPROCESSORS else "";
}

async def fetch_page(url: str) -> str {
    # Real B: httpx w/ real UA, 5s timeout, concurrency ~10, cache by domain.
    return url.replace("cache://", "") if url.startswith("cache://") else "";
}

def extract_and_resolve(page_text: str, known: list[str]) -> list[ResolvedSubprocessor] {
    # Real B: extract_subprocessors (by llm, sem) + canonicalize (by llm) against `known`.
    _ = known;
    return DEMO_SUBPROCESSORS[page_text] if page_text in DEMO_SUBPROCESSORS else [];
}

def provider_profile(name: str) -> ProviderProfile {
    return PROVIDER_REGISTRY[name] if name in PROVIDER_REGISTRY else ProviderProfile();
}

def vendor_feature(domain: str) -> str {
    return VENDOR_FEATURES[domain] if domain in VENDOR_FEATURES else "";
}

# ------------------------------------------------------------------ narrative outputs
# Deterministic now (rehearsed path stays offline); B/C swap bodies to `by llm`.
def draft_status_update(provider: str, features: list[str]) -> str {
    feats = ", ".join(features) if features else "several services";
    return f"We are aware of a degradation affecting {feats} stemming from an upstream {provider} incident. We are monitoring recovery and will update every 30 minutes.";
}

def explain_fallout(vendor: str, provider: str) -> str {
    return f"{vendor} routes regulated data through {provider}, whose attestation is invalid — your SOC 2 inherits the gap.";
}

def explain_change(added: list[str]) -> str {
    return f"{len(added)} new sub-processor(s) appeared since the last snapshot: {', '.join(added)}. Review your right-to-object window.";
}

def compose_one_look(chokepoints: list[dict], fallout: list[dict]) -> RiskHeadline {
    if not chokepoints {
        return RiskHeadline(
            biggest_risk="No concentration detected yet — expand the graph.",
            biggest_suggestion="Add your vendor stack, then expand.");
    }
    top = chokepoints[0];
    pct = round((top["share"] as float) * 100);
    risk = f"{top['provider']} carries {pct}% of your stack ({top['vendors_affected']} of your vendors) and logged {top['downtime_hours_ytd']}h of downtime last year — the single highest expected-exposure dependency.";
    names = top["names"] as list;
    tail = names[-1] if names else "a vendor";
    sug = f"Move one dependency off {top['provider']}: re-homing {tail} severs a shared path and drops your concentration below the danger line.";
    if fallout {
        f0 = fallout[0];
        sug = f"Re-home {f0['vendor']} off {f0['provider']} first — it closes the compliance gap and severs an {top['provider']} path in one move.";
    }
    return RiskHeadline(biggest_risk=risk, biggest_suggestion=sug);
}
