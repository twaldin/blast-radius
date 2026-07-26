# Blast Radius — final work split
**Written 16:00 PT. Demo 19:15 PT. 3h15m left.Tim → frontend · Snehil → deploy · David → search + discovery agent**

This supersedes `PLAN.md`, `SPEC-V2.md`, `blast-radius-build-spec.md`, and `REVIEW.md` wherever they disagree. Those docs describe a product we did not build. Everything below was verified by running it in the last 40 minutes.

* * *
## 1. Bottom line
The backend is **done and genuinely good**. The frontend **serves a blank page**. The agent **had no model bound and could not run at all**. Two of those three facts were not known an hour ago, and neither was in any existing doc.

Read §3 before you write code. Two of the four root causes are things people believe are working right now.

* * *
## 2. Verified state
Run at 15:55 PT against `main` @ `66d742c`.

| Area | State | Evidence |
| --- | --- | --- |
| Graph backend | **GREEN** | `jac test main.test.jac` → **9/9 pass** |
| Real data | **GREEN** | 293 companies, 555 edges, 19/20 filings readable |
| `atlas`, `graph`, `search`, `dependents`, `chokepoints`, `blast_radius`, `industry_map` | **GREEN** | all return real payloads, verified in test output |
| byLLM / all LLM calls | **FIXED 15:50** | was 100% dead; now verified live |
| ReAct discovery agent | **RED** | exists, 0 callers, unreachable from any user path |
| Frontend | **RED** | renders a blank page — no route resolves |
| Cold-start seeding | **RED** | fresh deploy comes up empty |
| Deploy | **RED** | never happened, no URL |

Real numbers you can say on stage — all from the passing test run, none invented:

- Okta 89 disclosed subprocessors · Figma 54 · Intercom 43 · Stripe 40 · HubSpot 32 · Notion 32 · Linear 32 · Cloudflare 30 · GitHub 30
  
- Top chokepoint: **Microsoft Azure — 6 of 19 companies (30%)**, then Salesforce 15%, Cloudflare 15%
  
- `openrouter.ai` = the one we honestly could not read
  

* * *
## 3. What actually went wrong — four root causes
### 3.1 The frontend has never rendered. Not "shows wrong data" — blank.
Jac file-based routing requires every page file to export `def:pub page()` and layouts `def:pub layout()` (`jac guide jac-cl-routing`). Ours export:

| File | Exports | Needs to be |
|---|---|---|
| `pages/index.jac:23` | `Landing()` | `page()` |
| `pages/atlas.jac:16` | `Atlas()` | `page()` |
| `pages/brief.jac:63` | `Brief()` | `page()` |
| `pages/layout.jac:34` | `Shell()` | `layout()` |

Zero routes register. `curl localhost:8010/` returns a shell that mounts `{"module":"main","function":"app"}` → `main.jac:1193`, which is `<>{children}</>` with no router and no children. **An empty div.**

`REVIEW.md` §2 says the app "renders an 8-vendor fabricated fixture". That was inferred from reading `store.jac`, not from loading the page. It renders nothing at all. The fix is four renames.

On top of that, **6 of 9 frontend files fail** `jac check` (`pages/index.jac`, `pages/atlas.jac`, `pages/brief.jac`, `risk/store.jac`, `risk/DependencyGraph.jac`, `risk/graph_core.cl.jac`).
### 3.2 Every LLM call in the repo was dead. — FIXED, committed as `66d742c`
byLLM binds `by llm(...)` to a module-global named `llm`. **No** `Model(...)` **was declared anywhere in the repo.** byLLM silently fell back to OpenAI; there is no `OPENAI_API_KEY` on this machine. Every call — `extract_subprocessors`, `canonicalize_with_llm`, `find_dpa_sources` — failed at runtime with `litellm.InternalServerError: Missing credentials`.

So "backend with LLMs" was not partially done. It was 0%.

Fixed in `extract.jac`: `glob llm = Model(model_name=os.getenv("BLAST_RADIUS_MODEL", "gemini/gemini-2.5-flash"))`. `GEMINI_API_KEY` is already in the environment. Verified live through the real module:

```
canonicalize_with_llm("Amazon Web Services EMEA SARL", [...])  ->  "AWS"
```

A tool-calling ReAct probe also completes its loop end to end. **B: your whole lane went from impossible to working. Re-test anything you concluded was broken.**
### 3.3 The ReAct agent is unreachable, so the Atlas page's core promise has no implementation
`find_dpa_sources` (`extract.jac:397-405`) is a correct byLLM ReAct declaration — 3 tools, `max_react_iterations=6`. Its call chain:

```
find_dpa_sources  <-  discover_with_browser  <-  discover_and_resolve  <-  NOTHING
```

`discover_and_resolve` has **zero callers**. `main.jac` does not import it.

What the `search` walker actually does today: 7 tiers of deterministic string matching (exact → alias → despaced → slug → Levenshtein≤2 → substring → 150-entry registry). No LLM, no browser, no discovery. For a company not already in the graph it returns `{"resolved": null, "results": []}`. `map_company` is not an escape hatch either — it falls through to `resolve_url`, which is registry-only, and returns `"notfound"`.

**"Search for an arbitrary company" — the entire point of the Atlas page — has no code path.** This is also the Agentic-AI track centrepiece.
### 3.4 A fresh deploy comes up empty
`seed_atlas` is idempotent, tested, and **called by nothing**. Worse, it resolves `Path("seed/atlas")` relative to process CWD; in a container that silently reports `seeded: 0` and succeeds. Plus `jac.toml:42` sets `max_replicas = 4` with no shared database → four pods, four different graphs.
### Also worth knowing
- The 9/9 test failure everyone saw was **a stale** `jac start` **on :8010 holding the SQLite WAL**, not a code fault. Killed it; suite is green. If tests say "readonly database", kill your servers.
  
- `/Users/twaldin/blast-radius-swiss` is **not** anyone's work — it's a scratch checkout from an agent running loose on Tim's machine. Do not merge it. It is 5 commits behind and pulls in a `react-force-graph-2d` npm dependency we already removed. It is useful as a **reference only**: it happens to contain a working search-input pattern (`pages/index.jac:129-142`) and a store `search` action (`store.jac:273`). Copy the pattern, not the files.
  

* * *
## 4. Frozen API contract — read this, then never block on each other
These payloads are **verified from the passing test run**. They will not change. Tim builds the pages against them without waiting for anyone; David owns both sides of the discovery path, so there is no cross-lane contract left to honor.

```jsonc
// POST /walker/atlas  {}                      -> the landing page's company list
{"total": 19, "companies": [{
  "id": "figma", "domain": "figma.com", "name": "Figma", "featured": true,
  "vendor_count": 51, "provider_count": 81,
  "top_chokepoint": "Salesforce", "top_chokepoint_id": "salesforce",
  "top_share": 0.06, "vendors_affected": 3,
  "source_url": "https://www.figma.com/sub-processors/"}]}

// POST /walker/graph  {"domain": "lindy.ai"}  -> one company's dependency graph
{"nodes": [{"id","label","tier","inbound_degree","soc2","supply_chain_risk",
            "downtime_hours_ytd","domain","category","crawl_status",
            "source_url","risk_source_url"}],
 "edges": [{"source","target","kind","purpose","region","handles_pii"}]}
// tier is "org" | "vendor" | "provider", computed as BFS distance from the viewed company

// POST /walker/search {"q": "aws", "allow_discovery": false}
{"query": "aws",
 "resolved": {"id","domain","name","state","filing_count","dependent_count",
              "crawl_status","source_url","match"},
 "results": [ ...same shape... ],
 "discovered": false}                          // <- NEW, added by David in §5

// POST /walker/chokepoints {}
[{"provider","provider_id","vendors_affected","share","downtime_hours_ytd",
  "exposure","downtime_cited","names","vendor_ids"}]

// POST /walker/blast_radius {"failed_provider": "azure"}
{"provider","provider_id","vendors_down","vendor_ids","features_down","status_post"}

// POST /walker/dependents {"domain": "..."}   -> inbound: who depends on this
{"nodes","edges","root","root_domain","root_label","direction":"inbound","dependent_count"}

// POST /walker/industry_map {"min_degree": 2}  -> the whole-map page (stretch)
```

