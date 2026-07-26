# Blast Radius — state of play + the decisions still open
Written for Tim (A). ~1:10 PM. Deadline 7:15 PM. Checkpoint 5:50 PM. Everything below is grounded in what's actually in the repo right now, not the plan.

* * *
## 1. Where we actually are
| Lane | Landed | Missing |
|---|---|---|
| **A (you)** | `main.jac` — real object-spatial graph. Typed nodes/edges, BFS `expand` with cycle guard, `[prov <-:Subprocesses:<-]` chokepoints, blast radius, compliance fallout, one-look, `@schedule` diff monitor. Plus (just now) slug ids, feature catalog, crawl provenance, TTL cache. `jac check` clean, all 8 endpoints verified live. | Shared-graph cache (§4), provider↔vendor identity (§5), auth flip to `:priv`. |
| **B** | `registry.jac` — **150 real vendors → exact subprocessor URL**, all `official_website`, each with `verified_on`. This is the single most valuable asset in the repo. | `extract.jac` does not exist. No crawl, no `by llm` extraction, no canonicalization, no ReAct agent. **And no provider compliance/downtime data** (PLAN B2) — see §7, this is a silent demo-killer. |
| **C** | 12 design mockups in `drafts/`. | `app.jac` does not exist. No `[scale.*]`, no deploy. Audit confirms **zero** `fetch`/WebSocket/EventSource across all 12 drafts — nothing is wired. |

**My read on risk order, which differs from the PLAN:**

1. **C hasn't started wiring, and there's no deploy.** PLAN calls mid-afternoon JacHammer deploy "non-negotiable". It's 1 PM. This is now the #1 risk, ahead of extraction.
  
2. **B's** `extract.jac` **is the entire live path** and doesn't exist. My `extract.jac` stub is currently standing in for it.
  
3. Provider risk data (§7).
  

The good news: the stub boundary is holding. A's slice runs end-to-end today with zero dependency on B or C.

* * *
## 2. What I changed after auditing your drafts (already pushed)
I had the audit read all 12 mockups and diff them against what the API serves. It found a **contract-breaking bug in my code**:

- **Node ids.** I was emitting `openai.com` and `Microsoft Azure`. Every mock — and the original stub — keys by short slug (`openai`, `azure`, `gcp`) and hardcodes `blast('aws')`. **All 12 mocks would have broken.** Fixed: ids are slugs now, derived from the _display name_ (so `datadoghq.com` → `datadog`), with curated overrides for `azure`/`gcp`. `blast_radius` accepts either form.
  
- **Feature catalog — 12/12 drafts need it.** Every mock has a hardcoded `FEATURES` map to render capability boards _before_ a blast. `features_down` only covers the failure list. Vendor nodes now carry `features: [str]`.
  
- **Provenance + coverage — 4 drafts.** Added `crawl_status` / `source_url` per vendor and a `crawl_progress` endpoint.
  
- Edges now carry `purpose` + `handles_pii` (`handles_pii` was dead data before).
  
- Org label: `org_name` param, so it's "JacHammer" not "Jachammer".
  

Gaps I deliberately did **not** fill: 12-month downtime sparklines and per-feature `$/h` cost (draft 11 only), and structured `incident_id`/`region` (draft 05 only). Say the word if you're picking those drafts.

* * *
## 3. Your framing is right — and here's the honest split
> _"we just built the graph layer over the data itself yes? but the fetching data (live) process is a hard path"_

Yes. Precisely. The graph layer is **done and it's the easy half**. It answers every question by traversal, and traversal is cheap and deterministic. Everything hard is on either side of it:

```
     HARD                     DONE                    HARD
  ┌──────────┐          ┌──────────────┐        ┌──────────────┐
  │ domain → │ ──────►  │  the graph   │ ─────► │  semantic    │
  │ real     │          │  (A's slice) │        │  output      │
  │ sub list │          └──────────────┘        └──────────────┘
  └──────────┘
   registry hit = free                          currently deterministic
   long tail    = agent                         strings in my stub
```

