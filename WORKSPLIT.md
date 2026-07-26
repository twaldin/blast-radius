# Blast Radius — final work split

**Written 16:00 PT. Demo 19:15 PT. 3h15m left.**
**A = Tim (backend/graph) · B = David (extraction/agent) · C = Snehil (frontend)**

This supersedes `PLAN.md`, `SPEC-V2.md`, `blast-radius-build-spec.md`, and `REVIEW.md`
wherever they disagree. Those docs describe a product we did not build. Everything below
was verified by running it in the last 40 minutes.

---

## 1. Bottom line

The backend is **done and genuinely good**. The frontend **serves a blank page**. The
agent **had no model bound and could not run at all**. Two of those three facts were not
known an hour ago, and neither was in any existing doc.

Read §3 before you write code. Two of the four root causes are things people believe are
working right now.

---

## 2. Verified state

Run at 15:55 PT against `main` @ `66d742c`.

| Area | State | Evidence |
|---|---|---|
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

---

## 3. What actually went wrong — four root causes

### 3.1 The frontend has never rendered. Not "shows wrong data" — blank.

Jac file-based routing requires every page file to export **`def:pub page()`** and layouts
**`def:pub layout()`** (`jac guide jac-cl-routing`). Ours export:

| File | Exports | Needs to be |
|---|---|---|
| `pages/index.jac:23` | `Landing()` | `page()` |
| `pages/atlas.jac:16` | `Atlas()` | `page()` |
| `pages/brief.jac:63` | `Brief()` | `page()` |
| `pages/layout.jac:34` | `Shell()` | `layout()` |

Zero routes register. `curl localhost:8010/` returns a shell that mounts
`{"module":"main","function":"app"}` → `main.jac:1193`, which is `<>{children}</>` with no
router and no children. **An empty div.**

`REVIEW.md` §2 says the app "renders an 8-vendor fabricated fixture". That was inferred
from reading `store.jac`, not from loading the page. It renders nothing at all. The fix is
four renames.

On top of that, **6 of 9 frontend files fail `jac check`** (`pages/index.jac`,
`pages/atlas.jac`, `pages/brief.jac`, `risk/store.jac`, `risk/DependencyGraph.jac`,
`risk/graph_core.cl.jac`).

### 3.2 Every LLM call in the repo was dead. — FIXED, committed as `66d742c`

byLLM binds `by llm(...)` to a module-global named `llm`. **No `Model(...)` was declared
anywhere in the repo.** byLLM silently fell back to OpenAI; there is no `OPENAI_API_KEY` on
this machine. Every call — `extract_subprocessors`, `canonicalize_with_llm`,
`find_dpa_sources` — failed at runtime with `litellm.InternalServerError: Missing
credentials`.

So "backend with LLMs" was not partially done. It was 0%.

Fixed in `extract.jac`: `glob llm = Model(model_name=os.getenv("BLAST_RADIUS_MODEL",
"gemini/gemini-2.5-flash"))`. `GEMINI_API_KEY` is already in the environment. Verified live
through the real module:

```
canonicalize_with_llm("Amazon Web Services EMEA SARL", [...])  ->  "AWS"
```

A tool-calling ReAct probe also completes its loop end to end. **B: your whole lane went
from impossible to working. Re-test anything you concluded was broken.**

### 3.3 The ReAct agent is unreachable, so the Atlas page's core promise has no implementation

`find_dpa_sources` (`extract.jac:397-405`) is a correct byLLM ReAct declaration — 3 tools,
`max_react_iterations=6`. Its call chain:

```
find_dpa_sources  <-  discover_with_browser  <-  discover_and_resolve  <-  NOTHING
```

`discover_and_resolve` has **zero callers**. `main.jac` does not import it.

What the `search` walker actually does today: 7 tiers of deterministic string matching
(exact → alias → despaced → slug → Levenshtein≤2 → substring → 150-entry registry). No LLM,
no browser, no discovery. For a company not already in the graph it returns
`{"resolved": null, "results": []}`. `map_company` is not an escape hatch either — it falls
through to `resolve_url`, which is registry-only, and returns `"notfound"`.

