# Blast Radius — SPEC v2: current code → deployed

Supersedes the lane tables in `PLAN.md`. Written against the **actual merged tree** at
`ffcf6bc`, after B's `data` push and C's `pages/` + `risk/` push.

**The pivot, in three parts:**
1. **Wideness, not depth** — stop building one deep demo graph. Build an **atlas** of many
   real company graphs, precomputed from real legal filings (§3).
2. **A whole-industry Map** — every crawled company and every disclosed dependency on one
   canvas, as a third view (§10).
3. **Swiss-editorial frontend, generalised** — take the full design system from
   `drafts/02-swiss-editorial`, strip its single-company copy, and replace the tier-pinned
   three-column graph with a free-form force layout (§9).

Reading order: **§0 unblocks the build, §1 gets us deployed.** Do those before anything
below them. A owns §4–5, B owns the data/search lane, C owns §9–10.

---

## 0. BLOCKING — ✅ ALL CLEAR. The tree boots.

All three breakages are fixed and pushed (`3108554`, `2f1a9f4`). `jac check` is clean on
every `.jac` file and `jac start main.jac --no_client --port 8000` boots.

| # | Where | Error | Fix |
|---|---|---|---|
| 1 | `main.jac` ×5 | `E1002`/`E1001` — `++>` returns a **list**; the `[0]` was dropped | ✅ restored |
| 2 | `extract.jac:261` | `E1054` — block lambda as sort key (and it was missing its `return`, so it sorted on `None`) | ✅ named typed fn |
| 3 | `extract.jac:6` | `No module named 'jaclang.byllm'` | ✅ path is `byllm.lib`; installed via `uv tool install jaclang --with byllm` |

> **Anyone setting up a fresh machine must run `uv tool install jaclang --with byllm`** —
> byLLM is not in the `jac` tool env by default and nothing boots without it.

**C: you are unblocked. Deploy now.**

---

## 0.5 Lane A status — ✅ COMPLETE (`2f1a9f4`)

`Company` model, write-time canonicalization, unbounded depth, seeding, and the new
endpoints are all landed and verified against real data. Details in §4/§5/§11/§12.
Live numbers from a cold boot:

```
seed_atlas   20 filings -> 19 ok, 555 disclosed dependencies, 293 companies
atlas        19 mapped companies                             2.9 s
graph        176 nodes / 259 edges (lindy.ai)                729 ms
chokepoints  122 ms   one_look 201 ms   blast_radius 98 ms   search 60 ms
```

Remaining for A, both post-MVP: `root.shared` migration, and Map tuning if §10 gets built.

---

## 1. Deploy is still not done, and it is still non-negotiable

`PLAN.md` called mid-afternoon JacHammer deploy non-negotiable. It has not happened.
It is now the single highest risk in the project — higher than the atlas, higher than
extraction quality.

**Rule: the moment blocker #1 is pushed, C deploys whatever is green.** Do not wait for
the atlas. Do not wait for real data. A deployed ugly graph beats an undeployed beautiful
one, and every hour we wait compounds the risk.

---

## 2. Editorial rule: delete everything we fabricated

I wrote `demo_data.jac` as throwaway stub fixtures. B preserved it verbatim, and C's
`docs/demo-script.md` now **asserts those inventions as fact on stage**:

> *"AWS logged 9.2 hours last year — that's the exposure number, not a vibe."*
> *"Fastly is amber because its SOC 2 is invalid and it's on a supply-chain watchlist."*

Both numbers are mine. I made them up. If a judge probes either, we lose the room, and
the "we don't assert more than the source does" line in C's own Q&A becomes false.

**The rule from here: if a real filing or a citable source didn't give it to us, we don't
ship it.** Unsourced fields return empty/zero and the UI hides that panel — never a
plausible-looking fake.