Envelope for all of them: `{"data": {"reports": [ <payload> ]}}`.

**The one piece that does not exist yet — David owns both sides of it, so it cannot desync:**

```jac
# extract.jac:570-593 -- already exists, needs hardening
def discover_and_resolve(domain: str, keyword: str) -> BrowserDiscoveryResult;
# never raises; status in {"ok","notfound","unreadable"}; returns in <=45s
```

The `search` walker calls it. Both sides live in David's lane now.

* * *
## 5. Lanes
Each lane owns disjoint files. **Do not edit outside your lane** — cross-lane edits are what produced §3.1.

Assignment changed at 16:10. Tim moves to frontend because it is now the only thing between us and a demo and it is the riskiest lane. Snehil takes deploy: bounded, binary, needs no context in a 1185-line file. David takes the entire search→discovery vertical so one person owns both sides of it and there is nothing to hand off.
### SNEHIL · deploy + config — owns `jac.toml`, hosting
**Do this first. Nothing else in this document matters without a URL.** You do not need to read `main.jac`.

| #   | Task | Done when |
| --- | --- | --- |
| S1  | Set `max_replicas = 1` (`jac.toml:42`). Four replicas with no shared database means four different graphs depending on which pod a judge hits | one replica |
| S2  | **Deploy on what exists right now.** Do not wait for anyone's feature | a URL answers `POST /walker/atlas` with 19 companies |
| S3  | Check `jac-version = "==0.34.7"` (`jac.toml:7`) against the installed 0.16.7 toolchain. If the builder honors that pin, install fails | build log clean |
| S4  | Cold-start seeding. `seed_atlas` resolves `Path("seed/atlas")` relative to **process CWD**, so in a container it reports `seeded: 0` and succeeds silently. Make it module-relative and auto-run when the graph is empty | fresh container serves 293 companies, no manual curl |
| S5  | Once a URL exists, own redeploys. Everyone else pushes `main`; you keep the URL current | —   |

S4 is the only item that touches `main.jac`. It is ~10 lines, localized to the `seed_atlas` walker — tell David before you push, he is in the same file.
### DAVID · search + discovery — owns `extract.jac`, `browser_discovery.jac`, `registry.jac`, and the `search` walker in `main.jac`
**Your lane was blocked by a dead LLM binding until 15:50 (§3.2). It works now. Start by re-running whatever you gave up on.** You own both sides of the discovery boundary, so there is no contract to negotiate with anyone.

| # | Task | Done when |
|---|---|---|
| D1 | Verify the ReAct agent end to end: call `find_dpa_sources("Vercel", "vercel.com")` and watch it plan | returns real candidate URLs for a company outside the 150-entry registry |
| D2 | Harden `discover_and_resolve` (`extract.jac:570-593`): never raises, always returns a status, hard 45s ceiling | fuzzed with 5 junk inputs, never throws |
| D3 | **Wire it up.** `search` gains `allow_discovery: bool = False` and a `"discovered"` field. On graph+registry miss with the flag set, call `discover_and_resolve`, persist via `_upsert_company`, return the same envelope (§4) | `search{q:"vercel", allow_discovery:true}` resolves a company that was not in the graph before |
| D4 | Decide the no-browser story. `browser_discovery.jac` shells out to a `browser-harness` binary + Chrome CDP that **will not exist in the deployed container** | either it degrades cleanly to `unreadable`, or discovery runs LLM-only via `search_web_tool` |
| D5 | Keep `main.test.jac` at 9/9 — you are the only one changing backend logic | green before every push |

