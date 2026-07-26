# Person B Execution Plan — Atlas Seed, Extraction, and Search

This plan implements Person B's lane from `SPEC-V2.md` at fresh-main commit
`b2de4d9`. It replaces the earlier single-organization, live-discovery-first plan.
`SPEC-V2.md` is authoritative wherever older documents disagree.

## Implementation snapshot — July 26, 2026

- The registry contains 152 generated entries: the original 150 plus the
  explicitly required OpenRouter and Lindy records.
- The committed MVP atlas contains 20 seed records, 20 raw replay fixtures,
  19 readable filings, 1 honest unreadable filing, and 394 canonical
  subprocessor records.
- A real project-environment byLLM replay completed all 19 readable fixtures
  with zero call errors. Twelve fixtures were exact identity matches; the
  checked-in report records every missing and unexpected identity for review.
- `scripts/precompute_atlas.jac` is a resumable, failure-isolated, bounded
  concurrency runner for the complete registry.
- Fifteen top-provider SOC claims have first-party citations. Downtime remains
  absent because no equally reproducible incident-period calculation has been
  curated.
- The A-owned `main.jac` integration has an explicit review handoff in
  `docs/person-a-review.md`; human approval remains a merge gate.
- Browser Harness is an offline acquisition tool, not the runtime registry-miss
  fallback. Any future arbitrary-company ReAct path is Firecrawl-only and
  returns `notfound` when authoritative evidence cannot be extracted.

## 1. Mission

Person B turns authoritative public legal disclosures into reviewable, typed,
canonical seed records and deterministic company search results:

```text
registry company
  -> authoritative subprocessor URL
  -> rendered filing text
  -> typed extraction
  -> canonical subprocessors
  -> committed seed/atlas/<domain>.json + raw fixture
  -> A's idempotent seed_atlas importer
  -> persistent Company/Subprocesses graph
  -> C's Atlas UI
```

Person B owns data acquisition, extraction, canonicalization, seed generation,
and matching/ranking. Person B does not create or query graph nodes, implement
walkers, build the UI, or deploy the app.

The MVP objective is no longer “crawl one demo organization deeply.” It is:

> Import at least 20 real, source-backed company graphs into the deployed atlas,
> prove they survive a redeploy, and keep the rehearsed path independent of the
> network and an LLM.

## 2. Fresh-main reality

Observed after pulling `origin/main` to `b2de4d9` on July 26, 2026:

- `jac --version` is `0.34.7`, matching the project pin.
- `jac check extract.jac` passes. The `extract.jac:261` and byLLM import compile
  blockers described in §6/B1 do not reproduce in this environment.
- A real model-backed extraction in the deployment-equivalent environment is
  still unproven. Compile success is not a live byLLM smoke test.
- `jac check main.jac` still reports five A-owned graph connection typing errors
  on fresh main. Do not absorb those into B's lane; full-app green remains an
  external integration gate.
- `registry.jac` contains 150 generated entries. `openrouter.ai` and `lindy.ai`
  are absent.
- There is no committed `seed/atlas/` corpus, no atlas precompute runner, no
  search-ranking backend, and no cited provider-facts dataset.
- The bounded ReAct/browser fallback exists, but it must stay off the rehearsed
  path.

The revised spec resolves the old persistence gap: local `.jac/data` is not a
handoff artifact. B must commit seed data; A imports it into Jac's graph database.

## 3. Scope and ownership

### Person B owns

- `extract.jac`: fetching, typed extraction, canonicalization, deduplication.
- `browser_discovery.jac` and `browser_worker.py`: bounded rendered-page access.
- `research/registry-*.json`: verified registry source records.
- `scripts/build_registry.jac`: registry generation and validation behavior.
- `registry.jac`: generated output only; never hand-edit it.
- `seed/atlas/*.json`: committed, reviewable atlas seed records.
- `seed/raw/*.txt`: raw rendered filing text used as replay fixtures.
- B-owned Jac validation/precompute helpers and their annex tests.
- Pure company-query normalization and ranking behind A's `search {q}` walker.
- Cited provider facts, only after the real seed corpus is working.

### Shared contracts requiring A's agreement

