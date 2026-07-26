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

## 0. BLOCKING — the tree does not boot. Fix before anything else.

Three independent breakages. Nobody can `jac start` right now.

| # | Where | Error | Owner | Est |
|---|---|---|---|---|
| 1 | `main.jac` ×5 | `E1002`/`E1001` — `++>` returns a **list**; the `[0]` was removed | **A** | 10 min |
| 2 | `extract.jac:261` | `E1054` — lambda sort key overload | **B** | 10 min |
| 3 | `extract.jac:6` | `No module named 'jaclang.byllm'` — byLLM not installed in the jac tool env, and the import path is likely `byllm.lib`, not `jaclang.byllm.lib` | **B** | 15 min |

> #1 is a real 0.16.7 gotcha, already in the team gotcha list: **`++>` returns a LIST — index `[0]`.**
> #3 is the known packaging hole: byLLM must be installed into `.jac/venv` (or on `PYTHONPATH`).

**A fixes #1 immediately and pushes, so C can deploy while the rest of this lands.**

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
| `search` | `{q}` | **NEW.** Type-ahead over crawled companies **and** uncrawled registry entries. |

**Dropped:** `expansion_candidates` (the depth-cap justifier — obsolete once depth is
uncapped), `detect_vendors`/`add_vendors` fold into a single `seed {domain, vendors[]}`.

---

## 6. Lanes

### A — graph, traversal, contract *(me)*
1. **Fix the 5 `[0]` errors, push immediately.** Unblocks C's deploy. *(10 min)*
2. Migrate `Org`/`Vendor`/`Provider` → `Company`; computed tiers; keep wire shape identical. *(~90 min)*
3. `graph {domain}` — unbounded BFS read.
4. `expand {domain, max_new}` — budget-bounded crawl, replaces the depth cap.
5. `atlas {}` — featured list + per-company headline.
6. Add `domain` to the four existing read walkers, defaulted for back-compat.
7. Delete `Feature`/`Powers`; `features_down` from edge `purpose`.
8. Degrade gracefully: unsourced downtime/compliance → zero/empty, never fabricated.
9. *(if time)* Vendor/Provider subgraph onto `root.shared` — `DECISIONS-A.md` §4.

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
7. *(subagent play)* Expand the registry well past 150 — see §8.

### C — frontend → deploy *(that is the whole lane now)*
1. **Deploy the moment A's fix lands.** Before the restyle, before the atlas. Non-negotiable.
2. Verify `jac.toml`: `jac-version = "==0.34.7"` but the installed toolchain is **0.16.7**.
   Confirm this pin doesn't break `jac start`/`--scale`.
3. **Restyle everything to the Swiss-editorial design system — §9.**
4. **Replace the tier-pinned graph with the free-form render — §9.3.**
5. Atlas landing: featured graphs, rotating headline, company selector, search box.
6. **Build the Map view — §10.**
7. Pass `domain` through every walker call.
8. **Update `docs/demo-script.md`:** remove the 9.2h AWS claim and the Fastly SOC 2 /
   watchlist claim unless B lands cited replacements. Re-point the script at the atlas.
9. `min_replicas = 1` is already set — good, no cold start on stage.

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

## 8. Open — needs your call

1. **Registry breadth via subagents.** Parallel subagents, one per vertical, each producing
   verified `{name, domain, subprocessor_url, source_type, verified_on}` rows — the same
   shape as the existing `research/*.json`. That's how the current 150 were built, so the
   pipeline exists. Realistically 8–12 subagents → several hundred more companies inside an
   hour. **Recommend yes, but only after B's precompute is running** — a wider registry with
   nothing crawled adds no demo value.
2. **Your other subagent idea** — you mentioned one but didn't say what it was. What is it?
3. **Featured set** — which companies lead the landing rotation? I'd suggest
   `lindy.ai` (you can vouch), `anthropic.com`, `openai.com`, `stripe.com`, `vercel.com`,
   plus `jachammer.ai` for the meta beat.
4. **Compliance panel** — if B can't source cited SOC 2 / watchlist facts by freeze, do we
   ship the panel empty, or cut it from the UI entirely? I'd cut it from the UI; an empty
   panel reads as broken.

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

## 10. The Map — third view, the industry map

*(New — this had not come up with me before now.)*

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