| Data | Status | Disposition |
|---|---|---|
| `DEMO_SUBPROCESSORS` (all 8 mappings) | **fabricated by A** | **DELETE.** 7 of 8 have real filing URLs in `registry.jac`. Crawl them for real. |
| `DEMO_VENDORS` (the 8-vendor stack) | **fabricated by A** | Replace — see §3. jachammer.ai cannot yield 8 vendors from live detection (bare uvicorn, no third-party tags). |
| `downtime_hours_ytd` (9.2 / 5.1 / 3.4 / 7.7 / 4.3) | **fabricated by A** | Default `0.0`. Rank chokepoints by **share** by default; downtime becomes an optional multiplier shown **only where cited**. |
| `soc2`, `supply_chain_risk` (Fastly watchlist) | **fabricated by A** | Remove the fake flags. Either B curates real ones **with a source URL per claim**, or `compliance_fallout` returns `[]` and C hides the panel. |
| `features` / `Feature` node / `Powers` edge | hand-mapped by A | **DELETE the node type.** `features_down` becomes the distinct set of `purpose` strings on the severed edges — that text is **real, straight from the filing** ("model hosting / compute", "error + log ingestion"). |
| per-feature `$ / h` cost | never in the spec, draft-11 only | **CUT.** |
| DoD / defense adapter | never implemented, prose only | **CUT from build.** Keep as a Q&A answer: *same engine, different data adapter.* |

Net effect: `demo_data.jac` shrinks to narrative helpers only. Every number on screen
traces to a `source_url`.

---

## 3. The atlas — what replaces the single demo org

**Insight that makes this cheap:** `registry.jac` already holds **150 companies with real
subprocessor URLs**. Every one of them is a graph root in its own right. OpenAI isn't only
*a vendor of* someone — OpenAI is a company with its own Article 28 disclosure. We already
own the atlas; we just haven't crawled it.

**Landing page:** rotating / selectable featured graphs, headline generated per company:

> *"**Anthropic** has a dependency cluster on **AWS** — if it goes down, **N** of its
> disclosed sub-processors go with it."*

with the bolded slots swapping between companies. Search over the atlas comes later.

**Featured set for the demo:** the highest-signal registry companies (OpenAI, Anthropic,
Stripe, Vercel, Sentry, Datadog, GitHub…), plus **lindy.ai** — Tim works there and can
vouch for the layer-1 list on stage, which is a stronger provenance claim than any
detection heuristic. `lindy.ai` is **not** in the registry yet; B adds it.

**jachammer.ai stays** as a featured entry (the meta beat), but its vendor list is
explicitly **declared**, not detected. That's honest and it's how the category actually
works — nobody can detect your SaaS stack from outside, which is exactly why Vanta makes
you type it in.

---

## 4. Graph model change: one `Company` node type

Today's `Org` / `Vendor` / `Provider` trichotomy **cannot express the atlas**: OpenAI would
have to exist as an `Org` *and* as a `Vendor`, duplicating the node and breaking the
"each company appears once" property.

```jac
node Company {
    has domain: str;              # canonical key: lowercase, no www
    has name: str;
    has slug: str;
    has source_url: str = "";     # the filing we read
    has crawl_status: str = "pending";
    has last_crawled: str = "";
    has content_hash: str = "";
    has is_sink: bool = False;    # terminal hyperscaler
}

edge Subprocesses: Company --> Company {
    has purpose: str = "";        # real text from the filing
    has region: str = "";
    has confidence: float = 1.0;
    has first_seen: str = "";
    has last_seen: str = "";
}
```

**`tier` is computed per view, not stored.** BFS from the company being viewed:
distance 0 → `org`, distance 1 → `vendor`, distance ≥2 → `provider`.

**This keeps the wire contract byte-identical.** `tier` still comes back as
`org|vendor|provider`; C's `store.jac` and `DependencyGraph.jac` do not change. Only
storage and traversal change.

It also fixes the Provider↔Vendor identity gap I flagged in `DECISIONS-A.md` §5 — for free.

### Depth: separate *walking* from *crawling*

This is the distinction the pivot was circling, and it resolves the depth-cap argument.