- `contracts.jac` changes.
- The exact seed schema consumed by `seed_atlas`.
- How a disclosed company name resolves to `Company.domain`.
- The plain-value input/output shape for B's search-ranking helper.

### Person B does not own

- `Company` nodes, `Subprocesses` edges, graph persistence, or graph migrations.
- `seed_atlas`, `graph`, `expand`, `atlas`, `search`, or `industry_map` walkers.
- Swiss-editorial UI, force layout, Map view, or deployment.
- `jac.toml` deployment topology. C owns the required one-replica MVP setting.
- Fabricated `demo_data.jac` records. They are not seed input.
- Live vendor detection, the defense adapter, or registry breadth past 150 before
  the MVP seed corpus lands.

## 4. Contracts to freeze before the data run

### 4.1 Committed seed record

One JSON file per company:

```text
seed/atlas/<normalized-domain>.json
seed/atlas/<normalized-domain>.txt
```

The JSON contract is:

```json
{
  "domain": "stripe.com",
  "name": "Stripe",
  "subprocessor_url": "https://stripe.com/legal/service-providers",
  "fetched_at": "2026-07-26T00:00:00Z",
  "raw_text_sha": "<sha256 of the adjacent .txt fixture>",
  "crawl_status": "ok",
  "subprocessors": [
    {
      "name": "Amazon Web Services",
      "purpose": "cloud hosting",
      "region": "United States"
    }
  ]
}
```

Rules:

- `domain` is lowercase, has no scheme, path, port, trailing dot, or `www.`.
- `subprocessor_url` is the authoritative public filing actually read.
- `fetched_at` records observation time; it is not an invented publication date.
- `raw_text_sha` is SHA-256 over the exact committed UTF-8 fixture bytes.
- `crawl_status` is `ok`, `unreadable`, or `notfound`.
- `ok` requires a readable authoritative source and a reviewed parsed result.
- `unreadable` and `notfound` ship honestly with an empty `subprocessors` list.
- Missing purpose or region is `""`; never infer it.
- Records and fields are emitted in deterministic order for reviewable diffs.
- A re-run for unchanged text must produce byte-stable parsed content apart from
  `fetched_at`.

The adjacent `.txt` file is required for every readable source. It provides an
offline replay fixture and makes the JSON auditable. Do not commit an empty or
invented fixture for an unreadable source.

### 4.2 Company identity seam

`SPEC-V2.md` makes normalized domain the canonical `Company` key, while the
current `ResolvedSubprocessor` contract returns only a canonical name. Before the
first seed is finalized, A and B must freeze one of these approaches:

1. B adds a verified optional `domain` to each subprocessor row; or
2. A resolves canonical names through a shared registry identity table during
   `seed_atlas` import.

Preferred rule: carry a domain only when an authoritative or curated mapping
supports it. Never manufacture a domain from a display name. Unresolved names
must remain explicit rather than silently merging unrelated companies.

### 4.3 Extraction contract

The existing boundary remains value-only:

```text
fetch_page(url) -> visible filing text
extract_subprocessors(text) -> list[SubprocessorRecord]
extract_and_resolve(text, known) -> list[ResolvedSubprocessor]
```

Invariants:

- one record per current named third-party processor;
- exclude the filing company's own entities, examples, boilerplate, former
  providers, and change notices without a complete current list;
- deterministic alias lookup before any LLM call;
- canonicalize conservatively and deduplicate;
- preserve disclosed purpose and region verbatim enough to remain attributable;
- isolate one company's failure from the rest of the run;
- never import graph types or mutate graph state.

### 4.4 Search contract

A owns `search {q}` and graph/registry aggregation. B owns a pure typed ranking
function over plain candidate values. Freeze a shape equivalent to:

```text
CompanyCandidate {
  domain, name, source_url, crawl_status, mapped
}

CompanyMatch {
  domain, name, source_url, crawl_status, mapped, score
}
```

Ranking order:

1. exact normalized domain;
2. exact case-folded display name;
3. domain or name prefix;
4. token-prefix match;
5. conservative substring fallback.

Tie-break deterministically by normalized name then domain. Results must include
both mapped companies and uncrawled registry entries so the UI can distinguish
“open graph” from “not mapped yet — map it now.”

