# Blast Radius — shared context for frontend drafts

## Product
**Blast Radius** — hackathon project (JackHacks Jul 2026), track: Agentic AI + Jac.
One-liner: *"Your vendors have vendors."* We map the second layer of a company's
SaaS stack from vendors' own legal filings (subprocessor lists), find the single
point of failure your "redundant" stack secretly shares, and turn it into a risk
memo, a live outage simulation, and a compliance-fallout report.

Key concepts to dramatize:
- org → vendors → providers (3 tiers). The org thinks it has 8 independent vendors;
  really 5 of them secretly ride on AWS.
- **Chokepoint**: AWS carries 62% of the stack (5/8 vendors), 9.2h downtime YTD →
  exposure score 5.75 (share × downtime).
- **Blast radius**: click a provider (e.g. AWS) → animated backward propagation
  showing which vendors + features go down (AI generation, payments, error
  monitoring, hosting).
- **Compliance fallout**: Sentry ingests error payloads (may contain PII) through
  Fastly — no valid SOC 2, supply-chain watchlist → your SOC 2 inherits the gap.
- **One-look headline**: "AWS carries 62% of your stack (5 of 8 vendors) and logged
  9.2h of downtime last year." Suggestion: "Move error monitoring + one CDN path
  off AWS-bound vendors: a single migration severs 2 of the 5 shared AWS paths."

## Demo graph (use this exact data — hardcode it into the page)
```json
{
  "nodes": [
    {"id":"jachammer.ai","label":"JacHammer","tier":"org","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"openai","label":"OpenAI","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"anthropic","label":"Anthropic","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"openrouter","label":"OpenRouter","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"github","label":"GitHub","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"stripe","label":"Stripe","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"datadog","label":"Datadog","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"vercel","label":"Vercel","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"sentry","label":"Sentry","tier":"vendor","inbound_degree":0,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":0.0},
    {"id":"aws","label":"AWS","tier":"provider","inbound_degree":5,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":9.2},
    {"id":"azure","label":"Microsoft Azure","tier":"provider","inbound_degree":2,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":5.1},
    {"id":"gcp","label":"Google Cloud","tier":"provider","inbound_degree":1,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":3.4},
    {"id":"cloudflare","label":"Cloudflare","tier":"provider","inbound_degree":2,"soc2":true,"supply_chain_risk":"","downtime_hours_ytd":7.7},
    {"id":"fastly","label":"Fastly","tier":"provider","inbound_degree":1,"soc2":false,"supply_chain_risk":"watchlist","downtime_hours_ytd":4.3}
  ],
  "edges": [
    {"source":"jachammer.ai","target":"openai","kind":"uses"},
    {"source":"jachammer.ai","target":"anthropic","kind":"uses"},
    {"source":"jachammer.ai","target":"openrouter","kind":"uses"},
    {"source":"jachammer.ai","target":"github","kind":"uses"},
    {"source":"jachammer.ai","target":"stripe","kind":"uses"},
    {"source":"jachammer.ai","target":"datadog","kind":"uses"},
    {"source":"jachammer.ai","target":"vercel","kind":"uses"},
    {"source":"jachammer.ai","target":"sentry","kind":"uses"},
    {"source":"openai","target":"azure","kind":"subprocesses"},
    {"source":"github","target":"azure","kind":"subprocesses"},
    {"source":"anthropic","target":"aws","kind":"subprocesses"},
    {"source":"anthropic","target":"gcp","kind":"subprocesses"},
    {"source":"openrouter","target":"aws","kind":"subprocesses"},
    {"source":"openrouter","target":"cloudflare","kind":"subprocesses"},
    {"source":"stripe","target":"aws","kind":"subprocesses"},
    {"source":"datadog","target":"aws","kind":"subprocesses"},
    {"source":"vercel","target":"aws","kind":"subprocesses"},
    {"source":"vercel","target":"cloudflare","kind":"subprocesses"},
    {"source":"sentry","target":"fastly","kind":"subprocesses"}
  ]
}
```

## Tech constraints
- ONE self-contained static `index.html` per draft (inline CSS/JS; CDN libraries OK —
  Google Fonts, D3, Three.js, GSAP, canvas, WebGL, whatever). No build step.
- Serve via `file://` — absolute file URL works in the browser tool.
- Must run at 1440×900 and survive being opened offline-ish (CDN is fine).

## Adversarial browser review protocol (MANDATORY, do it for real)
You are both the designer AND a hostile reviewer. After building:
1. `open` the browser tool on your file URL at 1440×900.
2. Screenshot. Then critique it like a design critic who hates you:
   - clipped/overflowing text, overlapping graph labels, unreadable contrast
   - dead empty space, orphaned sections, weak focal hierarchy
   - animation jank, elements animating layout instead of transform
   - anything that looks like generic AI slop (Inter font, purple-on-white gradient, cookie-cutter hero)
   - graph: is AWS visibly the chokepoint? is the blast-radius interaction legible?
3. Fix at least 3 concrete issues. Re-screenshot.
4. Interact: trigger the blast-radius click/hover on AWS via the browser, screenshot
   mid-state. Verify highlight logic actually works.
5. Repeat critique→fix until you can't find a real defect. Minimum 2 full rounds.
6. Save final screenshot to your draft dir as `screenshot.png` and the blast-radius
   interaction shot as `screenshot-blast.png`.
