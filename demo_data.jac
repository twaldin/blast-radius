"""Deterministic JacHammer demo fixture and narrative helpers.

The real registry/extraction pipeline lives in `extract.jac`. This module owns only
the pre-warmed eight-vendor demo data needed for a fast, network-independent stage
run, plus curated provider risk and deterministic narrative helpers.
"""

import from contracts { DetectedVendor, ResolvedSubprocessor, RiskHeadline }

# ------------------------------------------------------------------ curated demo asset
obj ProviderProfile {
    has category: str = "";
    has downtime_hours_ytd: float = 0.0;
    has soc2: bool = True;
    has hipaa: bool = False;
    has supply_chain_risk: str = "";      # "" | watchlist | sanctioned | foreign-owned
    has slug: str = "";                   # UI id override; blank = A slugifies the name
    has is_sink: bool = False;            # terminal hyperscaler: no useful deeper layer
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
    "AWS":             ProviderProfile(category="cloud", downtime_hours_ytd=9.2, soc2=True,  hipaa=True,  supply_chain_risk="", slug="aws",   is_sink=True),
    "Microsoft Azure": ProviderProfile(category="cloud", downtime_hours_ytd=5.1, soc2=True,  hipaa=True,  supply_chain_risk="", slug="azure", is_sink=True),
    "Google Cloud":    ProviderProfile(category="cloud", downtime_hours_ytd=3.4, soc2=True,  hipaa=True,  supply_chain_risk="", slug="gcp",   is_sink=True),
    "Cloudflare":      ProviderProfile(category="cdn",   downtime_hours_ytd=7.7, soc2=True,  hipaa=False, supply_chain_risk="", slug="cloudflare"),
    "Fastly":          ProviderProfile(category="cdn",   downtime_hours_ytd=4.3, soc2=False, hipaa=False, supply_chain_risk="watchlist", slug="fastly")
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

# ------------------------------------------------------------------ demo discovery
def detect_all(domain: str) -> list[DetectedVendor] {
    return DEMO_VENDORS if domain == "jachammer.ai" else [];
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
        sug = f"Re-home {f0['vendor']} off {f0['provider']} to close the compliance gap; then move {tail} off {top['provider']} to reduce chokepoint concentration.";
    }
    return RiskHeadline(biggest_risk=risk, biggest_suggestion=sug);
}
