# Blast Radius — Build Spec
**JacHacks SF · Main track: Agentic AI · Subprizes targeted: best use of Jac, best use of JacHammer, AI for Defense**

> Your vendors have vendors. Blast Radius maps that second layer, finds the single points of failure hiding behind your "redundant" stack, and turns the result into the three artifacts you actually owe someone.

* * *
## 1. The problem
A 30-person startup uses somewhere between 30 and 60 SaaS vendors. Leadership can name them. What nobody can name is what those vendors run on.

Stripe, Vercel, Notion, Twilio, and Datadog are five companies, five contracts, five invoices. They are also, underneath, largely one company. When a major cloud region degrades, all five degrade together, and most teams learn this from Twitter rather than from their own risk register.

That second layer is public. GDPR Article 28 requires every processor to disclose its sub-processors, so essentially every B2B SaaS company publishes a subprocessor list on its website. The data exists. Nobody assembles it, because assembling it by hand means reading 40 legal pages, normalizing 40 inconsistent tables, and redoing the whole thing every quarter.

**Who feels this today, concretely:**

- **Startups selling to enterprise.** SOC 2 and every serious security questionnaire require a maintained vendor inventory, a published subprocessor list of your own, and a written answer to "how do you manage concentration risk in your supply chain." Someone loses days a year to this in a spreadsheet, and it's stale on delivery.
  
- **Fintechs.** Their bank partners push third-party risk requirements downstream contractually. Concentration risk is named explicitly in FFIEC and OCC third-party guidance and in EU DORA.
  
- **Anyone who has ever written an incident post-mortem** that contained the phrase "we did not realize these systems shared a dependency."
  
## 2. What it does
Not a visualization. Concrete actions with outputs someone uses — one unified risk read across commercial and defense supply chains.
### Action 1 — Generate the artifact you owe someone
Output: a vendor inventory table plus a written concentration-risk assessment, exportable, ready to paste into a security questionnaire or hand to an auditor. This is the thing that currently costs days.
### Action 2 — Monitor for change
Vendors add subprocessors quietly. Most DPAs give you a contractual right to notice and often a right to object — a right nobody exercises, because nobody notices. A scheduled walker re-crawls weekly and diffs the graph: _"Notion added a new subprocessor on Nov 3. You have 30 days to object under §7.2."_

This is the feature that makes it a product rather than a report, and in Jac it's nearly free because the graph persists by reachability.
### Action 3 — Incident triage
A provider goes down. You get the affected-vendor list, the affected-feature list, and a drafted customer status update — while everyone else is still guessing which systems are involved.
### Action 4 — Compliance fallout
Output: every vendor whose SOC 2 / HIPAA claim is silently invalidated by a _second-layer_ subprocessor that handles PII without a valid attestation, or that sits on a supply-chain watchlist. The gap propagates up the graph the same way an outage does — your compliance is only as valid as the deepest processor touching regulated data.
### Action 5 — The one-look risk read
Output: two sentences a CISO reads first — the single **biggest risk** (concentration × historical downtime → expected exposure) and the single **biggest suggestion** (the one migration that severs the most shared paths). Fits on a phone.

All of this runs on **one screen, one engine** — commercial SaaS and DoD supply chains share the same graph, the same walkers, and the same one-look read; only the data adapter changes.
### What it is not
State these boundaries out loud in the pitch; it buys credibility.

- Not a security-posture score. No opinion on whether a vendor is well-run.
  
- Not exhaustive. It sees externally visible and publicly disclosed relationships. Internal tools must be entered manually.
  
- Not depth-unlimited. Two hops. See §5.4.
  
## 3. Graph model
```jac
node Org       { has domain: str; has name: str = ""; }
node Vendor    { has domain: str; has name: str;
                 has source_url: str = "";
                 has discovery_method: str = "";   # dns | headers | scripts | manual
                 has crawl_status: str = "pending"; }  # pending|ok|unreadable|notfound
node Provider  { has canonical_name: str; has category: str = "";
                 has downtime_hours_ytd: float = 0.0;   # curated historical outage -> risk weight
                 has soc2: bool = True; has hipaa: bool = False;
                 has supply_chain_risk: str = ""; }      # "" | watchlist | sanctioned | foreign-owned
node Region    { has code: str; }
node Feature   { has name: str; }
node Snapshot  { has taken_at: str; has vendor_count: int; has provider_count: int; }

edge Uses:          Org      --> Vendor   { has added_at: str = ""; }
edge Subprocesses:  Vendor   --> Provider { has purpose: str = "";
                                            has confidence: float = 1.0;
                                            has handles_pii: bool = False;   # gates compliance fallout
                                            has first_seen: str = "";
                                            has last_seen: str = ""; }
edge HostedIn:      Provider --> Region   {}
edge Powers:        Vendor   --> Feature  {}
edge CapturedAt:    Org      --> Snapshot {}
```

Declare the endpoint types. It isn't cosmetic — with endpoints declared, `[org ->:Uses:->]` infers `list[Vendor]` and field access resolves statically with no `[?:Type]` filter. Point this out to the Jaseci judges; it's a detail that signals you read the language reference rather than pattern-matching Python.