- **Walking is free.** Each company is one node, so a full BFS with a visited set is
  `O(V+E)` — microseconds. **No depth cap on reads.** `graph {domain}` returns the entire
  reachable component, exactly as deep as the data goes. This is what you asked for:
  unbounded, scoped, each company once, fast.
- **Crawling costs money.** Each *new* company is one fetch + one LLM extraction. So the
  budget lives on the crawl, and it is **`max_new_companies`, not depth**.

```
graph  {domain}                  -> unbounded read, instant
expand {domain, max_new: 40}     -> crawl frontier until budget spent
```

Because crawls are shared and cached (`content_hash` + TTL), the atlas gets *deeper for
everyone* every time anyone expands anything. Depth becomes emergent rather than capped.

---

## 5. Contract v2

All read walkers gain an optional `domain`. **Omitted → current behaviour**, so C's
existing five calls keep working unchanged while it migrates.

| Endpoint | Request | Notes |
|---|---|---|
| `atlas` | `{}` | **NEW.** `[{domain, name, slug, vendor_count, provider_count, top_chokepoint, headline}]` — drives the landing rotation. |
| `graph` | `{domain}` | **NEW.** `{nodes, edges}`, unbounded BFS, computed tiers. Replaces `expand`'s read half. |
| `expand` | `{domain, max_new, ttl_days, force}` | Crawl + return the graph. Budget-bounded. |
| `chokepoints` | `{domain}` | Ranked by `vendors_affected`; `exposure` only when downtime is cited. |
| `blast_radius` | `{domain, failed_provider}` | `features_down` = distinct `purpose` on severed edges. |
| `compliance_fallout` | `{domain}` | `[]` unless cited data exists. |
| `one_look` | `{domain}` | Headline for that company. |
| `crawl_progress` | `{domain}` | Unchanged. |
| `expand_one` | `{domain}` | Crawl exactly one company. |
| `industry_map` | `{min_degree?}` | **NEW.** Every company, every edge, one payload — powers the Map view (§10). |
| `search` | `{q, limit?}` | **NEW — landed.** Canonical resolution ladder over crawled companies **and** uncrawled registry entries. Returns `{query, resolved, results}`; `resolved` is non-null only on `exact`/`alias`. See §5.1. |
| `dependents` | `{domain, max_hops?}` | **NEW — landed.** Inbound BFS — "who depends on this". Same `{nodes, edges}` shape as `graph`, plus `root`, `root_domain`, `root_label`, `direction:"inbound"`, `dependent_count`. Edges keep real direction (source = dependent), so arrows point INTO the centre. See §5.1. |
| `map_company` | `{domain}` | **NEW — landed.** Promote a `registry`/`unknown` company into the graph (crawl its filing), so a searched dead end becomes a `mapped` node. |

**Dropped:** `expansion_candidates` (the depth-cap justifier — obsolete once depth is
uncapped), `detect_vendors`/`add_vendors` fold into a single `seed {domain, vendors[]}`.

### 5.1 Search resolution and the three company states

The search box is the front door. Everything a user types lands here, and the answer C
renders depends entirely on **which of four states** the resolved company is in. Render
each state differently — this is the single most important branch in the frontend.

#### The four states a searched company can be in

| State | Meaning | Count today | What C shows |
|---|---|---|---|
| `mapped` | we read its own Article 28 filing | 19 | forward graph: its vendors and their vendors (`graph {domain}`) |
| `known` | it appears inside others' filings, but we have not read its own | ~270 | **inbound view** — "N companies we mapped depend on this" (`dependents {domain}`) |
| `registry` | in our 150-vendor registry, not yet in the graph | — | offer "map it now" → `map_company {domain}` |
| `unknown` | nowhere | — | offer discovery |

A company's `state` is computed from its edges: **≥1 outbound `Subprocesses` edge →
`mapped`; 0 outbound but ≥1 inbound → `known`; not a graph node but in `VENDOR_REGISTRY` →
`registry`; otherwise `unknown`.**

