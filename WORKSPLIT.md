# Blast Radius — final work split

**Demo 19:15 PT. Baseline commit `7f3e852` on `main`, verified green.**

**Tim → frontend · Snehil → deploy · David → search + discovery agent**

Sections 3 and 4 are written to be **pasted directly into a coding agent**. Each is
self-contained: exact files, exact line numbers, exact signatures, exact acceptance
commands. Hand your section to your agent verbatim.

---

## 1. Verified state — run at baseline `7f3e852`

| Check | Result |
|---|---|
| `jac check main.jac` | **PASSED** |
| `jac check extract.jac` | **PASSED** |
| `jac test main.test.jac` | **9/9 OK** |
| Live LLM through the real module | `canonicalize_with_llm("Amazon Web Services EMEA SARL") -> "AWS"` |
| Graph | 293 companies, 555 edges, 19/20 filings readable |

Real numbers, safe to say on stage — all from the passing test run, none invented:

- Okta 89 disclosed subprocessors · Figma 54 · Intercom 43 · Stripe 40 · HubSpot 32 · Notion 32 · Linear 32 · Cloudflare 30 · GitHub 30
- Top chokepoint: **Microsoft Azure — 6 of 19 companies (30%)**, then Salesforce 15%, Cloudflare 15%
- `openrouter.ai` = the one we honestly could not read

**Do not narrate any number that is not in this table.**

---

## 2. What just happened, so nobody repeats it

Two regressions arrived with the `feat: add search and discovery pipeline` merge
(`453dbfd`) and were fixed in `7f3e852`:

1. **byLLM was imported as `jaclang.byllm.lib`.** That module does not exist. The type
   checker resolves it anyway, so `jac check` passed while every runtime import of
   `extract.jac` died with `No module named 'jaclang.byllm'`. **The correct path is
   `byllm.lib`.** Do not "fix" it back.
2. **`main.jac:368` dropped the `[0]` on `root ++> Company(...)`.** `++>` returns a
   **list**. `main.jac` failed to type-check entirely.

Also landed in `7f3e852`: the four page exports were renamed to the file-router
convention. Jac file routing requires `def:pub page()` per page and `def:pub layout()`
for layouts; ours were `Landing()` / `Atlas()` / `Brief()` / `Shell()`, so **zero routes
registered and the app served a blank div.**

What `453dbfd` did deliver, and it is genuinely useful:

- `provider_evidence.jac` — 15 providers with SOC 2 status **and a source URL each**.
  This is the first cited risk data in the project; it is what `compliance_fallout` needs
  in order to stop returning `[]`.
- `atlas_seed.jac` — seed parsing, validation and normalization hardening.

What `453dbfd` did **not** deliver, despite the commit message: **search is still not
wired to discovery.** `search` has no `allow_discovery` parameter and
`discover_and_resolve` still has zero callers. That is §4.

### Rules

- Work on `main`. Push every 20 minutes even if unfinished.
- `jac check` your own files before pushing.
- If `jac test` says `readonly database`, kill your `jac start` processes. That is a
  SQLite lock, not a bug.
- `/Users/twaldin/blast-radius-swiss` is a stray agent's scratch checkout. **Do not merge it.**

---

## 3. SNEHIL — deploy. Paste everything below into your agent.