D3 is the Agentic-AI track centrepiece and the Atlas page's entire promise. D4 is what bites on stage: if the deployed box has no browser, say so in the UI rather than hanging 45 seconds.
### TIM · frontend — owns `pages/`, `risk/`
Biggest lane and the critical path. **Do not merge the swiss checkout** (§3.4 note) — it is 5 commits behind and drags in an npm dependency we already removed. Read it for the search-input pattern only.

| # | Task | Done when |
|---|---|---|
| T1 | **Rename the four exports** — `Landing`→`page`, `Atlas`→`page`, `Brief`→`page`, `Shell`→`layout` | `/` renders literally anything. ~2 minutes. Do it first |
| T2 | Fix the 6 `jac check` failures (§3.1) | `jac check pages/*.jac risk/*.jac` clean |
| T3 | **Landing = real data.** Delete the 8 hardcoded literals at `pages/index.jac:8-17`; drive the picker from `atlas {}` (19 real companies, real counts, real chokepoints). Add the project/problem copy | landing lists Okta/Figma/Stripe with real subprocessor counts |
| T4 | **Kill the fixture path.** `risk/store.jac:123-134` calls `expand {}` with no domain and falls back to `detect_vendors` → the fabricated 8-vendor stack. Replace with `atlas {}` on load, `graph {domain}` on select | `detect_vendors`/`DEMO_VENDORS` have no frontend callers; the apology line at `pages/atlas.jac:160` is gone |
| T5 | **Atlas search box** — the page's reason to exist. Input → `search {q}` → hit list → select → `graph {domain}`. On an empty result, a "map it now" button that re-calls with `allow_discovery: true`, plus a spinner | typing "okta" draws Okta's 89-dependency graph |
| T6 | Keep the SVG radial renderer in `risk/DependencyGraph.jac` — it works and has no npm dependency | — |

T5 depends on David's D3 only for the _discovery_ branch. Build the search box against plain `search {q}` immediately — that works today and covers every seeded company.

* * *
## 6. Timeline
| Time | Gate |
| --- | --- |
| **16:20** | Snehil: URL is live. Tim: `/` renders something. David: agent confirmed running. **If S2 has not landed by 16:20, everyone stops and helps.** |
| **17:30** | Tim: landing + atlas on real data, search box works for seeded companies. Snehil: S4 done. David: D1–D4 done. |
| **18:00** | Integration on the deployed URL. Discovery branch wired or explicitly cut. |
| **18:15** | **Feature freeze.** Nothing merges after this. |
| **18:15–19:00** | Rehearse twice, on the deployed URL, not localhost. |
| **19:00** | Buffer. |
## 7. Cut list — in this order, without discussion
1. Whole-map page (`industry_map` — endpoint is real, no UI, cut the UI not the endpoint)
  
2. Brief page (closest to done of the three, but it is not one of the two pages that matter)
  
3. Compliance panel — `compliance_fallout` returns `[]` because no risk data is cited. An empty panel reads as broken. Cut it rather than ship it hollow.
  
4. Diff-monitor UI, `root.shared`, auth
  

**Never cut:** the deployed URL, the landing page, the atlas search box, the two rehearsals.
## 8. Merge protocol
The root cause of §3.1 was work living somewhere nobody merged from.

- Everyone works on `main`. Small commits. Push every 20 minutes even if unfinished.
  
- `jac check` your own files before pushing. `jac test main.test.jac` is David's gate.
  
- If tests report `readonly database`, kill your `jac start` processes — that is a lock, not a bug.
  
- Say it in the group chat when you touch a file outside your lane. Do not do it silently.
  
## 9. What to say on stage
Lead with provenance, not the graph:

> "Nineteen companies, 555 disclosed dependencies, every one read out of a public Article 28 filing with the source URL attached. One of the twenty we could not read — it's a client-rendered trust center, and we report that instead of guessing."

Best Jac line:

> "Reads are unbounded and free — full BFS over the whole reachable component in 729 milliseconds — because in Jac the graph _is_ the database. We put the budget on crawling, which costs money, not on depth, which doesn't."

Then the agent, if David lands D3: _"this isn't a scraper with an if/elif chain — the agent decides where to look."_

Do not narrate any number that is not in §2.