#### Why `known` matters

Searching `AWS` used to dead-end. AWS has no filing of its own in our graph, but **19 of
our 19 mapped companies depend on it.** The inbound view turns ~270 dead ends into valid
destinations and makes the product's core claim — *"who sits underneath this"* — directly
searchable. A `known` company is not a failure state; it is the most interesting kind of
result we have.

#### The resolution ladder

`search` walks these rungs in order and stops at the first that hits. The rung that
matched is returned as `match` on each `Result`, so C knows how confident to be:

1. **exact** — canonical-key hit (`_canon_key` normalises case/punctuation/suffixes;
   `"OpenAI, L.L.C."` → the OpenAI node).
2. **alias** — alias table (`aws` → Amazon Web Services, `open ai` → OpenAI).
3. **despaced** — whitespace-insensitive canonical hit (`open ai` → `openai`). Returned as
   `match: "alias"`.
4. **slug / domain** — the slug or domain matches directly.
5. **fuzzy** — bounded edit-distance ≤ 2, catches typos (`openia` → OpenAI). `match: "fuzzy"`.
6. **substring** — legacy naive contains, last resort. `match: "fuzzy"`.
7. **registry offers** — no graph node, but present in the registry → `match: "registry"`,
   `state: "registry"`, so C can offer "map it now".

**`resolved` is non-null only for `exact` and `alias` matches.** On those two, the hit is
unambiguous and C should **auto-navigate** straight to the graph/inbound view. On anything
lower (`fuzzy`/`substring`/`registry`), leave `resolved: null` and **show the `results`
list as a picker** — never silently jump on a guess.

#### `POST /walker/search` — `{"q": str, "limit": int = 20}`

```json
{ "query": "aws",
  "resolved": { <Result> } | null,
  "results": [ <Result> ] }
```

`resolved` = the single unambiguous best hit (match `exact` or `alias` only); otherwise
`null`. Each `Result`:

```json
{ "id": "amazon-web-services", "domain": "", "name": "Amazon Web Services",
  "state": "mapped" | "known" | "registry" | "unknown",
  "filing_count": 0,        // outbound Subprocesses edges = its own disclosed vendors
  "dependent_count": 19,    // inbound Subprocesses edges = who depends on it
  "crawl_status": "pending",
  "source_url": "",
  "match": "exact" | "alias" | "fuzzy" | "registry" }
```

- `state` ∈ `mapped | known | registry | unknown` (definitions above).
- `filing_count` — outbound `Subprocesses` edges = its own disclosed vendors.
- `dependent_count` — inbound `Subprocesses` edges = who depends on it.
- `match` ∈ `exact | alias | fuzzy | registry`.

#### `POST /walker/dependents` — `{"domain": str, "max_hops": int = 2}`

The INBOUND view — "who depends on this". Same `Node`/`Edge` shape as `graph`, so C reuses
one canvas.

```json
{ "nodes": [Node], "edges": [Edge], "root": slug, "root_domain": str,
  "root_label": str, "direction": "inbound", "dependent_count": int }
```

- Tiers by inbound BFS distance: centre = `org`, direct dependents = `vendor`, their
  dependents = `provider`. Reuses the same `_node_payload(c, tier, indeg)` helper as `graph`.
- Edges keep the **real** direction: `source` = the dependent, `target` = the
  depended-upon. So on the canvas, arrows point **INTO** the centre — the mirror image of
  the forward `graph` view.


---

## 6. Lanes