> **Task: get Blast Radius deployed and keep the URL current.**
>
> Repo `/Users/twaldin/jackhacks-jul-26`, branch `main`, baseline `7f3e852`. It is green:
> `jac check main.jac` passes and `jac test main.test.jac` is 9/9. You do not need to read
> `main.jac` except for one task (S3). Do not touch `pages/`, `risk/`, or `extract.jac` —
> other people are in those files right now.
>
> **S1 — one replica.** In `jac.toml`, `[scale.kubernetes]` sets `max_replicas = 4` with no
> `[plugins.scale.database]` configured. Each replica gets its own SQLite, so users see a
> different graph depending on which pod they hit. Set `max_replicas = 1`.
> *Done when:* `jac.toml` shows `max_replicas = 1`.
>
> **S2 — deploy on what exists right now.** Do not wait for any feature. Entry point is
> `main.jac`, `kind = "web-app"`.
> *Done when:* a public URL answers
> `curl -X POST <URL>/walker/atlas -H 'content-type: application/json' -d '{}'`
> with a JSON body containing `"total": 19`.
>
> **S3 — cold-start seeding.** The `seed_atlas` walker in `main.jac` resolves its seed
> directory with `Path("seed/atlas")`, which is relative to the **process working
> directory**. In a container whose CWD differs, `base.exists()` is `False`, the walker
> reports `seeded: 0` and *succeeds silently* — so a fresh deploy serves an empty graph and
> nothing looks broken. Two changes:
>   1. Resolve the path relative to the **module file** instead of CWD.
>   2. Make it run automatically when the graph is empty, so no human has to remember to
>      `curl` it after every deploy.
>
> This is the only task that edits `main.jac`. It is about 10 lines and confined to the
> `seed_atlas` walker. Tell David in chat before you push — he is editing the `search`
> walker in the same file.
> *Done when:* a container started with a fresh database serves `"total": 19` from
> `/walker/atlas` with no manual curl, and `jac test main.test.jac` is still 9/9.
>
> **S4 — check the toolchain pin.** `jac.toml` line 7 says `jac-version = "==0.34.7"` but
> the installed CLI reports `0.16.7`. If the builder honors that pin, install fails.
> Verify against the deploy build log and correct the pin if it breaks the build.
>
> **S5 — own redeploys.** Once a URL exists, keep it current as others push to `main`.
>
> **Order: S1, S2, then S3. Nothing else in the project matters until S2 is done.**
> Do not run project-wide formatters or linters. Do not refactor anything you were not asked to.

---

## 4. DAVID — search + discovery. Paste everything below into your agent.

