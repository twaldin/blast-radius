"""Blast Radius — API stub.

Frozen walker contracts + sample jachammer.ai demo data so the frontend can build
against real endpoints immediately. Person A replaces the hardcoded reports with real
graph traversal and swaps `walker:pub` -> `walker:priv` (per-user root isolation).

Run:  jac start main.jac --port 8000
Then: curl -X POST localhost:8000/walker/expand -H 'content-type: application/json' -d '{}'
"""

import from contracts { DetectedVendor }

# ------------------------------------------------------------------ sample graph
# jachammer.ai -> vendors -> providers. AWS is the chokepoint (5 of 8 vendors).
glob NODES: list[dict] = [
    {"id": "jachammer.ai", "label": "JacHammer",  "tier": "org",      "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "openai",       "label": "OpenAI",     "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "anthropic",    "label": "Anthropic",  "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "openrouter",   "label": "OpenRouter", "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "github",       "label": "GitHub",     "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "stripe",       "label": "Stripe",     "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "datadog",      "label": "Datadog",    "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "vercel",       "label": "Vercel",     "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "sentry",       "label": "Sentry",     "tier": "vendor",   "inbound_degree": 0, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 0.0},
    {"id": "aws",          "label": "AWS",        "tier": "provider", "inbound_degree": 5, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 9.2},
    {"id": "azure",        "label": "Microsoft Azure", "tier": "provider", "inbound_degree": 2, "soc2": True, "supply_chain_risk": "",       "downtime_hours_ytd": 5.1},
    {"id": "gcp",          "label": "Google Cloud", "tier": "provider", "inbound_degree": 1, "soc2": True, "supply_chain_risk": "",          "downtime_hours_ytd": 3.4},
    {"id": "cloudflare",   "label": "Cloudflare", "tier": "provider", "inbound_degree": 2, "soc2": True,  "supply_chain_risk": "",          "downtime_hours_ytd": 7.7},
    {"id": "fastly",       "label": "Fastly",     "tier": "provider", "inbound_degree": 1, "soc2": False, "supply_chain_risk": "watchlist", "downtime_hours_ytd": 4.3}
];

glob EDGES: list[dict] = [
    {"source": "jachammer.ai", "target": "openai",     "kind": "uses"},
    {"source": "jachammer.ai", "target": "anthropic",  "kind": "uses"},
    {"source": "jachammer.ai", "target": "openrouter", "kind": "uses"},
    {"source": "jachammer.ai", "target": "github",     "kind": "uses"},
    {"source": "jachammer.ai", "target": "stripe",     "kind": "uses"},
    {"source": "jachammer.ai", "target": "datadog",    "kind": "uses"},
    {"source": "jachammer.ai", "target": "vercel",     "kind": "uses"},
    {"source": "jachammer.ai", "target": "sentry",     "kind": "uses"},
    {"source": "openai",     "target": "azure",      "kind": "subprocesses"},
    {"source": "github",     "target": "azure",      "kind": "subprocesses"},
    {"source": "anthropic",  "target": "aws",        "kind": "subprocesses"},
    {"source": "anthropic",  "target": "gcp",        "kind": "subprocesses"},
    {"source": "openrouter", "target": "aws",        "kind": "subprocesses"},
    {"source": "openrouter", "target": "cloudflare", "kind": "subprocesses"},
    {"source": "stripe",     "target": "aws",        "kind": "subprocesses"},
    {"source": "datadog",    "target": "aws",        "kind": "subprocesses"},
    {"source": "vercel",     "target": "aws",        "kind": "subprocesses"},
    {"source": "vercel",     "target": "cloudflare", "kind": "subprocesses"},
    {"source": "sentry",     "target": "fastly",     "kind": "subprocesses"}
];

# ------------------------------------------------------------------ endpoints
# POST /walker/detect_vendors  {"domain": "jachammer.ai"}
walker:pub detect_vendors {
    has domain: str = "jachammer.ai";
    can run with Root entry {
        report {
            "found": 3,
            "vendors": [
                {"domain": "aws.amazon.com", "name": "AWS",              "method": "dns"},
                {"domain": "amazonaws.com",  "name": "AWS Route 53",     "method": "dns"},
                {"domain": "aws.amazon.com", "name": "AWS (us-east-2)",  "method": "headers"}
            ]
        };
    }
}

# POST /walker/expand  {}   -> full graph for the force canvas
walker:pub expand {
    can run with Root entry {
        report {"nodes": NODES, "edges": EDGES};
    }
}

# POST /walker/chokepoints  {}  -> ranked shared providers (share x downtime = exposure)
walker:pub chokepoints {
    can run with Root entry {
        report [
            {"provider": "AWS",        "vendors_affected": 5, "share": 0.625, "downtime_hours_ytd": 9.2, "exposure": 5.75, "names": ["Anthropic", "OpenRouter", "Stripe", "Datadog", "Vercel"]},
            {"provider": "Microsoft Azure", "vendors_affected": 2, "share": 0.25, "downtime_hours_ytd": 5.1, "exposure": 1.28, "names": ["OpenAI", "GitHub"]},
            {"provider": "Cloudflare", "vendors_affected": 2, "share": 0.25, "downtime_hours_ytd": 7.7, "exposure": 1.93, "names": ["OpenRouter", "Vercel"]}
        ];
    }
}

# POST /walker/blast_radius  {"failed_provider": "AWS"}
walker:pub blast_radius {
    has failed_provider: str = "AWS";
    can run with Root entry {
        report {
            "provider": "AWS",
            "vendors_down": ["Anthropic", "OpenRouter", "Stripe", "Datadog", "Vercel"],
            "features_down": ["AI generation", "payments", "error monitoring", "hosting"],
            "status_post": "We are aware of a degradation affecting AI generation, payments, and hosting stemming from an upstream AWS us-east-2 incident. We are monitoring recovery and will update every 30 minutes."
        };
    }
}

# POST /walker/compliance_fallout  {}  -> SOC2/HIPAA/watchlist gaps that propagate up
walker:pub compliance_fallout {
    can run with Root entry {
        report [
            {"vendor": "Sentry", "provider": "Fastly", "reason": "supply-chain watchlist; no valid SOC 2",
             "breaks": "Sentry ingests error payloads (may contain PII) through Fastly, whose attestation is invalid — your SOC 2 inherits the gap."}
        ];
    }
}

# POST /walker/one_look  {}  -> the two-sentence headline
walker:pub one_look {
    can run with Root entry {
        report {
            "biggest_risk": "AWS carries 62% of your stack (5 of 8 vendors) and logged 9.2h of downtime last year — the single highest expected-exposure dependency.",
            "biggest_suggestion": "Move error monitoring + one CDN path off the AWS-bound vendors: a single migration severs 2 of the 5 shared AWS paths."
        };
    }
}

# ------------------------------------------------------------------ client mount (C)
def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