### A — graph, traversal, contract *(me)*
1. ~~**Fix the 5 `[0]` errors.**~~ **DONE** — pushed at `3108554`, tree is green.
2. Migrate `Org`/`Vendor`/`Provider` → `Company`; computed tiers; keep wire shape identical. *(~90 min)*
3. `graph {domain}` — unbounded BFS read.
4. `expand {domain, max_new}` — budget-bounded crawl, replaces the depth cap.
5. `atlas {}` — featured list + per-company headline.
6. Add `domain` to the four existing read walkers, defaulted for back-compat.
7. Delete `Feature`/`Powers`; `features_down` from edge `purpose`.
8. Degrade gracefully: unsourced downtime/compliance → zero/empty, never fabricated.
9. **`seed_atlas` — import committed seed data into the graph (§11).** Without this the
   deployed instance is empty and every redeploy wipes the atlas. Non-optional.
10. ~~`search {q}` walker~~ **LANDED.** Canonical resolution ladder (§5.1), the inbound
   `dependents` view, and `map_company` are all wired and reachable from the search box.
11. *(post-MVP)* `industry_map` endpoint for §10.
12. *(post-MVP)* `root.shared` migration — `DECISIONS-A.md` §4.

### B — data, fetching, search *(that is the whole lane now)*
1. **Fix `extract.jac:261` + the byLLM import/install.** Blocking. *(25 min)*
2. **Batch precompute the atlas:** crawl all 150 registry companies, extract, canonicalize,
   persist. Concurrency ~10. This is the single highest-value task left — it's what turns
   the pivot into a demo.
3. **Search backend.** Resolve a typed string → company, over crawled companies *and*
   uncrawled registry entries, so search can offer "not mapped yet — map it now". A exposes
   the `search` walker; B owns the matching/ranking behind it.
4. Add `openrouter.ai` and `lindy.ai` to the registry.
5. **Curate provider facts *with a source URL per claim*** (SOC 2 status, real outage hours
   from public status-page history) for the top ~15 providers. **If it isn't cited by
   freeze, we ship the field empty** — see §2.
6. Keep the ReAct/browser discovery path off the rehearsed run.
7. **The 20-company real-data run — §12.** Highest-value data task.

### C — frontend → deploy *(that is the whole lane now)*
1. **Deploy the moment A's fix lands.** Before the restyle, before the atlas. Non-negotiable.
2. Verify `jac.toml`: `jac-version = "==0.34.7"` but the installed toolchain is **0.16.7**.
   Confirm this pin doesn't break `jac start`/`--scale`.
3. **Restyle everything to the Swiss-editorial design system — §9.**
4. **Replace the tier-pinned graph with the free-form render — §9.3.**
5. Atlas landing: featured graphs, rotating headline, company selector, search box.
6. Pass `domain` through every walker call.
7. **Update `docs/demo-script.md`:** remove the 9.2h AWS claim and the Fastly SOC 2 /
   watchlist claim unless B lands cited replacements. Re-point the script at the atlas.
8. ⚠️ **`max_replicas = 4` with no Mongo configured is a data-splitting bug.** `jac.toml`
   has `[scale.kubernetes]` but no `[plugins.scale.database]`, so each replica gets its own
   SQLite and users see different graphs depending on which pod they hit. **Either set
   `max_replicas = 1` for the demo, or configure `MONGODB_URI` + `REDIS_URL`.** For today,
   pin to 1 — it is one line and it cannot fail on stage.
9. `min_replicas = 1` is already set — good, no cold start.
10. *(post-MVP)* Build the Map view — §10.
11. **Render the inbound view for `known` companies (§5.1).** When `search` resolves to a
    `known` company, call `dependents {domain}` and draw it on the **same force canvas** as
    the forward graph — only with arrows pointing **into** the centre. One canvas, two
    directions.

---

## 7. Sequencing

| When | Gate |
|---|---|
| **now** | A pushes the `[0]` fix → tree is green |
| **+15 min** | **C deploys.** Whatever is green. |
| +30 min | B: extract fix + byLLM installed → live crawl possible |
| +90 min | A: `Company` model + `graph`/`atlas`/`expand` landed |
| +2 hr | B: 150-company precompute run completes → atlas is real |
| **−3 hr** | Feature freeze. Whatever isn't merged is cut. |
| −2 hr / −1 hr | Rehearsal 1 and 2 **on the deployed URL** |