**"Search for an arbitrary company" — the entire point of the Atlas page — has no code path.**
This is also the Agentic-AI track centrepiece.

### 3.4 A fresh deploy comes up empty

`seed_atlas` is idempotent, tested, and **called by nothing**. Worse, it resolves
`Path("seed/atlas")` relative to process CWD; in a container that silently reports
`seeded: 0` and succeeds. Plus `jac.toml:42` sets `max_replicas = 4` with no shared
database → four pods, four different graphs.

### Also worth knowing

- The 9/9 test failure everyone saw was **a stale `jac start` on :8010 holding the SQLite
  WAL**, not a code fault. Killed it; suite is green. If tests say "readonly database",
  kill your servers.
- `/Users/twaldin/blast-radius-swiss` is **not** anyone's work — it's a scratch checkout
  from an agent running loose on Tim's machine. Do not merge it. It is 5 commits behind and
  pulls in a `react-force-graph-2d` npm dependency we already removed. It is useful as a
  **reference only**: it happens to contain a working search-input pattern
  (`pages/index.jac:129-142`) and a store `search` action (`store.jac:273`). Copy the
  pattern, not the files.

---

## 4. Frozen API contract — read this, then never block on each other

These payloads are **verified from the passing test run**. They will not change. C builds
against them without waiting for A; A builds against B's signature without waiting for B.

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
 "discovered": false}                          // <- NEW, added by A in §5

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

**The one contract that does not exist yet — A and B agree to this now and build in parallel:**

```jac
# B owns the body. A owns the caller. Signature is frozen as of 16:00.
def discover_and_resolve(domain: str, keyword: str) -> BrowserDiscoveryResult;
# B guarantees: never raises; status in {"ok","notfound","unreadable"}; returns in <=45s.
# A guarantees: persists results through _upsert_company; response shape unchanged.
```

`discover_and_resolve` already exists at `extract.jac:570-593`. B hardens it, A calls it.
Neither waits.

---

## 5. Lanes

Each lane owns disjoint files. **Do not edit outside your lane** — cross-lane edits are
what produced §3.1.

### A — Tim · owns `main.jac`, `jac.toml`, deploy

| # | Task | Done when |
|---|---|---|
| A1 | **Deploy now, on what exists.** `max_replicas = 1` (`jac.toml:42`). Commit the `jac.toml` byLLM fix that is still sitting uncommitted. | A URL exists and answers `POST /walker/atlas` with 19 companies |
| A2 | Cold-start seeding: make `seed_atlas` resolve `seed/atlas` **relative to the module file, not CWD**, and auto-run when the graph is empty | Fresh container serves 293 companies with no manual curl |
| A3 | `search` gains `allow_discovery: bool = False` and a `"discovered"` field. On graph+registry miss with the flag set, call `discover_and_resolve` (§4), persist via `_upsert_company`, return the same envelope | `search{q:"vercel", allow_discovery:true}` returns a resolved company that was not in the graph before |
| A4 | Keep `main.test.jac` at 9/9 | green before every push |

A1 is first and is not negotiable. Everything else in this document is worthless without a URL.

### B — David · owns `extract.jac`, `browser_discovery.jac`, `registry.jac`

**Your lane was blocked by a dead LLM binding until 15:50. It works now. Start by re-running
whatever you gave up on.**

| # | Task | Done when |
|---|---|---|
| B1 | Verify the ReAct agent end to end: call `find_dpa_sources("Vercel", "vercel.com")` directly and watch it plan | It returns real candidate URLs for a company not in the 150-entry registry |
| B2 | Harden `discover_and_resolve` to the §4 guarantee: never raises, always returns a status, hard 45s ceiling | Fuzzed with 5 junk inputs, never throws |
| B3 | Make it work without a local browser, or make the fallback honest. `browser_discovery.jac` shells out to a `browser-harness` binary + Chrome CDP that **will not exist in the deployed container** | Either it degrades cleanly to `unreadable`, or discovery runs LLM-only via `search_web_tool` |
| B4 | Confirm `extract_subprocessors` produces typed records off one real page now that the model is bound | One live extraction, eyeballed |

