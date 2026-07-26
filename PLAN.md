# Blast Radius — Fan-Out Plan

Deep spec: [`blast-radius-build-spec.md`](./blast-radius-build-spec.md). This file is the **crystal-clear work split** — read it, pick your lane, go.

**Track:** Agentic AI (main) + Best Use of Jac + Best Use of JacHammer + AI for Defense.
**One-liner:** *Your vendors have vendors.* We map the second layer from vendors' own legal filings, find the single point of failure your "redundant" stack secretly shares, and turn it into a risk memo, a live outage sim, and a compliance-fallout report.

---

## Status: the JacHammer demo graph is E2E green and the contract is FROZEN

The API now builds and traverses the pre-warmed `jachammer.ai` graph through the
real public walkers. The visible UI graph is **14 nodes / 19 edges**:
1 org + 8 vendors + 5 providers, with 8 `Uses` and 11 `Subprocesses` edges.
The complete domain graph also contains 5 deduplicated `Feature` nodes and 8
`Powers` edges, for **19 domain nodes / 27 typed domain edges**. **Nobody is blocked.**

```bash
jac start main.jac --port 8000
# then, from another shell:
curl -s -X POST localhost:8000/walker/one_look -H 'content-type: application/json' -d '{}'
```

Files already in the repo:

| File | Owner | State |
|---|---|---|
| `main.jac` | **A** | real typed graph, traversal, scoring, outage, compliance, and snapshot walkers; E2E-tested. |
| `contracts.jac` | shared, **frozen** | `DetectedVendor`, `SubprocessorRecord`, `ResolvedSubprocessor`, `RiskHeadline`. |
| `jac.toml` | **C** | `kind = "api-service"`. C adds `[scale.*]` for deploy. |
| `.gitignore` | — | ignores `.jac/`, venvs, `node_modules`. |
| `extract.jac`, `registry.jac` | **B** | real typed extraction/resolution plus 150-company registry. |
| `demo_data.jac` | **B** | explicit offline demo fixture; no longer mixed into `extract.jac`. |
| `browser_discovery.jac`, `browser_worker.py` | **B** | bounded Browser Harness escalation adapter; deferred off the demo path. |
| `app.jac` | **C** | not created yet — C owns the `cl def` frontend. |

---

## THE FROZEN CONTRACT — do not rename a field without a group call

All endpoints are `POST /walker/<name>`. Response envelope is always:

```json
{ "data": { "reports": [ <PAYLOAD> ] } }
```

**C reads `data.reports[0]`.** That is the payload. (For list-returning walkers, `data.reports[0]` is the list.)

| Endpoint | Request body | `data.reports[0]` payload |
|---|---|---|
| `detect_vendors` | `{"domain": "jachammer.ai"}` | `{"found": int, "vendors": [{"domain","name","method"}]}` |
| `expand` | `{}` | `{"nodes": [Node], "edges": [Edge]}` |
| `chokepoints` | `{}` | `[{"provider","vendors_affected","share","downtime_hours_ytd","exposure","names":[str]}]` |
| `blast_radius` | `{"failed_provider": "AWS"}` | `{"provider","vendors_down":[str],"features_down":[str],"status_post":str}` |
| `compliance_fallout` | `{}` | `[{"vendor","provider","reason","breaks"}]` |
| `one_look` | `{}` | `{"biggest_risk":str,"biggest_suggestion":str}` |

**Node** = `{"id","label","tier","inbound_degree","soc2","supply_chain_risk","downtime_hours_ytd"}`
`tier` ∈ `org | vendor | provider`. **Edge** = `{"source","target","kind"}`, `kind` ∈ `uses | subprocesses`.

The rehearsed graph is `jachammer.ai` → 8 vendors → 5 providers, **AWS is the
chokepoint** (5 of 8 vendors, 9.2h downtime, `Fastly` carries the
compliance-fallout example).

---

## Remaining work split — one layer each, own your file

### Person A — Graph & Traversal (`main.jac`) — *this is you*
Replace the hardcoded reports with real object-spatial logic. **Only A creates nodes/edges.**