**Cut order under pressure** (delete from the bottom, simultaneously): defense adapter →
`root.shared` migration → diff monitor → compliance panel → risk memo. **Never cut the
rehearsals.**

---

## 8. Definition of done, and what is still open

### Done = all of this is true

1. `jac check` clean on every `.jac` file; `jac start` boots.
2. A public JacHammer URL serves the app.
3. That deployed instance has a **non-empty atlas** — ≥20 real companies imported from
   committed seed data (§11), surviving a redeploy.
4. Landing page: Swiss-editorial styling, rotating headline, company selector, free-form
   graph. No company name hardcoded in static copy.
5. Selecting a company drives graph + chokepoints + blast radius + one-look off that
   company's real data.
6. Every number on screen traces to a `source_url`, or is not shown.
7. `docs/demo-script.md` matches what the deployed app actually does.
8. Two rehearsals completed **on the deployed URL**.

If 1–8 hold we are deployed, honest, and iterating on a real MVP. The Map (§10),
`root.shared`, auth, the diff monitor, and the defense adapter are all **explicitly outside
this line** and are what we build next.

### Resolved this round

- **The Map** → post-MVP. Build after §0–§9 land. (§10)
- **Subagent play** → §12: 20 companies, one subagent each, headless render, real data into
  committed seed files. Replaces the "crawl 150 automatically" milestone as the *first* data
  target.
- **Persistence** → §11. SQLite now, Mongo+Redis under `--scale`; shared cache is free while
  we stay `:pub`; committed seed data closes the redeploy gap.

### Still open

1. **Featured set for the landing rotation** — I suggest `lindy.ai` (you can vouch for it),
   `anthropic.com`, `openai.com`, `stripe.com`, `vercel.com`, plus `jachammer.ai` for the
   meta beat. Confirm or swap.
2. **Compliance panel** — if B can't source cited SOC 2 / watchlist facts by freeze, ship
   the panel empty or cut it from the UI? **I'd cut it** — an empty panel reads as broken.
3. **Registry breadth past 150** — worth doing only *after* §12 lands. A wider registry with
   nothing crawled adds no demo value.

---

## 9. Frontend direction — Swiss editorial, generalised

**The visual target is `drafts/02-swiss-editorial`.** Take its full design system.
Nothing else in `drafts/` is a style reference any more. The current dark-blue palette in
`risk/DependencyGraph.jac` is replaced wholesale.

### 9.1 Design system — lift verbatim

| Token | Value | Use |
|---|---|---|
| `--paper` | `#F4F1E9` | page background — **light**, not dark |
| `--ink` | `#191813` | type, rules, node strokes, edges |
| `--red` | `#E30613` | **blast radius only.** Never for warnings, errors, or badges. |
| Display | `Archivo Black` | headline, section heads |
| Body | `Archivo` | prose |
| Data/label | `IBM Plex Mono` | figure captions, table data, node labels, all numerics |

Keep the editorial furniture — it is the whole personality: hairline rules, `FIG. N —`
captions, small-caps mono kickers, clause numbering, generous margins, the masthead, and
the end-mark. Keep the memorandum framing.

### 9.2 De-overfit the copy — this is the actual work

The draft hardcodes one company everywhere. **Every string below must become
data-driven or generic.** Static copy names no company, no count, no percentage.

| Draft string | Problem | Fix |
|---|---|---|
| `One of them is carrying 62% of your stack.` | hardcoded stat | bind to selected company; rotate across featured companies on the landing |
| `JACHAMMER.AI` (masthead slug) | one company | selected company, or the product name on the landing |
| `BLAST RADIUS — <X> DOWN → k/8 VENDORS` | hardcoded `8` | `k/{vendor_count}` from the payload |
| `SOC 2 GAP INHERITED (PII VIA FASTLY)` | hardcoded vendor | from `compliance_fallout`, and only if cited (§2) |
| `Move error monitoring and one CDN path off AWS-bound vendors:` | hardcoded remediation | `one_look.biggest_suggestion` |
| `TECHNICAL MEMORANDUM Nº BR-01` | single memo | derive per company, or drop the number |
| `JACKHACKS · JUL 2026`, `PRINTED AT 1440 × 900` | hackathon/demo artifact | drop, or demote to a colophon |
| `FIG. 1 — ORG / VENDORS / PROVIDERS` | already generic | **keep** |
| `Your vendors have vendors.` | already generic | **keep — it is the product line** |