> **Task: make search find companies that are not already in the graph.**
>
> Repo `/Users/twaldin/jackhacks-jul-26`, branch `main`, baseline `7f3e852`. You own
> `extract.jac`, `browser_discovery.jac`, `registry.jac`, and **the `search` walker inside
> `main.jac`** (starts at `main.jac:1016`). Do not touch `pages/`, `risk/`, or `jac.toml` —
> other people are in those files right now.
>
> **Context you need before writing code.**
>
> The LLM works. It is bound in `extract.jac` as
> `glob llm = Model(model_name=os.getenv("BLAST_RADIUS_MODEL", "gemini/gemini-2.5-flash"))`
> and `GEMINI_API_KEY` is in the environment. Verified live:
> `canonicalize_with_llm("Amazon Web Services EMEA SARL", [...])` returns `"AWS"`.
> **The byLLM import path is `byllm.lib`. It is NOT `jaclang.byllm.lib` — that module does
> not exist, it passes `jac check` and then dies at runtime. Do not change it.**
>
> A ReAct agent already exists and is correctly declared at `extract.jac:438`:
> `find_dpa_sources(company_keyword, domain) -> list[str] by llm(tools=[search_web_tool,
> read_page_tool, search_github_tool], temperature=0.0, max_tokens=1000,
> max_react_iterations=6)`. Its call chain is
> `find_dpa_sources <- discover_with_browser <- discover_and_resolve <- NOTHING`.
> `discover_and_resolve` is at `extract.jac:608` and has **zero callers**. Everything below
> is about giving it exactly one caller and making it safe.
>
> What `search` does today (`main.jac:1016`, params `q: str`, `limit: int = 20`): seven
> tiers of deterministic string matching — exact, alias, despaced, slug, Levenshtein ≤ 2,
> substring, then the 150-entry registry in `registry.jac`. No LLM, no browser, no
> discovery. For a company that is not already in the graph it returns
> `{"query": q, "resolved": null, "results": []}`. That is the gap.
>
> **D1 — prove the agent runs.** Call `find_dpa_sources("Vercel", "vercel.com")` directly
> and watch it plan and call tools.
> *Done when:* it returns real candidate URLs for a company outside the 150-entry registry.
>
> **D2 — harden `discover_and_resolve` (`extract.jac:608`).** Contract, frozen:
> ```jac
> async def discover_and_resolve(domain: str, company_keyword: str) -> str;
> ```
> It must **never raise**, must always return a status, and must return within **45
> seconds**. Wrap the whole body; catch `ByLLMError` and everything else.
> *Done when:* five junk inputs (`""`, `"   "`, `"!!!"`, a 500-char string, a domain that
> does not resolve) all return cleanly and none throw.
>
> **D3 — wire it into `search`. This is the whole point of your lane.**
> Add to the `search` walker:
> ```jac
> has allow_discovery: bool = False;
> ```
> Behavior: run the existing seven tiers unchanged. **Only if they all miss AND
> `allow_discovery` is true**, call `discover_and_resolve`, persist whatever it finds
> through the existing `_upsert_company` chokepoint in `main.jac`, and then return the
> normal envelope with the newly created company in `resolved`. Add a `"discovered": bool`
> field to the report so the frontend can label it. The response shape is otherwise
> **unchanged** — the frontend is already built against it:
> ```jsonc
> {"query": "...",
>  "resolved": {"id","domain","name","state","filing_count","dependent_count",
>               "crawl_status","source_url","match"},
>  "results": [ ...same shape... ],
>  "discovered": false}
> ```
> Default `allow_discovery` to `False` so the fast path and the demo never block.
> *Done when:*
> `search{q: "vercel", allow_discovery: true}` resolves a company that was not in the graph
> beforehand, `search{q: "okta"}` still returns instantly from the graph, and
> `jac test main.test.jac` is still 9/9.
>
> **D4 — decide the no-browser story. This is what will break on stage.**
> `browser_discovery.jac:118-165` shells out to a `browser-harness` binary driving Chrome
> over CDP. **That binary and that browser will not exist in the deployed container.**
> Pick one and implement it: either discovery degrades cleanly and fast to
> `status: "unreadable"` when the harness is absent, or discovery runs LLM-only through
> `search_web_tool` with no browser at all. Either is fine. Hanging for 45 seconds in front
> of a judge is not.
> *Done when:* with `browser-harness` unavailable, `discover_and_resolve` returns a clean
> status in under 5 seconds.
>
> **D5 — you are the only person changing backend logic.** `jac test main.test.jac` must be
> 9/9 before every push. If it reports `readonly database`, kill your `jac start`
> processes — that is a SQLite lock, not a bug.
>
> **Order: D1, D2, D3, D4. D3 is the deliverable; if you run out of time, D3 with a
> browser-less fallback beats D4 done perfectly.**
> Do not run project-wide formatters or linters. Do not refactor anything you were not asked to.

---

## 5. TIM — frontend (`pages/`, `risk/`)

| # | Task | Done when |
|---|---|---|
| T1 | ~~Rename the four route exports to `page()` / `layout()`~~ | **done in `7f3e852`** |
| T2 | Fix the 6 `jac check` failures — `pages/index.jac`, `pages/atlas.jac`, `pages/brief.jac`, `risk/store.jac`, `risk/DependencyGraph.jac`, `risk/graph_core.cl.jac`. All are `any`-typing: `len(x as list)`, `as str` / `as float` casts | `jac check pages/*.jac risk/*.jac` clean |
| T3 | **Landing = real data.** Delete the 8 hardcoded literals at `pages/index.jac:8-17`; drive the picker from `atlas {}` — 19 real companies with real counts and chokepoints. Add the project/problem copy | landing lists Okta/Figma/Stripe with real subprocessor counts |
| T4 | **Kill the fixture path.** `risk/store.jac:123-134` calls `expand {}` with no domain, then falls back to `detect_vendors` → the fabricated 8-vendor stack. Replace: `atlas {}` on load, `graph {domain}` on select | `detect_vendors` / `DEMO_VENDORS` have no frontend callers; the apology line at `pages/atlas.jac:160` is deleted |
| T5 | **Atlas search box.** Input → `search {q}` → hit list → select → `graph {domain}`. On an empty result, a "map it now" button that re-calls with `allow_discovery: true` plus a spinner | typing "okta" draws Okta's 89-dependency graph |
| T6 | Keep the SVG radial renderer in `risk/DependencyGraph.jac` — it works and pulls no npm dependency | — |