1. Graph model — `node`/`edge` with **typed endpoints** (`edge Uses: Org --> Vendor`). Add the new fields already in the contract: `Provider.soc2/hipaa/supply_chain_risk/downtime_hours_ytd`, `Subprocesses.handles_pii`.
2. `DetectVendors` + `AddVendors` walkers — write vendor nodes from B's `detect_all` output + the manual text box.
3. `Expand` walker — BFS, `max_depth=2`, `seen` guard for cycles; calls B's `extract_and_resolve`; creates `Provider` nodes + `Subprocesses` edges via `find_or_create_provider`.
4. `Chokepoints` — `[prov <-:Subprocesses:<-]`, the core algorithm. Score `share × downtime_hours_ytd = exposure`.
5. `BlastRadius` — backward traversal → affected vendors → features.
6. `ComplianceFallout` — same inbound query; flag providers with `not soc2` or `supply_chain_risk != ""`, propagate up.
7. `one_look` wiring (calls B/ C's `by llm` `one_look`) + `DiffMonitor` on `@schedule` (Tier 3).
8. Switch `walker:pub` → `walker:priv` for per-user root isolation once C's auth is wired.
**Keep the JSON report shapes byte-identical to the contract above** so C never rebuilds.

### Person B — Data & Extraction (`extract.jac`, `registry.jac`)
Everything from "a domain" to "clean canonical records." **Returns values, never touches the graph.** Both `by llm()` calls + the ReAct agent are yours.

1. `registry.jac` — ~150 SaaS vendors → exact subprocessor URL. **Seed the ~20 anchor providers** (AWS, GCP, Azure, Cloudflare, Fastly, Twilio, SendGrid, Snowflake, Datadog…) — canonicalization needs anchors or the chokepoint never appears.
2. Seed provider **compliance + downtime** data (`soc2`, `hipaa`, `supply_chain_risk`, `downtime_hours_ytd`) for the top ~20 — same curated asset.
3. `detect_all(domain)` — MX / SPF-DMARC TXT / CNAME / HTTP headers / `<script>` tags **+ IP-range → cloud** (jachammer.ai resolves to AWS us-east-2 IPs on Route 53; that's the live detect).
4. `fetch_page` — real UA, 5s timeout, concurrency ~10, cache by domain. **Pre-warm the demo cache** for the manually-added jachammer.ai stack.
5. `extract_subprocessors` (`by llm`, `sem`) → `list[SubprocessorRecord]`.
6. `canonicalize` (`by llm`) — the load-bearing entity-resolution call.
7. `extract_and_resolve(page_text, known) -> list[ResolvedSubprocessor]` — the single export A calls.
8. **Registry-miss ReAct fallback (§4.3, deferred until after the demo):**
   `resolve_url` = exact curated/learned registry lookup first. Only on a true
   miss, the Jac ReAct agent gets narrow Firecrawl `search` and `scrape` tools.
   Search locates official company or verified GitHub candidates; scrape
   renders/extracts a known candidate. A separate bounded Browser Harness
   escalation handles trust-center click-throughs or pages Firecrawl cannot
   extract. Do not hand unrestricted CDP control to the ReAct agent.
   Deterministic validation rejects snippets, aggregators, login walls, and
   change notices without a complete current named list. B returns typed
   evidence and updates only the learned registry; A alone upserts graph nodes.
   Limit the miss path to 4 searches, 8 pages, and 30–45 seconds; cache positive
   results by source hash and negative results with a short TTL. If no
   authoritative complete list is found, return `notfound`. Firecrawl Agent is
   a later tertiary option, not the first implementation.
9. Defense adapter — DoD prime → sub → tier-3 (renders on the same canvas).

### Person C — Interface, Deploy & Pitch (`app.jac`)
Build the entire UI against the frozen endpoints **right now** — the real demo
graph already serves them.

1. **Deploy the current E2E graph to JacHammer now.** Get the public URL.
2. `cl def:pub app` skeleton reading `data.reports[0]` from each walker.
3. Force graph (spec §6.1): **tier-pinned x, force-solved y**, `sqrt` node sizing by `inbound_degree`, prune providers with <2 dependents. `react-force-graph-2d` via npm.
4. **Outage sim** (spec §6.2): backward-propagation animation, red reserved for blast radius only.
5. WebSocket live-stream the crawl, batched at 200ms.
6. **One-look card** (biggest risk + biggest suggestion) + **compliance-fallout panel** on the same screen.
7. `draft_status_update` + `risk_memo` (`by llm`) render into their panels.
8. `jac.toml` `[scale.*]` + verify `jac start --scale` comes up.
9. **Write the 3-min script. Rehearse twice.**

---

## Integration order (set alarms)

| When | Checkpoint |
|---|---|
| now | **Demo graph E2E is green.** Freeze the graph payload and connect the UI. |
| next | Get the 14-node/19-edge graph, chokepoint, outage, compliance, and one-look flow onto the deployed JacHammer demo. |
| after deploy | Rehearse the deterministic demo from a clean graph and fix only script-blocking defects. |
| after rehearsal | Add the Firecrawl-first registry-miss ReAct path; keep it out of the scripted demo. |
| −3 hr | Feature freeze (Tier 1+2). |
| −2 hr / −1 hr | Rehearsal #1 on the deployed URL, then #2. Cut anything not in the script. |

## Gotchas (already bit us or verified today)

- **`contracts.jac`, never `types.jac`** — `types` collides with Python stdlib and imports the wrong module.
- **byLLM model:** `openrouter/openai/gpt-4o-mini` (extraction/canonicalize) + `openrouter/openai/gpt-4o` (agent/memos). `OPENROUTER_API_KEY` is set. Smoke-tested working (structured output + ReAct loop). Fallbacks: `GEMINI_API_KEY`, vibeproxy `:8317`, Ollama `:11434`.
- **Demo the non-dev server** (`jac start main.jac --port N`), **not `--dev`** — `--dev` has an IPv6 proxy bug (`::1` vs IPv4 → `ECONNREFUSED`).
- **`jac-scale` needs `pip install requests`** into `.jac/venv` after `jac install` (its non-test deps omit it).
- **`jac clean --all`** before any graph rehearsal or you hit `NodeAnchor` errors on stage.
- **Root entry is `with Root entry`** (capital `Root`), not `` with `root entry `` — the backtick form type-warns.
- Current Jac `++>` and a single typed connect return the connected **node**, not
  a one-item list. Do not index `[0]`. Typed edges create with
  `+>:E(...):+>` (plus on both sides).

## Stage roles
Snehil pitches. C drives the laptop. Jac Q&A splits by pillar: **A = object-spatial** (walkers/traversal/persistence), **B = meaning-typed + agentic** (`by llm`, entity resolution, ReAct loop), **C = scale-invariance** (one file → `jac run`/`jac start`/`--scale`, JacHammer).