**Rule of thumb:** if a judge selects a different company and a sentence is still true,
it belongs in the markup. If it becomes false, it belongs in the payload.

### 9.3 Graph render — free-form, not columns

`risk/DependencyGraph.jac` currently pins `x` per tier (`TIER_X = {org:0.13, vendor:0.47,
provider:0.85}`) and only solves `y`. That produces the three-column look, and it
structurally cannot render the atlas or the Map — both have no single org and unbounded
depth.

**Replace with a real force layout**, closer to `drafts/12-contagion`:

- **Drop `fx`/tier pinning entirely.** Let charge + link distance resolve both axes.
- **No max depth and no max node count in the renderer.** Depth is a data question now
  (§4), not a layout constraint.
- Node radius `∝ sqrt(inbound_degree)` — shared dependencies read as visibly bigger.
- Curved//bent edges and a slow organic drift (contagion uses a small sinusoidal offset
  per node with a per-node seed). Keeps it alive without animating layout.
- Prune by **degree**, not by tier: fold `inbound_degree < 2` leaves into an `other (N)`
  aggregate. `store.jac` already does this with `PRUNE_ABOVE`; keep it, make the
  threshold a prop.
- Ink-on-paper: `--ink` nodes and hairline edges on `--paper`; **`--red` only during a
  blast**. Everything else desaturates to ~15% opacity when a blast is running.
- `tier` still arrives on every node (§4) — use it for *labelling*, never for position.

### 9.4 Multigraph

One canvas component, three consumers: a single company (Atlas selection), the whole
dataset (Map, §10), and the memo figure (Brief). Same `DependencyGraph`, different
payload and palette prop — the component already accepts `palette`, so keep that seam.

---

## 10. The Map — the industry map *(POST-MVP — build only once §0–§9 are done)*

> **Scope call: this ships after the MVP is deployed and green.** It is the thing we
> iterate toward on top of a working deployment, not a launch requirement. Nothing in
> §0–§9 may slip for it.

**Every company and every disclosed dependency in one canvas.** Not one org's graph — the
whole crawled corpus. This is the payoff of the wideness pivot and it is the single most
arresting thing we can put on a projector: hundreds of real companies, sourced from real
legal filings, visibly collapsing onto a handful of providers.

- Endpoint: `industry_map {min_degree?}` → `{nodes, edges, stats}` over all crawled
  companies. No org root, so `tier` is degree-derived: sinks/hubs vs leaves.
- Sizing by global `inbound_degree`; the hyperscalers become unmissable hubs.
- `min_degree` lets C trade density for legibility at render time.
- Hover a node → its name, dependents count, `source_url`. Click → open that company's
  Atlas view.
- Search (§B3) targets this view: type a company, fly to its node.

**Nav becomes:** `/` **Atlas** (landing + company view) · `/map` **Map** · `/brief`
**Brief**. The current `/console` outage controls fold into the Atlas company view — that
keeps three tabs, which is what `pages/layout.jac` already renders.

**Honesty guard:** the Map shows only what we actually crawled. Put the real count in the
furniture — *"N companies · M disclosed dependencies · sourced from public Article 28
filings"* — and it reads as rigor rather than decoration.

---

## 11. Persistence — where the atlas actually lives

*Answering the question directly: it is **not** CDN JSON. It is a real graph database, and
`jac` provides it with no code from us.*

### What exists today (verified)