One thing worth internalising: **the cache you're describing is a graph concern, not a fetch concern.** "Anyone can do OpenAI but spend no tokens because we already did it once" is not an HTTP cache — it's a persistent shared subgraph with a TTL. That's §4, and it's mine to build.

* * *
## 4. DECISION 1 — the shared graph. This is the big one.
**Context.** I built TTL caching (`Vendor.last_crawled`, `expand{ttl_days=7}`). But every node currently hangs off _the caller's_ root. Under `walker:pub` everyone shares the guest root, so it accidentally works right now. **The moment C wires auth (**`walker:priv`**, per-user root isolation — PLAN A8), every user re-crawls everything from scratch.** The cache evaporates exactly when it starts to matter.

**The fix.** Split the graph by privacy boundary:

- `root.shared` (deployment-wide commons) holds `Vendor` + `Provider` + `Subprocesses`. This data comes from _public legal filings_ — there is nothing tenant-specific in it.
  
- **The user's own** `root` holds their `Org`, with `Uses` edges pointing _into_ the shared vendor nodes. Who you are and which vendors you use stays private.
  

**What this buys:**

- {==OpenAI's subprocessor list is crawled **once, ever, for the whole deployment**. User #2 pays zero tokens and zero latency.==}{>>but what if it changes<<}{id="c6" by="user" at="2026-07-26T20:19:09.012Z"}
  
- It implements the moat claim we're already planning to say out loud (spec §12: _"every new customer's vendors improve canonicalization for everyone"_). Right now that claim is not true in the code.
  
- It makes the second-user isolation demo actually mean something.
  
- It gives you §5's recursion nearly for free.
  

**Cost / risk:**

- Shared nodes need `grant(node, level=…)` or other users can't see them (`ConnectPerm` for vendors so users can attach `Uses`, `ReadPerm` for providers). Needs a real 2-user test — `allroots()`/grants don't behave in single-session `jac run`.
  
- ~6 query sites change from `[root -->[?:Provider]]` to `[root.shared -->…]`.
  
- Estimate 45–60 min including the 2-user test.
  

**My recommendation: do it, and do it _now_, while walkers are still** `:pub`**.** Outside multi-user, `jid(root.shared) == jid(root)`, so building it today changes nothing observable and can't break the demo — but it turns C's eventual auth flip from a re-architecture at hour 9 into a one-line change. Doing this _after_ auth lands is the expensive order.

**Counter-argument you should weigh:** if C never gets to auth, this is invisible work. It's cheap insurance on the single best story we have, but it is insurance.

* * *
## 5. DECISION 2 — recursion / "unknown company inside another's graph"
Your instinct here is sharp. There are two separate things hiding in it.

{==**(a) Depth.** Spec caps at 2 on purpose: depth 3 is ~thousands of nodes, every one an LLM call, and it carries no information — everything terminates at AWS/GCP/Azure/Cloudflare, which the judge already knows. **Keep the cap.**==}{>>can we 'know' if we should uncap it?<<}{id="c7" by="user" at="2026-07-26T20:19:46.344Z"}

But note what §4 does to this: with a shared graph, depth becomes _emergent_. If any user ever expanded Twilio as their own vendor, then a later user whose Notion subprocesses Twilio gets Twilio's subprocessors **for free, at zero crawl cost**. That's depth 3 without paying for depth 3, and it's a genuinely strong pitch beat.

**(b) Identity.** Right now `Provider("Twilio")` and `Vendor("twilio.com")` are two unrelated nodes with no link. Spec explicitly says a company can be both. Without the link, recursion can't happen at all.

- _Rejected:_ merge into one `Company` node with a role flag. The spec is right that keeping them distinct is what keeps the concentration math honest — merging double-counts.
  
- _Recommended:_ add `Provider.domain` + a lazy `SameAs: Provider --> Vendor` edge, created whenever both exist. Then an **on-demand** `expand_provider` walker: the user clicks a provider and gets one more layer. User-driven, bounded, demoable, and it never blows the token budget on its own.
  

**Blocker:** needs a name→domain lookup from B (`ResolvedSubprocessor` is frozen and has no domain). B's registry is keyed by domain and carries `name`, so a reverse index is trivial for them — ask for `registry_domain_for_name(name) -> str`.

**My recommendation: defer.** Ranks below §4 and well below C's deploy. §4 gives you the compounding story without it. Pick this up only if we're ahead at −3 hr.

* * *
## 6. DECISION 3 — arbitrary company: discovery + BYO
**The resolution ladder** (cheapest first — B owns all of it):

| Layer | Method | Cost |
|---|---|---|
| L0 | Registry exact hit (150 vendors) | free, instant, no LLM |
| L1 | Domain normalise + name fuzzy match → registry | free |
| L2 | Well-known paths: `/legal/subprocessors`, `/subprocessors`, `/trust`, `/dpa`, `trust.<domain>` | 1 fetch |
| L3 | `sitemap.xml` scan for `subprocessor\|sub-processor\|dpa` | 1–2 fetches |
| L4 | ReAct agent + browser (B is building; bounded 4 searches / 8 pages / 30–45 s) | expensive, **off the rehearsed path** |
| L5 | BYO — user supplies the list | free |

Known dead end, worth saying out loud on stage: **Vanta/SafeBase/Drata trust centers are client-rendered** and return an empty shell to a plain GET. B's plan now routes those through a browser render. Anything still unreadable gets marked `unreadable` and surfaces in the coverage strip — _a tool that reports its own coverage gaps reads as competent, not incomplete._

**On your BYO idea — yes, and rank it like this:**

1. **Paste a list** — already works (`add_vendors`). Zero effort.
  
2. **GitHub repo URL** — parse `package.json` / `requirements.txt` / `go.mod` / `docker-compose` / `.github/workflows` / Terraform → infer vendors. **This is the one I'd actually build.** No LLM needed for the common cases (a package-name → vendor-domain map), it's honest, and _"point us at your repo and we'll read your dependency manifest"_ is a great line for a room full of people who all have a repo open.
  
3. **File upload** (`.txt`/`.csv`) — Jac supports `UploadFile`. Cheap.
  
4. **SSO / SaaS-management export** (Okta, Ramp, Vanta CSV) — the real enterprise answer. _Mention it in Q&A, don't build it._
  

**Key architectural point:** every one of these is a **B-side adapter** that produces the same `list[DetectedVendor]`. My graph contract doesn't change at all. So BYO is purely additive and can land late without risk.

* * *
## 7. ⚠️ The silent demo-killer nobody owns
`registry.jac` has **zero** provider compliance/downtime data — I checked, `soc2`/`hipaa`/`downtime`/`watchlist` appear nowhere in it. `RegistryEntry` is `{name, domain, subprocessor_url, source_type, verified_on, notes}`.

Right now that data exists **only in my** `extract.jac` **stub, for exactly 5 providers** (AWS, Azure, GCP, Cloudflare, Fastly).

**What happens if a judge types a domain whose vendors resolve to a 6th provider:** it comes back `soc2=true, downtime=0.0` → `exposure = share × 0.0 = 0.0` → it ranks last, the chokepoint table degenerates, and the one-look headline reads "0.0h of downtime". The demo doesn't crash — it just quietly stops being impressive, which is worse.

**This is PLAN item B2 and it is not built.** It needs ~20 rows of curated data. Somebody has to own it today. It's the cheapest high-impact task left in the entire project.

Related, same shape: `explain_fallout`, `compose_one_look`, and `draft_status_update` are deterministic strings in my stub. Fine for a safe rehearsed path — but if nobody swaps them to `by llm`, we quietly lose the "meaning-typed narrative" claim. And **nobody owns** `risk_memo` (spec §5.4 — "the artifact you owe someone", Action 1). It's under C7 and C hasn't started.

* * *
## 8. DECISION 4 — progress UI transport
| Option | Pros | Cons |
| --- | --- | --- |
| **Poll** `crawl_progress` (built) | Works today on the bundled server. No jac-scale. Can't fail on stage. | Not "real" streaming (nobody will know at 300 ms). |
| WebSocket (PLAN C5) | The spec's 200 ms batched stream. | Needs jac-scale + the `pip install requests` packaging hole. Risk on stage. |
| SSE (`-> Generator`) | Middle ground. | Still more infra than polling. |

**Subtlety that matters:** `expand` currently crawls all 8 vendors and _then_ returns. A poll during that call won't see partial writes — so polling alone gives you a bar that jumps 0 → 100.

**Recommended fix, and it's small:** add `expand_one {vendor_id}`. The frontend reads `crawl_progress`, then loops the pending vendors calling `expand_one` for each, updating the UI per response. Zero new infrastructure, a genuine per-vendor streaming feel, natural per-vendor timeout isolation, and it gives spec §10's _"visible per-vendor spinner and graceful timeout"_ exactly. `expand` stays as the batch/rehearsed path.

I can add `expand_one` in ~15 min. **Recommend yes.**

* * *
## 9. What I propose to do next, in order
1. `expand_one` (§8) — 15 min. Unblocks C's progress UI immediately.
  
2. **Shared graph on** `root.shared` (§4) — 45–60 min. The moat story, and it must precede auth.
  
3. Hold `expand_provider`/recursion (§5) unless we're ahead at −3 hr.
  

**Not mine but I'd escalate now, in this order:**

- C: deploy the stub to JacHammer _today_, before any UI polish. It's already deployable.
  
- B: 20 rows of provider risk data (§7). Cheapest high-impact task left.
  
- Someone: own `risk_memo`.
  

* * *
## 10. Questions for you
{==Mark these up and I'll execute.==}

1. **§4 shared graph — build it now, or skip it?** {>>My rec: build now, while `:pub` makes it a no-op to test.<<}{id="c1" by="user" at="2026-07-26T20:10:12.282Z"} {#c1}
  
2. **§8** `expand_one` **— add it?** {>>My rec: yes, 15 min, unblocks C.<<}{id="c2" by="user" at="2026-07-26T20:10:12.282Z"} {#c2}
  
3. **§6 GitHub-repo ingest — worth pushing B on, or is it scope creep at 1 PM?** {>>My rec: worth it *only* if B's core extract path is already working by ~3 PM.<<}{id="c3" by="user" at="2026-07-26T20:10:12.282Z"} {#c3}
  
4. **§7 provider risk data — who owns it?** {>>Needs an owner today or the demo quietly degrades on any judge-typed domain.<<}{id="c4" by="user" at="2026-07-26T20:10:12.282Z"} {#c4}
  
5. **Which draft is C actually building?** {>>Changes whether I add sparklines + per-feature cost (draft 11) or incident metadata (draft 05).<<}{id="c5" by="user" at="2026-07-26T20:10:12.282Z"} {#c5}
  
6. **§5 recursion — confirm we're deferring?** {#c6}
  

* * *

comments:

- id: c1 by: assistant at: 2026-07-26T13:10:00-07:00
  
- id: c2 by: assistant at: 2026-07-26T13:10:00-07:00
  
- id: c3 by: assistant at: 2026-07-26T13:10:00-07:00
  
- id: c4 by: assistant at: 2026-07-26T13:10:00-07:00
  
- id: c5 by: assistant at: 2026-07-26T13:10:00-07:00
  
- id: c6 by: assistant at: 2026-07-26T13:10:00-07:00
  

* * *