B3 is the one that will bite on stage. Decide early: if the deployed box has no browser,
say so in the UI rather than hanging for 45 seconds.

### C — Snehil · owns `pages/`, `risk/`

This is the biggest lane. **Do not merge the swiss checkout** (§3.4 note); it will cost you
more than it saves.

| # | Task | Done when |
|---|---|---|
| C1 | **Rename the four exports** — `Landing`→`page`, `Atlas`→`page`, `Brief`→`page`, `Shell`→`layout` | `/` renders literally anything. ~2 minutes. Do it first |
| C2 | Fix the 6 `jac check` failures (§3.1) | `jac check pages/*.jac risk/*.jac` clean |
| C3 | **Landing = real data.** Delete the 8 hardcoded literals at `pages/index.jac:8-17`; drive the picker from `atlas {}` (19 real companies with counts and chokepoints). Add the project/problem copy | Landing lists Okta/Figma/Stripe with real subprocessor counts |
| C4 | **Kill the fixture path.** `risk/store.jac:123-134` calls `expand {}` with no domain and falls back to `detect_vendors` → the fabricated 8-vendor stack. Replace with `atlas {}` on load, `graph {domain}` on select | `detect_vendors` and `DEMO_VENDORS` have no frontend callers. Delete the apology line at `pages/atlas.jac:160` |
| C5 | **Atlas search box** — the page's whole reason to exist. Input → `search {q}` → hit list → select → `graph {domain}`. On empty result, show a "map it now" button that re-calls with `allow_discovery: true` and a spinner | Typing "okta" draws Okta's 89-dependency graph |
| C6 | Keep the SVG radial renderer in `risk/DependencyGraph.jac`. It works and has no npm dependency | — |

C5 depends on A3 only for the *discovery* branch. Build the search box against plain
`search {q}` immediately — that already works today and covers every seeded company.

---

## 6. Timeline

| Time | Gate |
|---|---|
| **16:20** | A: URL is live. C: `/` renders something. B: agent confirmed running. **If A1 has not landed by 16:20, everyone stops and helps.** |
| **17:30** | C: landing + atlas on real data, search box works for seeded companies. A: A2+A3 done. B: B1–B3 done. |
| **18:00** | Integration on the deployed URL. Discovery branch wired or explicitly cut. |
| **18:15** | **Feature freeze.** Nothing merges after this. |
| **18:15–19:00** | Rehearse twice, on the deployed URL, not localhost. |
| **19:00** | Buffer. |

## 7. Cut list — in this order, without discussion

1. Whole-map page (`industry_map` — endpoint is real, no UI, cut the UI not the endpoint)
2. Brief page (closest to done of the three, but it is not one of the two pages that matter)
3. Compliance panel — `compliance_fallout` returns `[]` because no risk data is cited. An
   empty panel reads as broken. Cut it rather than ship it hollow.
4. Diff-monitor UI, `root.shared`, auth

**Never cut:** the deployed URL, the landing page, the atlas search box, the two rehearsals.

## 8. Merge protocol

The root cause of §3.1 was work living somewhere nobody merged from.

- Everyone works on `main`. Small commits. Push every 20 minutes even if unfinished.
- `jac check` your own files before pushing. `jac test main.test.jac` is A's gate.
- If tests report `readonly database`, kill your `jac start` processes — that is a lock, not a bug.
- Say it in the group chat when you touch a file outside your lane. Do not do it silently.

## 9. What to say on stage

Lead with provenance, not the graph:

> "Nineteen companies, 555 disclosed dependencies, every one read out of a public Article 28
> filing with the source URL attached. One of the twenty we could not read — it's a
> client-rendered trust center, and we report that instead of guessing."

Best Jac line:

> "Reads are unbounded and free — full BFS over the whole reachable component in 729
> milliseconds — because in Jac the graph *is* the database. We put the budget on crawling,
> which costs money, not on depth, which doesn't."

Then the agent, if B lands it: *"this isn't a scraper with an if/elif chain — the agent
decides where to look."*

Do not narrate any number that is not in §2.