| Mode | Backend | Notes |
|---|---|---|
| `jac start` (now) | **SQLite** at `.jac/data/blast-radius.db` | Already real — 94 KB on my box after the smoke runs. Graph + users. Zero setup. |
| `jac start --scale` | **MongoDB + Redis**, auto-provisioned as k8s StatefulSets | Required the moment you have >1 replica. |

Writes persist automatically inside endpoints — no save/commit call. The graph *is* the
database; there is no ORM and no migration step.

### "If two people search the same company, do they share the cache?"

**Today, yes.** All walkers are `walker:pub`, so anonymous callers land on the shared guest
root. Two people searching `stripe.com` hit the same `Company` node, and the second one
pays nothing: `last_crawled` + TTL says it is fresh, and `content_hash` means even a forced
refresh skips extraction if the filing is byte-identical.

**This breaks the moment auth is added.** `walker:priv` gives each user their own root, and
the cache fragments per-user. That is `DECISIONS-A.md` §4 (`root.shared` migration) and it
is why that item exists. For the MVP we stay `:pub` and the sharing is free.

### ⚠️ The gap nobody owned — and it is deploy-fatal

Three facts that combine badly:
1. `.jac/` is **gitignored** — the crawled atlas never travels with the repo.
2. A crawl run on someone's laptop does **not** populate the deployed instance.
3. `jac destroy` **deletes the persistent volumes**, and any redeploy starts empty.

So "B precomputes 150 companies" and "C deploys" produce a **deployed app with an empty
atlas**, and neither lane is wrong — the handoff between them was simply never specified.

**Fix — committed seed data:**

```
seed/atlas/<domain>.json     # {domain, name, subprocessor_url, fetched_at,
                             #  raw_text_sha, subprocessors:[{name, purpose, region}]}
```

- Checked into git, so it survives every redeploy and every fresh clone.
- `seed_atlas` walker (A, lane item 9) imports the directory into the graph, idempotently,
  keyed by `domain`. Safe to re-run.
- Called once after deploy, or from a boot hook.
- The rehearsed demo therefore **never touches the network**, which is what spec §10 of the
  original build spec demanded anyway.
- Live crawling still works on top for anything a judge types — it just writes into the
  same graph.

This also makes the data reviewable: a real filing snapshot in a PR, not a number someone
typed into a fixture.

---

## 12. The 20-company real-data run *(the subagent play)*

Replaces "crawl 150 automatically" as the **first** data milestone — 20 verified companies
beat 150 half-parsed ones, and this produces the seed corpus §11 needs.

**Shape:** one subagent per company, run locally, in parallel.

- **Input:** company domain + its `subprocessor_url` from `registry.jac` when present.
- **Tools:** browser-harness / headless render — necessary because Vanta and SafeBase trust
  centers are client-rendered and return an empty shell to a plain GET. This is the exact
  failure mode called out in the original spec §4.3.
- **Output, per company:** `seed/atlas/<domain>.json` in the §11 shape, **plus** the raw
  extracted filing text as a fixture.
- **Non-goal:** subagents do not touch the graph and do not invent data. If a filing cannot
  be found or rendered, the row is marked `crawl_status: "unreadable"` and shipped as such.
  A visible coverage gap is fine; a fabricated row is not (§2).

**Why raw text as well as the parsed list:** it lets B's real `extract_and_resolve` run over
it afterwards, which both proves our own pipeline works and gives us a cross-check. If the
subagent's list and our extractor's list disagree, that is a bug worth knowing about before
stage.

**Company set (20):** the 8 current demo vendors, plus `lindy.ai` and the highest-recognition
registry entries — Notion, Slack, Figma, Linear, Twilio, Snowflake, Cloudflare, Auth0/Okta,
HubSpot, Intercom, Segment, Zoom. Recognition matters more than coverage here: a judge should
know every name on the landing rotation.

**Sequencing:** run this *concurrently* with C's deploy and restyle. It is pure data
gathering and blocks nothing, but nothing downstream is real until it lands.