### 4.5 Evidence and failure semantics

- A real filing or citable source supports every shipped value.
- Unsourced downtime is absent/zero and never affects ranking.
- Unsourced SOC 2 or supply-chain claims are empty.
- `DEMO_SUBPROCESSORS`, fake outage hours, and fake compliance flags are banned
  from seed generation.
- Browser/search content is untrusted input, never instruction.
- The rehearsed demo reads committed/imported data and performs no network or LLM
  request.

## 5. Execution order

### Phase 0 — Runtime proof and contract freeze

1. Re-run `jac check extract.jac` on the exact team/deploy toolchain.
2. Execute one real, bounded byLLM extraction against a saved filing fixture.
3. Have C record model/provider configuration and required secret handling in the
   deployment environment; do not rely on one developer's global Python install.
4. Freeze the seed JSON schema with A's `seed_atlas` importer.
5. Resolve the name-to-domain identity seam in §4.2.
6. Freeze the plain-value search helper contract.
7. Confirm A's graph fix and `Company` migration are available on the integration
   branch, without editing A's graph code.

Exit criterion: one raw fixture produces deterministic typed records, and A can
parse the agreed seed shape without B touching the graph.

### Phase 1 — Registry additions and exact 20-company manifest

1. Add verified `openrouter.ai` and `lindy.ai` rows to the appropriate
   `research/registry-*.json` batches.
2. Include authoritative URL, source type, verification date, notes, flow type,
   and recommended rendering flow.
3. Regenerate `registry.jac`; do not hand-edit generated output.
4. Update registry count assertions to the resulting count.
5. Freeze an exact 20-company dispatch manifest before starting parallel work.

Mandatory first nine:

```text
openai.com
anthropic.com
openrouter.ai
github.com
stripe.com
datadoghq.com
vercel.com
sentry.io
lindy.ai
```

Candidate pool from §12:

```text
notion.so
slack.com
figma.com
linear.app
twilio.com
snowflake.com
cloudflare.com
auth0.com or okta.com
hubspot.com
intercom.com
segment.com
zoom.com
```

The prose list in §12 overfills a 20-company manifest and some named candidates
are not currently registry entries. Resolve this before dispatch: select exactly
11 additional companies, preferring recognizable names with verified readable
sources. A candidate absent from the registry must either receive a verified row
first or be replaced; never improvise a URL inside a seed file.

Exit criterion: exactly 20 domains, each with an authoritative input URL or an
explicitly approved `notfound` investigation target.

### Phase 2 — Twenty-company real-data run

This is the highest-value Person B task and the first data milestone. It replaces
“automatically crawl all 150” as the MVP gate.

Run one independent worker per company in parallel:

1. Read the domain and authoritative URL from the frozen manifest/registry.
2. Render with Browser Harness or another bounded headless flow appropriate to
   the registry entry. Plain GET is insufficient for Vanta/SafeBase-style trust
   centers.
3. Capture only the visible complete current filing text.
4. Write the raw text fixture.
5. Produce a draft seed JSON record in the agreed schema.
6. On failure, emit `unreadable` or `notfound`; do not invent subprocessors.
7. Do not touch the graph or shared Jac persistence.

Workers must skip project-wide checks; validation happens once after all results
land. Each company is isolated so one failed trust center cannot block the other
19.

Exit criterion: 20 JSON records exist, every readable record has a matching raw
fixture, and every failure is explicit.

### Phase 3 — Run our extractor and finalize the seed corpus

For every readable fixture:

1. Run `extract_and_resolve` against the committed raw text.
2. Compare its result with the worker's independently extracted list.
3. Review disagreements against the visible filing, not against intuition.
4. Fix deterministic aliases or `sem` declarations at the source when the same
   error class appears across companies.
5. Canonicalize and deduplicate the final result.
6. Preserve only source-backed purpose and region values.
7. Recompute and verify `raw_text_sha`.
8. Sort output deterministically and validate the complete directory.

The final JSON should come from the reviewed pipeline output, not from a worker's
unchecked transcription.

Quality gate:

- every `ok` company has at least one plausible current subprocessor;
- no obvious company-owned legal entities or former providers remain;
- common AWS/GCP/Azure variants converge;
- every JSON source URL points to the filing represented by its fixture;
- every hash matches;
- no fabricated demo value appears anywhere in the corpus.

### Phase 4 — Seed importer handoff and deployed proof

1. Give A the complete seed directory and schema validator.
2. A implements `seed_atlas` as an idempotent domain-keyed import.
3. Run the importer twice; the second run must create no duplicate companies or
   edges.
4. C deploys with one replica for the MVP unless shared Mongo/Redis is configured.
5. Invoke `seed_atlas` after deployment or through the agreed boot hook.
6. Confirm the public deployment contains at least 20 real companies.
7. Redeploy and confirm the atlas is restored from committed seed data.
8. Disable network/model access and exercise the featured graphs.

Exit criterion: the public app has a non-empty real atlas after a redeploy, and
the rehearsed path is fully offline.

### Phase 5 — Search matching and ranking

1. Implement query normalization as a pure Jac helper.
2. Rank mapped graph candidates and uncrawled registry candidates using §4.4.
3. Preserve a stable limit and deterministic tie-breaking.
4. Return enough status for “open graph” versus “map it now.”
5. Hand the helper to A's `search {q}` walker without importing graph types.
6. Validate exact domain, exact name, prefix, ambiguous, empty, and no-match
   queries.

Exit criterion: a query can find both a seeded company and an unseeded registry
company, with mapped state and order stable across runs.

### Phase 6 — Scale the proven pipeline toward all registry companies

Only begin after the 20-company corpus is imported into a green deployment.

1. Reuse the same seed schema and validation path.
2. Crawl registry companies with approximately ten concurrent fetches.
3. Keep per-company failures isolated and resumable.
4. Skip fresh, hash-identical fixtures.
5. Commit reviewed batches rather than one opaque 150-file dump.
6. Import each batch idempotently.

The 150-company crawl remains the full lane target, but it is not allowed to delay
the first 20-company deployed MVP. Do not expand the registry past its current
breadth until the existing corpus is actually crawled.

### Phase 7 — Cited provider facts

After real graph degree data exists:

1. Identify roughly the top 15 providers by global inbound degree.
2. Curate SOC 2/attestation status only from a citable primary source.
3. Calculate outage hours only from public status-page incident history with a
   defined period and source URL.
4. Store a source URL and observation period per claim.
5. Leave unsupported fields empty.
6. Tell C to cut the compliance panel if supported facts do not land by freeze.

Do not preserve the fabricated AWS `9.2h` or Fastly SOC 2/watchlist story.

### Phase 8 — Explicitly deferred work

These do not block Person B's MVP:

- live Firecrawl ReAct discovery during the rehearsed run;
- registry expansion past 150;
- the industry Map;
- `root.shared` migration and auth;
- DNS/header/script vendor detection;
- the defense/DoD adapter;
- compliance UI when no cited facts exist.

Browser Harness remains available to the offline acquisition runner. It is not a
registry-miss fallback. A future live, non-rehearsed miss path may use bounded
Firecrawl search/scrape and must return `notfound` when it cannot verify a
complete authoritative disclosure.

## 6. Handoffs

### To Person A

Provide:

- frozen seed schema and exact sample files;
- identity-resolution decision for disclosed company domains;
- status semantics: `ok`, `unreadable`, `notfound`;
- deterministic seed validator;
- the 20-company committed corpus;
- pure search candidate/match types and ranking helper;
- notice before any field or semantic change.

Require from A:

- idempotent `seed_atlas` import keyed by normalized domain;
- no duplicate nodes or edges on re-import;
- `Company`/`Subprocesses` model compatible with the frozen seed fields;
- A-owned `search {q}` walker around B's plain-value matcher.

### To Person C

Request:

- deployment-equivalent byLLM provider/key configuration;
- a one-replica MVP deployment unless Mongo+Redis is intentionally configured;
- a post-deploy or boot invocation of `seed_atlas`;
- no demo-script claim unsupported by committed source evidence.

Provide:

- featured company domains and crawl statuses;
- source URLs and observation timestamps for display;
- mapped/unmapped search semantics;
- expected offline behavior of all rehearsed featured graphs.