T5 needs David's D3 **only** for the discovery branch. Build the box against plain
`search {q}` immediately — that works today and covers every seeded company.

---

## 6. API contract — verified payloads, will not change

Envelope for all of them: `{"data": {"reports": [ <payload> ]}}`.

```jsonc
// POST /walker/atlas {}                        -> the landing page's company list
{"total": 19, "companies": [{
  "id": "figma", "domain": "figma.com", "name": "Figma", "featured": true,
  "vendor_count": 51, "provider_count": 81,
  "top_chokepoint": "Salesforce", "top_chokepoint_id": "salesforce",
  "top_share": 0.06, "vendors_affected": 3,
  "source_url": "https://www.figma.com/sub-processors/"}]}

// POST /walker/graph {"domain": "lindy.ai"}    -> one company's dependency graph
{"nodes": [{"id","label","tier","inbound_degree","soc2","supply_chain_risk",
            "downtime_hours_ytd","domain","category","crawl_status",
            "source_url","risk_source_url"}],
 "edges": [{"source","target","kind","purpose","region","handles_pii"}]}
// tier is "org" | "vendor" | "provider", computed as BFS distance from the viewed company

// POST /walker/search {"q": "aws", "allow_discovery": false}   // allow_discovery = David's D3
{"query","resolved","results","discovered"}

// POST /walker/chokepoints {}
[{"provider","provider_id","vendors_affected","share","downtime_hours_ytd",
  "exposure","downtime_cited","names","vendor_ids"}]

// POST /walker/blast_radius {"failed_provider": "azure"}
{"provider","provider_id","vendors_down","vendor_ids","features_down","status_post"}

// POST /walker/dependents {"domain": "..."}    -> inbound: who depends on this
{"nodes","edges","root","root_domain","root_label","direction":"inbound","dependent_count"}

// POST /walker/industry_map {"min_degree": 2}  -> the whole-map page (stretch)
```

---

## 7. Timeline and cut list

| Time | Gate |
|---|---|
| **+20 min** | Snehil: URL live. Tim: `/` renders. David: D1 confirmed. **If the URL is not up, everyone stops and helps.** |
| **17:30** | Tim: landing + atlas on real data, search box working for seeded companies. Snehil: S3 done. David: D2 + D3 done. |
| **18:00** | Integration on the deployed URL. Discovery branch wired or explicitly cut. |
| **18:15** | **Feature freeze.** Nothing merges after this. |
| **18:15–19:00** | Rehearse twice, on the deployed URL, not localhost. |

Cut in this order, without discussion:

1. Whole-map page (`industry_map` endpoint is real — cut the UI, keep the endpoint)
2. Brief page
3. Compliance panel — **unless** someone wires `provider_evidence.jac`'s 15 cited SOC 2
   facts into `compliance_fallout`, it returns `[]` and the panel renders empty. An empty
   panel reads as broken. Ship it cited or cut it.
4. Diff-monitor UI, `root.shared`, auth

**Never cut:** the deployed URL, the landing page, the atlas search box, the two rehearsals.

---

## 8. What to say on stage

Lead with provenance, not the graph:

> "Nineteen companies, 555 disclosed dependencies, every one read out of a public Article 28
> filing with the source URL attached. One of the twenty we could not read — it's a
> client-rendered trust center, and we report that instead of guessing."

Best Jac line:

> "Reads are unbounded and free — full BFS over the whole reachable component in 729
> milliseconds — because in Jac the graph *is* the database. We put the budget on crawling,
> which costs money, not on depth, which doesn't."

Then the agent, if David lands D3: *"this isn't a scraper with an if/elif chain — the agent
decides where to look."*