`Provider` is deliberately a separate type from `Vendor`. A company can be both (Twilio is a vendor of yours and a subprocessor of Notion's), and keeping them distinct keeps the concentration math honest.
## 4. Pipeline
```
domain ──> [detect] ──> Vendor nodes ──> [crawl] ──> raw page text
                             ↑                             │
                        manual add                         ▼
                                                    [extract by llm]
                                                           │
                                                           ▼
                                                  [canonicalize by llm]
                                                           │
                                                           ▼
                                                   Provider nodes + edges
                                                           │
                                                           ▼
                                          [chokepoints] [blast radius] [diff]
```
### 4.1 Detection — the judge-types-their-own-domain moment
There is no public record of which vendors a company uses. This has to be discovered or entered. Discovery gets you most of the way:

| Signal | What it reveals | Cost |
| --- | --- | --- |
| MX records | Google Workspace vs Microsoft 365 | 1 DNS query |
| SPF / DMARC TXT | SendGrid, Mailchimp, HubSpot, Zendesk, Postmark — anyone authorized to send as them | 1 DNS query |
| CNAMEs | Vercel, Netlify, Cloudflare, Shopify, Webflow | 1 DNS query |
| HTTP response headers | `x-vercel-id`, `cf-ray`, `x-served-by` (Fastly), `x-amz-*` | 1 GET |
| `<script>` tags on the marketing site | Segment, Intercom, PostHog, GA, Stripe.js, Sentry, Hotjar | same GET |
| Their own subprocessor page | the entire list, handed to you | 1 GET |

Realistically 8–12 vendors from a cold domain in under three seconds. Then a text box for what detection cannot see — Linear, payroll, the data warehouse.

Be honest in the UI that this finds _externally visible_ vendors. "I typed your domain and found nine of your vendors without you telling me anything" is a strong claim precisely because it's a true one.
### 4.2 The registry — build this first
A hardcoded map of ~150 common B2B SaaS vendors to their exact subprocessor page URL. Stripe, Vercel, Notion, Twilio, Datadog, Slack, Linear, Segment, Sentry, Auth0, Zoom, HubSpot, Figma, GitHub, Cloudflare, Snowflake, Mixpanel, Intercom, and so on.

This covers roughly 90% of what any startup in that room actually uses, and it means the judge's vendors resolve **instantly, off cache, with no network call.** That's the difference between a product and a scraper.

It is not a shortcut — a real company would maintain exactly this asset, and it is most of the defensible value.
### 4.3 Discovery fallback — the agentic long-tail hunter
**This is the Agentic AI hero, but it comes after the deterministic demo is
deployed.** For anything not in the registry, let the Jac ReAct agent plan a
bounded hunt using narrow discovery tools. Firecrawl is the primary web layer:
`search` locates candidates and `scrape` extracts a known URL. Browser Harness is
a separate escalation for trust-center click-throughs and other interactions
that search/scrape cannot complete; the agent does not receive unrestricted CDP.

Resolution order, cheapest first:

1. **Exact registry hit** → cached URL, zero network. The scripted demo path lives here.
  
2. **Fuzzy match** the typed name against the registry + already-resolved `Provider` names (`"openai"` → OpenAI). Deterministic, no LLM — keeps the common case instant.
  
3. **ReAct agent**, only on a genuine miss:
  

```jac
def find_dpa_url(domain: str) -> str by llm(
    tools=[firecrawl_search, firecrawl_scrape, browser_harness_render],
    max_react_iterations=6
);
sem find_dpa_url =
    "Find this company's complete current named subprocessor list. Search for "
    "official-company or verified-GitHub candidates, scrape likely URLs, and "
    "use the browser escalation only for a required click-through or failed "
    "render. Return one authoritative URL, or empty if none.";
sem find_dpa_url.domain = "The vendor's root domain, e.g. 'linear.app'.";
```

Each tool is one narrow Jac `def` with its own `sem`; the agent chooses what to
call and when. Deterministic code still validates domain ownership, completeness,
page limits, timeouts, and the final evidence before learning the result.
`tools=[...]` activates the ReAct loop. Do not nest Firecrawl Agent inside the
first version of our ReAct agent: that obscures the Jac planning story and adds
another asynchronous cost/latency layer.

Keep the agent off the rehearsed path: registry + fuzzy resolve the scripted vendors instantly and offline. The agent fires live only on the judge's own unindexed vendor — which is also the most impressive thing on screen.

**Known limitation, worth saying out loud:** Some trust centers require client
rendering or click-throughs. Firecrawl handles the ordinary rendered/search case;
the bounded Browser Harness escalation handles supported interactive cases.
Anything still incomplete surfaces as `notfound`—never as a guessed or partial
company graph.
### 4.4 Fetch mechanics
```jac
import httpx;
import trafilatura;

async def fetch_page(url: str) -> str {
    async with httpx.AsyncClient(
        timeout=5.0, follow_redirects=True,
        headers={"User-Agent": "Mozilla/5.0 (compatible; BlastRadius/0.1)"}
    ) as c {
        r = await c.get(url);
        if r.status_code != 200 { return ""; }
        return trafilatura.extract(r.text) or "";
    }
}
```

Bare Python user-agents get 403'd — set a real one. Five-second timeout, concurrency capped around 10, cache keyed by domain so re-running mid-pitch is free.
## 5. The Jac core
### 5.1 Extraction — do not write a table parser
These pages are HTML tables with wildly inconsistent columns: Name / Purpose / Location / Legal Entity, in any order, sometimes nested, sometimes prose. A parser for 150 layouts is a week of work. A typed return signature is one line.

```jac
obj SubprocessorRecord {
    has name: str;
    has purpose: str = "";
    has hosting_region: str = "";
}

"""Extract every named subprocessor from a vendor's DPA or subprocessor page."""
def extract_subprocessors(page_text: str) -> list[SubprocessorRecord] by llm();
sem extract_subprocessors =
    "Return one record per third-party company named as a subprocessor or "
    "sub-processor. Ignore the vendor's own legal entities and ignore any "
    "company named only as an example or in boilerplate.";
```
### 5.2 Entity resolution — the load-bearing LLM call
This is the one to talk about. Stripe writes "Amazon Web Services, Inc." Notion writes "AWS." Vercel writes "Amazon Web Services EMEA SARL." Those are one company. Without resolution the graph shows three separate providers, each with one inbound edge, and **the chokepoint never appears.** The entire insight depends on this step.

```jac
"""Map a raw vendor-listed name to its canonical provider identity."""
def canonicalize(raw: str, known: list[str]) -> str by llm();
sem canonicalize =
    "Resolve aliases and legal entity variants to one canonical name. "
    "'AWS', 'Amazon Web Services, Inc.', and 'Amazon Web Services EMEA SARL' "
    "are all 'Amazon Web Services'. If the name matches nothing in the known "
    "list, return it cleaned of legal suffixes.";
```

Pitch line: _"The graph only converges because the language does the entity resolution. That's not a prompt I wrote — it's a type signature."_
### 5.3 Walkers — each one is a REST endpoint for free
```jac
walker:priv DetectVendors {
    has domain: str;
    can run with Root entry {
        org = here ++> Org(domain=self.domain);
        for v in detect_all(self.domain) {              # dns + headers + scripts
            org +>: Uses(added_at=now()) :+> Vendor(
                domain=v.domain, name=v.name, discovery_method=v.method
            );
        }
        report {"found": len([org ->:Uses:->])};
    }
}

walker:priv AddVendors {           # the manual text box
    has domains: list[str];
    can run with Root entry { ... }
}
```

```jac
walker:priv Expand {
    has max_depth: int = 2;
    has depth: int = 0;
    has seen: set[str] = {};

    can start with Org entry { visit [->:Uses:->]; }

    can crawl with Vendor entry {
        if self.depth >= self.max_depth or jid(here) in self.seen { skip; }
        self.seen.add(jid(here));

        url = resolve_url(here.domain);        # registry, then discovery
        if not url { here.crawl_status = "notfound"; skip; }

        text = await fetch_page(url);
        if not text { here.crawl_status = "unreadable"; skip; }

        here.source_url = url;
        here.crawl_status = "ok";
        known = [p.canonical_name for p in [root -->[?:Provider]]];

        for rec in extract_subprocessors(text) {
            name = canonicalize(rec.name, known);
            prov = find_or_create_provider(name);
            here +>: Subprocesses(purpose=rec.purpose, last_seen=now()) :+> prov;
        }
        visit [->:Subprocesses:->];
    }
}
```

Three things to say about this walker when you pitch:

- **BFS is the default.** `visit [-->]` appends to the end of the walker's queue, so breadth-first expansion is the language's default traversal semantic. `visit :0: [-->]` would make it depth-first. You didn't write a crawl frontier; you declared one.
  
- **The** `seen` **guard is required, not defensive.** The graph has genuine cycles — AWS's own subprocessors use AWS — and the Jac docs warn that separate `visit` statements can each enqueue the same node.
  
- **Depth 2, deliberately.** 30 vendors × ~15 subprocessors is ~450 nodes at depth 2, and thousands at depth 3, each one an LLM call. Worse, depth 3 has no information in it: everything terminates at AWS, GCP, Azure, or Cloudflare, which every judge already knows. The insight lives at the layer nobody looks at. "Your vendors, and their vendors" is also a sentence a judge parses instantly, which "transitive closure of the supply graph" is not.
  

```jac
walker:priv Chokepoints {
    can run with Org entry {
        vendors = [here ->:Uses:->];
        scored = [];
        for prov in [root -->[?:Provider]] {
            dependents = [prov <-:Subprocesses:<-];       # inbound traversal
            exposed = [v for v in dependents if v in vendors];
            if exposed {
                scored.append({
                    "provider": prov.canonical_name,
                    "vendors_affected": len(exposed),
                    "share": len(exposed) / len(vendors),
                    "names": [v.name for v in exposed]
                });
            }
        }
        scored.sort(key=lambda (x: any) { x["vendors_affected"]; }, reverse=True);
        report scored;
    }
}
```

`[prov <-:Subprocesses:<-]` is the whole product in one line. That query — _who transitively depends on this_ — is the thing a spreadsheet structurally cannot answer and a graph answers for free.

```jac
walker:priv BlastRadius {
    has failed_provider: str;
    can run with Org entry {
        prov = lookup_provider(self.failed_provider);
        hit = [v for v in [prov <-:Subprocesses:<-] if v in [here ->:Uses:->]];
        features = [];
        for v in hit { features += [f.name for f in [v ->:Powers:->]]; }
        report {
            "provider": self.failed_provider,
            "vendors_down": [v.name for v in hit],
            "features_down": list(set(features)),
            "status_post": draft_status_update(self.failed_provider,
                                               list(set(features)))
        };
    }
}
```

```jac
@schedule(trigger="cron", day_of_week="mon", hour=9)
walker:priv DiffMonitor {
    can run with Org entry {
        before = snapshot_edges(here);
        here spawn Expand();
        after = snapshot_edges(here);
        added = after - before;
        if added { report {"new_subprocessors": list(added),
                           "notice": explain_change(list(added))}; }
    }
}
```
### 5.4 The narrative LLM calls
Two, both producing the deliverable rather than chatting:

```jac
"""Write the third-party concentration risk section of a security questionnaire."""
def risk_memo(chokepoints: list[dict], vendor_count: int) -> str by llm();

"""Draft a customer-facing status update for a provider outage."""
def draft_status_update(provider: str, features: list[str]) -> str by llm();
```
### 5.5 Compliance fallout, downtime-weighted risk, and the one-look read
Three products ride on the graph you already built — no new traversal engine, just more to say when a walker arrives at a node. All three reuse the one inbound query `[prov <-:Subprocesses:<-]`.

**Compliance fallout (SOC 2 / HIPAA).** If a _second-layer_ subprocessor handles PII and lacks a valid SOC 2 / HIPAA attestation (or sits on a supply-chain watchlist), every vendor above it inherits the gap. Invalidity propagates _up the inbound edges_, exactly like an outage does — a non-compliant node and a down node propagate identically; only the label changes.

```jac
walker:priv ComplianceFallout {
    can run with Org entry {
        flagged = [];
        for prov in [root -->[?:Provider]] {
            gap = (not prov.soc2) or (prov.supply_chain_risk != "");
            if not gap { continue; }
            for v in [prov <-:Subprocesses:<-] {          # who inherits the gap
                if v in [here ->:Uses:->] {
                    flagged.append({
                        "vendor": v.name, "provider": prov.canonical_name,
                        "reason": prov.supply_chain_risk or "no valid SOC 2",
                        "breaks": explain_fallout(v.name, prov.canonical_name)
                    });
                }
            }
        }
        report flagged;
    }
}
```

**Downtime-weighted risk.** A chokepoint's severity is `share × historical-downtime`. AWS carrying 71% of your stack matters more if it went down 9 hours last year than if it never did. `Provider.downtime_hours_ytd` (seeded per provider — the same curated asset as the registry) turns a structural share into an expected-exposure number.

**The one-look read.** The headline, computed over the scored chokepoints + fallout: the single **biggest risk** and the single **biggest suggestion**, one sentence each. It is what a CISO reads first and what fits on a phone.

```jac
obj RiskHeadline { has biggest_risk: str; has biggest_suggestion: str; }

"""Pick the highest expected-exposure chokepoint and the one remediation that severs the most shared paths."""
def one_look(chokepoints: list[dict], fallout: list[dict]) -> RiskHeadline by llm();
```

Defense and commercial run on this **identical engine, same screen** — not a separate tab. A DoD prime -> subcontractor -> tier-3 supplier graph has the same chokepoints (one machine shop three primes share), the same fallout (a tier-3 supplier on a sanctions watchlist), and the same one-look read. The only difference is the data adapter that seeds the graph.
## 6. Frontend — same file
```jac
cl def:pub app -> JsxElement {
    has org_domain: str = "";
    has graph: dict = {};
    has chokepoints: list = [];
    has simulating: str = "";
    ...
}
```

Force-directed graph, three columns: you → vendors → providers. Node size by inbound degree so chokepoints are visually obvious before anyone reads a number. On outage simulation, tint the affected subgraph red. Stream crawl progress over the built-in WebSocket so nodes visibly appear one at a time — the build _is_ the demo.

Also worth doing: a coverage strip showing `ok / unreadable / notfound` counts. Honesty reads as rigor.
### 6.1 The visualization — Person C, read this carefully
The graph is what makes the chokepoint number land emotionally. But the _default_ version of this looks bad, and the specific choices below are the difference between "sick" and "noisy."

**The trap.** 34 vendors × ~15 subprocessors is ~450 nodes. Turn a force simulation loose on that and you get a hairball: impressive for three seconds, then unreadable, and the judge cannot find the thing you're pointing at.

**The fix — constrain x by tier, let force solve only y.**

This is the single biggest visual win in the project. Pin each node's horizontal position by its tier and let the simulation resolve vertical placement only. Now it reads like a Sankey diagram, and the convergence becomes _structurally_ visible: many vendors on the left funneling into a few fat nodes on the right. The picture argues your thesis before you open your mouth.

```js
// react-force-graph-2d, via plain npm import
const TIER_X = { org: 0.15, vendor: 0.5, provider: 0.85 };

<ForceGraph2D
  graphData={graph}
  dagMode={null}
  d3VelocityDecay={0.3}
  // lock x to the node's tier, force only resolves y
  nodeCanvasObject={drawNode}
  onEngineTick={() => {
    graph.nodes.forEach(n => {
      n.fx = TIER_X[n.tier] * width;   // fx pins the axis
    });
  }}
/>
```

**Node sizing.** Providers scale by inbound degree, `sqrt` so AWS doesn't eat the canvas:

```js
const r = 4 + 10 * Math.sqrt(node.inbound_degree || 1);
```

The chokepoint is simply the biggest circle. No legend required.

**Aggressive pruning — render only providers with 2+ dependents.** Single-dependent providers collapse into one muted "other (n)" cluster node. This takes you from ~450 rendered nodes to roughly 80 and loses nothing, because a provider with one dependent is not a chokepoint by definition. Keep the full graph in Jac; prune only at render time.

**Labels.** Providers always. Vendors on hover only. Labeling all 450 is mud.

**Color discipline.** Dark background, one accent color for structure, and **red reserved exclusively for blast radius**. If red appears anywhere else in the UI — errors, warnings, badges — the outage moment loses its punch. Use amber for `unreadable` states.
### 6.2 The two money shots
**1. Backward propagation on outage simulation.** This is the frame people remember.

On _Simulate outage_: desaturate the entire graph to ~15% opacity, light the failed provider red, then animate the failure spreading **backwards** along inbound edges — provider → vendors → your features. Roughly 2 seconds, staggered per hop.

It is a literal rendering of `[prov <-:Subprocesses:<-]`. Say that out loud while it plays: _"that animation is one line of Jac."_

```js
// stagger by hop distance from the failed provider
const delay = hop * 350;  // ms
```

**2. The build itself.** WebSocket-stream the crawl so nodes fly in one at a time as each vendor resolves. Motion is what sells it.

**But batch the updates every ~200ms.** Recomputing the force layout on every single node arrival will jank badly on a projector, and a stuttering demo reads as broken rather than busy.

```js
// accumulate incoming nodes, flush on an interval
let pending = [];
ws.onmessage = e => pending.push(JSON.parse(e.data));
setInterval(() => {
  if (pending.length) { setGraph(g => merge(g, pending)); pending = []; }
}, 200);
```
### 6.3 Keep the admin portal separate
Jac's scale admin portal ships with its own built-in graph visualization. It's free and it proves the language claim, so show it — for about five seconds, at the end, as a "and the language just gives me this" beat.

Do **not** confuse it with your product canvas. Two different graphs on screen with no framing will read as one unpolished graph.
### 6.4 Test on the actual hardware
Render performance on a projector and on the judge's phone is not the same as on your laptop. Check both during rehearsal #1, not after. If the phone chokes, ship a static pre-rendered snapshot for the mobile view — nobody will know, and a smooth fake beats a stuttering real one at 2 minutes 30.
## 7. Deploy
```bash
jac start                 # walkers become REST endpoints, Swagger, JWT auth, SQLite
jac start --scale         # Kubernetes + Mongo + Redis, generated Dockerfile & manifests
```

`jac.toml` needs `[scale.database]` and `[scale.kubernetes]` declared, then `jac install` to pull the optional deps into `.jac/venv`.

**Deploy on JacHammer for the subprize**, get the public URL, and open it on the judge's phone via the mobile client. Mention scale-to-zero: the stable URL wakes a zero-replica deployment on request through jac-scale's KEDA autoscaler.

**Do this by mid-afternoon, on a two-node graph, before the real logic exists.** A working deploy beats one more feature, and deploy problems discovered at hour nine have killed better projects.

Run `jac clean --all` before any rehearsal of a graph demo or you will hit `NodeAnchor` errors on stage.
## 8. Demo script — 3 minutes
| Time | Beat |
| --- | --- |
| 0:00 | "Your vendors have vendors — and you've never seen that list. Watch me map the supply chain of JacHammer — the platform every project here deployed on today." |
| 0:20 | Type `jachammer.ai`. Detection fires live: its A-records resolve into **AWS** (us-east-2) and its DNS runs on Route 53 — the platform we're all deploying on today runs on AWS. |
| 0:40 | Add the stack a platform like this runs — its LLM providers (OpenAI / Anthropic / OpenRouter), GitHub, Stripe, its CDN, monitoring. Crawl starts; nodes stream in live. |
| 1:00 | **The agent moment.** One vendor isn't in the registry — the ReAct agent hunts live: tries the sitemap, checks the trust subdomain, reasons its way to the DPA. "The agent decides where to look." |
| 1:20 | **The reveal.** A dozen-plus vendors resolve to a handful of real providers. Chokepoint ranking. "The majority of this stack — JacHammer's own included — terminates at AWS. Your redundancy is a myth." |
| 1:40 | **One-look read:** biggest risk (AWS: top share × hours-down-last-year -> highest exposure) and biggest suggestion (the one migration that severs the most shared paths). Fits on a phone. |
| 2:00 | **Compliance fallout, same screen:** a tier-2 subprocessor handling PII has no valid SOC 2 -> the gap propagates up to three vendors. "Your SOC 2 is only as valid as the deepest processor." |
| 2:15 | Click _Simulate outage_. Subgraph goes red, backwards along inbound edges. Affected features + drafted status post. "That animation is one line of Jac." |
| 2:35 | Same engine, defense data: DoD prime -> sub -> tier-3. The one machine shop three redundant primes share. Same walkers, same screen. |
| 2:50 | Open the JacHammer URL on a phone. Admin portal's built-in graph + auto Swagger. "One file. `jac start --scale`. No Dockerfile, no tenancy code." |

Rehearse twice. Pre-warm the cache for your scripted vendor set so the rehearsed path never touches the network; keep the live path only for the judge's input, with a visible per-vendor spinner and a graceful timeout.
## 9. Subprize coverage
**Agentic AI (main track).** The hero is the discovery agent in §4.3: a `by llm(tools=[...])` ReAct loop that plans its own hunt for each vendor's DPA — sitemap, then trust subdomain, then path guesses, then web search — narrating each tool call on screen. That is the rubric's "Depth of Agentic Behavior" (planning + tool use), which a deterministic crawler fails. Say it plainly: _"this isn't a scraper with an if/elif chain — the agent decides where to look."_ Incident triage (Action 3) is the second agentic surface: on an outage it autonomously walks the blast radius and drafts the comms.

**Best use of Jac.** Say the words _object-spatial_, _meaning-typed_, _scale-invariant_ — Jaseci judges are listening for exactly those and most teams won't say them.

- The graph is the product, not a rendering of it. `[prov <-:Subprocesses:<-]` is the core algorithm.
  
- The _same_ inbound query `[prov <-:Subprocesses:<-]` powers outage blast radius, compliance fallout, and chokepoint ranking — one traversal, three products. That's OSP paying rent.
  
- Typed edge endpoints, so traversals infer concrete node types with no filters.
  
- `by llm()` for structured extraction _and_ entity resolution — the graph doesn't converge without the latter.
  
- Walkers as REST endpoints; `walker:priv` gives per-user root isolation for free.
  
- Async walkers for the parallel crawl; `@schedule` for the monitor; WebSocket for live build.
  
- Persistence by reachability — the diff monitor works with no database.
  
- Same file: `jac run` → `jac start` → `jac start --scale`, empty diff.
  

**Best use of JacHammer.** Deployed there, live public URL, demoed on the judge's phone through the mobile client, scale-to-zero called out.

**AI for Defense.** _Same engine, same screen, different data_ — not a separate tab. A DoD prime -> subcontractor -> tier-3 supplier graph runs through the identical chokepoint / fallout / one-look walkers: find the one small machine shop three nominally redundant primes depend on, or the tier-3 supplier on a sanctions watchlist whose risk propagates up. Frame it as **industrial base resilience and sustainment**, not weapons. The reframe costs a data adapter, not a rewrite.
## 10. Failure modes
| Risk | Mitigation |
|---|---|
| Live crawl flakes on stage | Pre-warmed cache for scripted vendors; live path only for judge input; graceful per-vendor timeout |
| Trust centers are client-rendered | Registry points at underlying HTML; mark `unreadable` and show coverage honestly |
| Entity resolution fails, no chokepoint appears | Seed the known-providers list with the obvious 20 so canonicalization has anchors |
| LLM cost / latency explosion | Depth cap 2, cache extractions by URL, batch where possible |
| 403s from bare user-agent | Real UA string, 5s timeout |
| `NodeAnchor` errors mid-demo | `jac clean --all` before every rehearsal |
| Deploy discovered broken at hour 9 | Deploy a stub by mid-afternoon |
| `jac-scale` plugin won't load (`requests` missing) | Its non-test deps omit `requests`; `pip install requests` into `.jac/venv` right after `jac install`. Verified failure today |
| `jac start --dev` proxy `ECONNREFUSED` (IPv6 `::1` vs IPv4 API) | Demo on the non-dev bundled server: `jac start main.jac --port N`, not `--dev`. Verified today |
| `react-force-graph-2d` npm import unverified in `.cl.jac` | Prove the import renders at the +10min checkpoint, alongside the multi-file compile. Fallback: hand-drawn canvas of the 3 tiers |
| byllm can't reach a model | **Resolved:** `model_name="openrouter/openai/gpt-4o-mini"` (extraction/canonicalize) + `openrouter/openai/gpt-4o` (agent + memos), `OPENROUTER_API_KEY` in env. Smoke-tested today — structured output + ReAct tool loop both work (~14s, exit 0). Fallbacks: `GEMINI_API_KEY`, vibeproxy `:8317`, Ollama `:11434` |
## 11. Three-way split ### 11.0 The split principle — one layer each, separate files The boundary is **pipeline stage**, not "hard stuff vs. easy stuff": | Person | Owns | File | | --- | --- | --- | | **A** | records → graph → insight | `main.jac` | | **B** | raw web → clean typed records | `extract.jac`, `registry.jac` | | **C** | insight → screen → judge | `app.jac` (the `cl def` section) |
Two benefits beyond even workload. Each person has exactly one responsibility, and **each works in their own file**, so three people don't spend the evening resolving merge conflicts in one `main.jac`.

One hard rule: **only A writes to the graph.** B returns pure typed values and never creates a node or edge. That keeps graph mutation in one head and one file.
### 11.1 First 15 minutes — stub the contracts, then never block again
Do this before anyone writes real logic. The whole point of the split is that nobody waits on anybody, and that only holds if the interfaces exist as stubs from minute one.

**B hands A four signatures, stubbed with hardcoded returns:**

```jac
obj ResolvedSubprocessor {
    has canonical_name: str;
    has purpose: str = "";
    has region: str = "";
    has confidence: float = 1.0;
}

def resolve_url(domain: str) -> str { return "https://stripe.com/legal/subprocessors"; }
async def fetch_page(url: str) -> str { return SAMPLE_PAGE_TEXT; }
def detect_all(domain: str) -> list[DetectedVendor] { return [ /* 5 fixed */ ]; }
# B's headline export: raw page text in, canonical records out.
# Extraction AND entity resolution both happen behind this one call.
def extract_and_resolve(page_text: str, known: list[str])
    -> list[ResolvedSubprocessor] { return [ /* 3 fixed */ ]; }
```

`extract_and_resolve` returns **strings, not nodes.** A does all node creation from the returned records.

**A hands C the walker names and exact JSON shapes, stubbed with sample reports:**

```
POST /walker/detect_vendors   -> {"found": 9, "vendors": [...]}
POST /walker/expand           -> {"nodes": [...], "edges": [...]}
POST /walker/chokepoints      -> [{"provider","vendors_affected","share","names"}]
POST /walker/blast_radius     -> {"provider","vendors_down","features_down"}
```

C builds the entire frontend against those fixed shapes. When A's real walkers land, the UI already works. If you skip this step, C sits idle for four hours and you lose the demo.

Agree the JSON field names in writing. Renaming a field at hour eight is how three-person teams lose.
### 11.2 Working simultaneously without collisions
Separate files reduce conflicts. They don't eliminate them, and the worst failure here isn't a merge conflict at all.

**Step zero: verify multi-file actually compiles.** Do this before anyone writes real logic.

Jac's entire marketing pitch is "a complete full-stack AI app in one file," and the flagship example puts nodes, walkers, and the `cl def` frontend together. Splitting across files should work via imports, but the frontend-in-a-separate-file path is less well-trodden than the documented happy path.

So get a trivial three-file version compiling first — `main.jac` importing a stub from `extract.jac`, with the `cl def` living in `app.jac`. Two minutes of work. If it fights you, fall back to **one file with strict section ownership** and commit more often. You want to discover that at minute 10, not hour six.

**Shared touchpoints that still collide:**

| File | Owner | Rule |
|---|---|---|
| `contracts.jac` (**NOT** `types.jac` — collides with Python's stdlib `types` module and silently imports the wrong one) | written once, then **frozen** | `ResolvedSubprocessor`, `SubprocessorRecord`, `DetectedVendor`, `RiskHeadline`. Field changes are a conversation, not a commit |
| import lines | whoever's file it is | trivial to resolve, but the classic conflict zone |
| `jac.toml` | **C only** | B needs `httpx`/`trafilatura`, C needs `[scale.*]`. B requests additions verbally |

**The risk that's worse than a merge conflict.**

B renames `canonical_name` to `name`, or makes `region` optional. A's code breaks **silently** — no textual conflict, so git says nothing. You find out during integration when the graph is inexplicably empty and three people start debugging the wrong layer.

This is why the contract freeze matters more than the file split does. After minute 15, a field rename is something you say out loud.

**Git hygiene — boring, works:**

- Commit every ~20 minutes. Small commits are cheap to untangle; one giant commit at hour seven is not.
  
- `git pull --rebase` before every push.
  
- **Nobody touches a file they don't own.** No drive-by fixes, no "while I was in there."
  
- **No formatters.** One person running a formatter across the repo at hour seven generates a conflict in every file simultaneously, and you will spend your rehearsal time on it.
  

* * *
### Person A — Graph & Traversal (`main.jac`)
**Owns the object-spatial half of "best use of Jac."**

You own every line that touches the graph. Nobody else creates a node or an edge.

| Priority | Task |
| --- | --- |
| 1   | Graph model — nodes, edges, **typed edge endpoints** (`edge Uses: Org --> Vendor`) |
| 1   | `Expand` walker — depth cap, `seen` guard for cycles, BFS orchestration, calls into B's `extract_and_resolve` |
| 1   | `find_or_create_provider` — node creation from B's returned canonical strings |
| 1   | `Chokepoints` walker — `[prov <-:Subprocesses:<-]`, the core algorithm |
| 2   | `BlastRadius` walker — backward traversal, affected vendors → affected features |
| 2   | `DetectVendors` and `AddVendors` walkers (graph writes from B's detection output) |
| 2   | `walker:priv` auth wiring + per-user root isolation |
| 3   | `DiffMonitor` on `@schedule` + `Snapshot` nodes (Action 2) |
| 3   | Second-user isolation demo data |

**In Q&A you field the object-spatial questions.** Be ready without notes: why BFS is the language default (`visit [-->]` appends to the queue), why the `seen` guard is required rather than defensive, why typed endpoints let traversals infer concrete node types, why persistence-by-reachability means the monitor needs no database.

* * *
### Person B — Data & Extraction Pipeline (`extract.jac`, `registry.jac`)
**Owns the meaning-typed half of "best use of Jac," and the judge-types-their-own-domain moment.**

You own everything from "a domain name" to "clean canonical records." Both `by llm()` calls are yours — they're the second Jac pillar, and you speak to them in Q&A.

| Priority | Task |
| --- | --- |
| 1   | Registry: ~150 vendors → subprocessor URLs. Generate the bulk with Claude, spot-check by hand |
| 1   | `resolve_url` — exact registry -> fuzzy match -> ReAct agent (§4.3) |
| 1   | `fetch_page` — real UA, 5s timeout, concurrency cap ~10, cache by domain |
| 1   | **Seed the known-providers anchor list** — the obvious 20 (AWS, GCP, Azure, Cloudflare, Fastly, Twilio, SendGrid, Snowflake, Datadog, MongoDB Atlas…) |
| 1   | `extract_subprocessors` — `by llm()` with `sem`, returns `list[SubprocessorRecord]` |
| 1   | `canonicalize` — `by llm()` entity resolution, the load-bearing call |
| 1   | `extract_and_resolve` — the single export A calls. Returns records, **never touches the graph** |
| 2   | Detection module: DNS (MX, SPF/DMARC TXT, CNAME), HTTP headers, `<script>` tags |
| 2   | **Pre-warm the demo cache** — target is `jachammer.ai` (meta: analyze the platform we deploy on). Detection resolves it to AWS (us-east-2 IPs + Route 53) live; pre-warm the stack we manually add (its LLM providers, GitHub, Stripe, CDN, monitoring) so the scripted path is instant + offline |
| 2   | Extraction quality pass — run it against 15 real vendor pages and eyeball the output |
| 2   | **Agentic discovery fallback (§4.3)** — fuzzy match over registry + resolved names, then a `by llm(tools=[...])` ReAct hunter (sitemap → trust subdomain → path guess → web search). The Agentic-AI hero; each tool is a narrow `def`+`sem`. Keep it off the rehearsed path |
| 2   | **Defense + compliance data (core, same screen)** — seed `Provider` compliance fields (`soc2`, `hipaa`, `supply_chain_risk`) and `downtime_hours_ytd` for the top ~20 providers; add a DoD prime->sub->tier-3 adapter. Renders on the same canvas via the same walkers — not a separate tab |

**The anchor list comes before the LLM calls.** Canonicalization needs something to resolve _toward_. Without anchors, "AWS" and "Amazon Web Services, Inc." stay separate single-edge nodes and **the chokepoint silently never appears** — the failure mode that looks like the whole idea doesn't work. You own that risk.

**You're now on the critical path**, which you weren't before. Extraction quality determines whether a chokepoint exists at all, so the +2hr end-to-end checkpoint is primarily a test of your layer. Get one vendor extracting correctly before you touch detection.

**Pre-warming the cache is not optional.** The rehearsed path must never touch the network. Live crawling exists only for the judge's own input.

**In Q&A you field meaning-typed and data questions:** why entity resolution is a type signature rather than a prompt, why a hand-written parser for 150 page layouts is a week of work, where the data comes from (the vendors' own legal disclosures — better provenance than inference), what coverage looks like, and how this differs from BuiltWith.

* * *
### Person C — Interface, Deploy & Pitch (`app.jac`)
**Owns: best use of JacHammer, the scale-invariance story, and the pitch. Two prizes route through you.**

| Priority | Task |
| --- | --- |
| 1   | **Deploy a two-node stub to JacHammer by mid-afternoon.** Before any real logic exists |
| 1   | `cl def:pub app` skeleton wired to A's stubbed JSON shapes |
| 2   | Graph canvas per **§6.1** — tier-pinned x, force-solved y, sqrt sizing, 2+ dependent pruning |
| 2   | Outage simulation with **backward propagation animation** (§6.2). The money shot |
| 2   | WebSocket streaming, batched at 200ms so it doesn't jank on the projector |
| 2   | **The 3-minute script, written down.** Then rehearse it twice |
| 2   | `draft_status_update` — `by llm()`, renders into the outage panel |
| 3   | `risk_memo` — `by llm()`, plus the export UI (Action 1) |
| 3   | Diff feed UI (Action 2) |
| 3   | Coverage strip (`ok / unreadable / notfound`) |
| 3   | `jac.toml` `[scale.*]` config + verify `jac start --scale` actually comes up |

The two narrative `by llm()` calls are yours because you own the surfaces they render into — no cross-file handoff for a string.

Deploy first, on a stub. Deploy problems discovered at hour nine have killed better projects than yours. Get the JacHammer URL working while it costs twenty minutes instead of two hours.

`jac clean --all` before every rehearsal or you'll hit `NodeAnchor` errors on stage.

**In Q&A you field scale and product questions:** why the same file runs `jac run` → `jac start` → `jac start --scale` with an empty diff, what scale-to-zero means on JacHammer, who pays, what the wedge is, why the monitor drives retention, how it differs from Vanta.

* * *
### Integration checkpoints
Set actual alarms. Three people converging on one `main.jac` will conflict, and you want to find that out early and often.

| When | Checkpoint |
| --- | --- |
| +10 min | Three-file skeleton compiles (§11.2 step zero). If not, collapse to one file now |
| +15 min | Contracts stubbed and `contracts.jac` frozen. A, B, C all have something running against fake data |
| +2 hr | **First real end-to-end:** one hardcoded vendor → real crawl → real extraction → chokepoint in the UI. One vendor is enough. Primarily a test of B's layer — if extraction and canonicalization don't converge, nothing downstream matters |
| mid-afternoon | JacHammer deploy live on the stub. Non-negotiable |
| −3 hr | Feature freeze on Tier 1 and 2. Everything after this is Tier 3 or polish |
| −2 hr | Full rehearsal #1 on the deployed URL, not localhost |
| −1 hr | Rehearsal #2. Cut anything not in the script |

The +2hr end-to-end matters more than it looks. If extraction and canonicalization don't converge into a visible chokepoint on a single vendor, you need to know at hour two, not hour nine.
### Who does what on stage
Snehil pitches — you've won this way before and you know the beats. C drives the laptop, since they built the UI and know where every click lives.

Jac questions split cleanly now, which is better than one person carrying all of it: **A takes object-spatial** (traversal, walkers, persistence), **B takes meaning-typed + agentic** (`by llm()`, entity resolution, the ReAct discovery loop, why no parser), **C takes scale-invariance** (one file, three deploy modes, JacHammer). If a Jaseci judge goes deep, whoever owns that pillar answers. Decide this now, not while walking up.
### Cut order under time pressure
Delete from the bottom of every Tier-3 list simultaneously. In order of what you sacrifice first: second-user login, coverage strip, `DiffMonitor`, `risk_memo`. Defense/compliance is now core (same engine, cheap) — keep it. Do **not** cut the rehearsals to buy feature time — an unrehearsed demo of a better product loses to a rehearsed demo of a worse one.
## 12. Questions judges will ask
**"Isn't this BuiltWith or Wapparlyzer?"** Those detect your first layer — what's on your own site. They stop there. The entire point is the second layer, which comes from legal disclosures rather than page inspection, and the concentration math across it.

**"Don't Vanta and Drata do this?"** They track your vendor list as inventory, for compliance checkboxes. They don't expand it transitively and they don't compute concentration. Their output is "you have a DPA on file." Ours is "three of these die together."

**"What about SecurityScorecard / Bitsight / UpGuard?"** Per-vendor risk _ratings_ — is this vendor well-run. Orthogonal to shared-dependency structure. A stack of five A-rated vendors on one provider still has one point of failure.

**"How do you know the data's right?"** We don't assert more than the source does. Every edge carries `source_url` and `last_seen`, and the UI reports read/unread coverage. It's the vendor's own legal disclosure, which is a stronger provenance story than inference.

**"Who pays?"** The startup that just got a security questionnaire with a concentration-risk question in it, and the fintech whose bank partner requires third-party risk documentation. Wedge is the questionnaire; retention is the monitor.

**"What's the moat?"** The registry and the resolved entity graph, both of which compound. Every new customer's vendors improve canonicalization for everyone.
## Sources
- [Jac docs — What is Jac](https://docs.jaseci.org/quick-guide/)
  
- [Object-Spatial Programming reference](https://docs.jaseci.org/reference/language/osp/)
  
- [Scale reference —](https://docs.jaseci.org/reference/plugins/jac-scale/) `jac start --scale`[, K8s, auth, persistence](https://docs.jaseci.org/reference/plugins/jac-scale/)
  
- [Agentic AI / byLLM tools tutorial](https://docs.jaseci.org/tutorials/ai/agentic/)
  
- [jaseci-labs/jac on GitHub](https://github.com/jaseci-labs/jac)