## 7. Validation

Run targeted validation at each behavior boundary:

- registry generation rejects duplicate normalized domains, missing URLs, and
  non-authoritative source types;
- seed validation rejects malformed domains, unsupported statuses, missing
  readable fixtures, hash mismatches, duplicate subprocessors, and invented
  non-empty fields without a source;
- extraction tests cover typed output, alias convergence, deduplication, empty
  input, malformed model output, and exclusion of company-owned entities;
- search tests cover exact domain/name, prefix ordering, deterministic ties,
  mapped/unmapped status, empty query, and no result;
- A's importer integration proves idempotence and graph shape;
- deployed smoke proves at least 20 companies survive a redeploy with network and
  LLM access unavailable.

`jac check` and `jac test` validate B-owned Jac changes. A full `jac start` smoke is
the final cross-lane proof, not a substitute for seed and extraction checks.

## 8. Time-pressure cuts

Cut in this order:

1. live ReAct/browser-discovery polish;
2. registry breadth past 150;
3. cited provider facts and therefore the compliance panel;
4. completing all 150 after the first 20 are deployed.

Never cut:

- the exact 20-company seed run;
- raw filing fixtures and matching hashes;
- real typed extraction and conservative canonicalization;
- committed seed data;
- A's idempotent seed import;
- source provenance and honest failure states;
- offline deployed replay;
- rehearsals on the deployed URL.

## 9. Definition of done

### Person B's MVP lane is done when

- [x] A real byLLM extraction is proven in the project-pinned environment.
- [x] `openrouter.ai` and `lindy.ai` are verified registry entries generated from
      research data.
- [x] An exact 20-company manifest is frozen.
- [x] Twenty seed JSON records are committed.
- [x] Every readable record has a committed raw fixture and matching SHA-256.
- [x] Every record is `ok`, `unreadable`, or `notfound` without fabricated data.
- [x] `extract_and_resolve` has been cross-checked against every readable fixture.
- [x] Common provider aliases converge and final records are deduplicated.
- [ ] A imports the corpus idempotently through `seed_atlas`.
- [ ] The public deployment contains at least 20 real companies after a redeploy.
- [x] Featured seed parsing and graph construction work with network and LLM
      access disabled.
- [x] Search ranks both mapped and unmapped companies deterministically.
- [x] No uncited downtime/compliance value is shipped.

### The extended B lane is done when

- [x] The same reviewed pipeline has a complete-registry runner with
      approximately ten-way concurrency.
- [x] Per-company failures are resumable and visible.
- [x] The top provider facts are cited per claim or deliberately absent.
- [ ] Registry breadth grows only after existing entries are mapped.

## 10. Q&A brief

1. **Why committed seed data if Jac already persists the graph?**
   Local `.jac/data` does not travel with the repo or populate a deployment, and a
   destroyed deployment loses its volume. Committed seeds make the atlas
   reproducible; Jac remains the runtime graph database.
2. **Why 20 before 150?**
   Twenty verified, reviewable companies produce a real deployed atlas quickly.
   The exact same pipeline can then scale without betting the MVP on 150 hostile
   page layouts succeeding at once.
3. **Why keep raw text fixtures?**
   They make every parsed row auditable, allow offline extractor replay, and let
   us detect disagreements between independent collection and our byLLM pipeline.
4. **Why `by llm()` instead of one parser?**
   Legal disclosures use incompatible tables, prose, PDFs, and client-rendered
   trust centers. The typed return contract absorbs layout variance without
   weakening the application boundary.
5. **Why is canonicalization load-bearing?**
   If AWS legal aliases become separate companies, inbound degree fragments and
   the chokepoint signal disappears.
6. **What happens when a page cannot be read?**
   It ships as `unreadable` with its attempted authoritative URL and no invented
   subprocessors. Coverage gaps are honest product data.
7. **Why is live discovery off the demo path?**
   The demo must be deterministic. Live discovery remains a bounded product path
   on top of the committed seed-backed atlas.

Pitch sentence:

> “We turn each company's public Article 28 filing into a typed, canonical,
> source-backed seed record; Jac imports those records into one persistent graph,
> so shared providers emerge without fabricated data or a live crawl on stage.”
