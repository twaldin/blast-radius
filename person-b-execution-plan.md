# Person B Execution Plan — Data & Extraction Pipeline

This plan executes Person B's role from `blast-radius-build-spec.md`: turn a domain into clean, canonical, typed records without ever mutating the graph.

## 1. Mission and non-negotiable boundary

Person B owns:

```text
domain
  -> visible-vendor detection
  -> subprocessor-page resolution
  -> browser search when the company is absent from the registry
  -> page fetching and cleanup
  -> typed subprocessor extraction
  -> provider canonicalization
  -> ResolvedSubprocessor records
```

Person B does **not** create, query, or mutate Jac nodes or edges. Person A is the only graph writer. Person B also does not edit `jac.toml`; dependency and capability changes go through Person C.

The minimum successful outcome is:

1. One real vendor URL resolves.
2. Its page is fetched and reduced to usable text.
3. `by llm()` produces typed records.
4. aliases such as `AWS` and `Amazon Web Services, Inc.` converge on `Amazon Web Services`;
5. Person A receives plain `ResolvedSubprocessor` objects and creates a visible chokepoint.

Everything else is secondary until this path works end to end.

## 2. Current repository state and immediate prerequisites

As of July 26, 2026, the repository contains only:

- `blast-radius-build-spec.md`
- `LICENSE`

The `jac` command is not installed on the current machine. Before implementation can be compiled or tested:

1. Install the current Jac binary and record `jac --version` in the team channel.
2. Person C creates and owns `jac.toml`.
3. Person B requests these project dependencies from C:
   - `httpx` for async HTTP;
   - `trafilatura` for main-text extraction;
   - `dnspython` for MX, TXT, and CNAME lookup;
   - `beautifulsoup4` only if script-tag extraction is awkward with the existing HTML tools.
4. Confirm the Browser Use runtime:
   - local development can use the installed `browser-use` CLI;
   - JacHammer needs Browser Use Cloud or another deployed CDP browser because it cannot depend on the developer's local Chrome;
   - C owns the deployment secret/configuration for the remote browser.
5. Configure the current built-in byLLM capability and model through `jac.toml`; do not copy an older plugin configuration blindly.
6. Run `jac install`, `jac check`, and a trivial `jac test` before writing real pipeline logic.

Current Jac documentation says dependencies are declared in `jac.toml` and installed into `.jac/venv` with `jac install`. It also confirms that structured `by llm()` returns are type-validated and that `sem` declarations—not docstrings—supply model instructions.

## 3. Freeze the cross-person contract first

### 3.1 Types to freeze in `types.jac`

Agree on these fields before any real implementation:

```jac
obj DetectedVendor {
    has domain: str;
    has name: str;
    has method: str;       # dns | headers | scripts | disclosure
}

obj SubprocessorRecord {
    has name: str;
    has purpose: str = "";
    has hosting_region: str = "";
}

obj ResolvedSubprocessor {
    has canonical_name: str;
    has purpose: str = "";
    has region: str = "";
    has confidence: float = 1.0;
}

obj BrowserDiscoveryResult {
    has status: str = "notfound";        # found | notfound
    has company_name: str = "";
    has company_domain: str = "";
    has primary_source_url: str = "";
    has source_urls: list[str] = [];
    has subprocessors: list[ResolvedSubprocessor] = [];
}
```

Do not add or rename fields after the +15 minute freeze without telling A and C. In particular, retain `canonical_name`, `region`, and `method`; those names connect B's layer to A's graph and C's payloads.

### 3.2 Exported functions

Use deterministic stubs first, but freeze the production sync/async shape before A imports them:

```jac
async def resolve_url(domain: str) -> str;
async def fetch_page(url: str) -> str;
async def detect_all(domain: str) -> list[DetectedVendor];
async def discover_with_browser(
    company_keyword: str,
    domain: str,
    known: list[str]
) -> BrowserDiscoveryResult;

def extract_and_resolve(
    page_text: str,
    known: list[str]
) -> list[ResolvedSubprocessor];
```

The build spec shows `resolve_url` and `detect_all` as synchronous stubs, but both perform network I/O in production. Make them async from the outset so A does not have to change every caller later. Jac's current type checker treats an un-awaited async call as an error, which helps catch this boundary mistake early.

Return/error rules:

- `resolve_url`: check only the curated and learned registries and return `""` on a miss. A must invoke `discover_with_browser` before mapping the company to `notfound`.
- `fetch_page`: return `""` when a page exists but cannot produce useful text. A maps that to `crawl_status = "unreadable"`.
- `detect_all`: return a deduplicated list; one vendor should appear once even if several signals identify it.
- `discover_with_browser`: search only when the normalized company/domain is absent from the curated and learned registries. Return `status = "found"` only when an authoritative source yields at least one named subprocessor. Otherwise return `status = "notfound"` with no partial records.
- `extract_and_resolve`: return plain typed objects, never graph objects, and return `[]` for empty/unusable text.
- Expected network failures are contained and logged; they do not crash the entire expansion.

### 3.3 Minute-15 handoff

Before real logic, give A hardcoded implementations returning:

- one known subprocessor URL;
- one sample page body;
- five detected vendors;
- three canonicalized provider records, including two raw AWS variants that resolve to the same canonical name.
- one fixed `BrowserDiscoveryResult` containing the new company and three unique subprocessors.

Acceptance: A can import B's module, call every export, and create graph records without waiting for B again.

## 4. Recommended file layout

Person B owns:

```text
extract.jac                    # fetch, cleanup, LLM extraction, resolution
registry.jac                   # curated + learned registry, aliases, anchors
browser_discovery.jac          # bounded Browser Use search and source validation
browser_worker.py              # fixed Browser Use/CDP task invoked by the adapter
tests/
  registry_test.jac
  fetch_test.jac
  detection_test.jac
  extraction_test.jac
  browser_discovery_test.jac
  fixtures/
    stripe_subprocessors.html
    notion_subprocessors.html
    scripts_and_headers.html
cache/
  demo_manifest.json           # if the team agrees to check in warmed results
```

Keep pure helpers separate inside the two owned modules:

- domain and URL normalization;
- header-to-vendor mapping;
- script-host-to-vendor mapping;
- DNS-answer-to-vendor mapping;
- legal-suffix cleanup and alias lookup;
- record deduplication.

Pure helpers make most behavior testable without network calls or LLM cost.

`browser_discovery.jac` is also B-owned. It may call the Browser Use worker and return typed data, but it must not import graph types or create nodes.

## 5. Execution order

### Phase 0 — Compile the real module boundary (0:00–0:15)

1. Confirm `main.jac` can import B's stub and `app.jac` still compiles.
2. Freeze `types.jac`.
3. Decide and document the async signatures above.
4. Give A sample outputs.
5. Ask C for the dependency and byLLM configuration.

Exit criterion: the three-file skeleton compiles and A can consume B's fixed records.

### Phase 1 — Build canonicalization anchors before calling the LLM (0:15–0:40)

Create two constants in `registry.jac`:

1. `KNOWN_PROVIDERS`: at least 20 canonical target names.
2. `PROVIDER_ALIASES`: normalized raw aliases mapped to those targets.

The initial anchors should cover at least:

- Amazon Web Services
- Google Cloud
- Microsoft Azure
- Cloudflare
- Fastly
- Akamai
- Twilio
- SendGrid
- Snowflake
- Datadog
- MongoDB Atlas
- Auth0
- Okta
- GitHub
- Salesforce
- Atlassian
- Sentry
- Segment
- OpenAI
- Zendesk

Normalization should be conservative:

1. trim whitespace and punctuation;
2. case-fold;
3. remove only well-understood legal suffixes such as `Inc.`, `LLC`, `Ltd.`, `GmbH`, and `SARL`;
4. check the exact alias table;
5. use the LLM only when deterministic lookup cannot decide.

Do not use aggressive substring matching: it can incorrectly merge unrelated companies.

Exit criterion: unit tests prove that the common AWS, GCP, and Azure variants converge without an LLM call.

### Phase 2 — Make one vendor work end to end (0:40–2:00)

Use one stable, server-rendered page—Stripe is the spec's suggested stub—to implement the entire happy path.

#### `fetch_page`

Implement:

- shared `httpx.AsyncClient`;
- realistic Blast Radius user agent;
- redirects enabled;
- five-second connect/read timeout;
- concurrency semaphore of 10;
- HTML/text content-type guard;
- reasonable response-size limit;
- `trafilatura.extract`;
- a conservative visible-text fallback when Trafilatura returns empty;
- in-memory caching by normalized final URL.

Internally capture diagnostic status such as HTTP code, final URL, elapsed time, and failure class. Keep the public return type as `str` to preserve A's contract.

#### `extract_subprocessors`

Define the typed object and attach semantics at the function, parameter, return, object, and field levels. The semantics must say:

- emit one record per named third-party subprocessor;
- ignore the vendor's own legal entities;
- ignore examples and boilerplate;
- preserve stated purpose and region;
- use empty strings rather than inventing missing values.

Limit the submitted text to the relevant page content and a bounded size so navigation text and very large DPAs do not dominate token use.

#### `canonicalize`

Implement the load-bearing meaning-typed call with these stages:

1. normalized exact canonical-name match;
2. deterministic alias match;
3. cached prior LLM resolution;
4. LLM match against `known + KNOWN_PROVIDERS`;
5. cleaned new canonical name if no known target fits.

Use confidence consistently:

- `1.0`: deterministic canonical or alias match;
- `0.9`: LLM result exactly matches a known anchor;
- `0.65`: cleaned new provider not present in the known list.

#### `extract_and_resolve`

This orchestration function:

1. rejects empty text;
2. calls typed extraction;
3. canonicalizes each raw name;
4. deduplicates by `canonical_name`;
5. merges non-empty purpose/region values;
6. returns a stable, deterministic order;
7. never imports or references graph types.

Cache raw-name resolutions so repeated names across vendors do not trigger repeated LLM calls. If latency is still too high, batch only the unresolved raw names behind an internal typed LLM call while preserving the exported contract.

Exit criterion at +2 hours: one real page produces canonical typed records that A renders in the UI. At least one expected major provider must appear.

### Phase 3 — Build the registry in value order (2:00–3:30)

Do not start by generating 150 unverified rows. Build three tiers:

1. **Demo tier:** the exact 12–15 vendors used in the scripted demo.
2. **Room tier:** the 40–50 most likely startup vendors.
3. **Coverage tier:** expand to approximately 150.

Each registry entry should include:

- normalized vendor domain;
- display name;
- exact subprocessor URL;
- optional aliases for acquired or alternate domains.

Validation script/test:

- domains are unique after normalization;
- URLs are HTTPS unless there is a documented exception;
- no placeholder or empty URLs;
- each demo-tier URL returns a successful response;
- extracted text is non-trivial and contains subprocessor/DPA language;
- redirects are updated to the stable final URL where practical.

Manually spot-check all demo-tier entries and a sample of every generated batch. A 40-entry verified registry is more valuable for the demo than 150 plausible but broken URLs.

Exit criterion: every scripted vendor resolves from the local registry with zero discovery requests.

### Phase 4 — Implement Browser Use registry fallback (3:30–5:00)

This replaces sitemap probing, trust-subdomain guessing, and path guessing as the fallback.

#### Trigger

1. Normalize the company keyword and domain.
2. Check the curated registry.
3. Check the learned registry/cache.
4. Only on a complete miss, call `discover_with_browser`.

The fallback receives both the user-entered company keyword and the detected domain when available. A name alone is acceptable, but a domain is stronger identity evidence.

#### Browser search plan

Give the Browser Use worker a fixed, read-only task. It may search and navigate but may not log in, submit forms, download files, or perform writes.

Keep the Jac-facing adapter independent of the browser host:

- in development, it invokes the installed `browser-use` CLI against local Chrome;
- in JacHammer, it invokes the same fixed worker against a named Browser Use Cloud/CDP session;
- if the CLI cannot be packaged with the Jac deployment, run the worker as a small remote service and keep `discover_with_browser`'s typed contract unchanged.

Complete a deployed smoke test before depending on this fallback in the demo. A local-only browser integration does not count as complete.

Run a bounded query set:

1. `"<company>" subprocessors`
2. `"<company>" "sub-processors" OR "data processing addendum"`
3. `site:<company-domain> subprocessors OR sub-processors OR DPA`
4. `site:github.com "<company>" subprocessors OR sub-processors OR DPA`

Inspect at most five search results per query and at most eight candidate pages overall. Stop early once authoritative sources have been exhausted. Give the whole fallback a fixed time/page budget so a difficult company cannot hold the crawl open indefinitely.

#### Authoritative-source rules

Accept:

- the company's official legal, privacy, trust, security, or DPA page;
- an official GitHub organization/repository containing a subprocessor list or DPA;
- a rendered trust-center page whose company/domain identity is clear.

Reject:

- search-result snippets as evidence;
- SEO pages, aggregators, vendor directories, or AI summaries;
- unrelated GitHub forks, user gists, or repositories whose ownership cannot be tied to the company;
- a page that mentions subprocessors but names none;
- login-gated or ambiguous content.

Use third-party search results only to locate a first-party source. For GitHub, accept the repository only when its organization is linked by the official company site, is a verified organization for that domain, or otherwise has strong identity evidence.

#### Extraction and merging

For each accepted page:

1. wait for the rendered page to load;
2. collect the visible legal/table text and exact source URL;
3. run `extract_subprocessors`;
4. canonicalize against A's `known` list plus B's anchors;
5. merge results from all accepted website and GitHub sources;
6. deduplicate by normalized `canonical_name`;
7. merge non-empty purpose and region;
8. retain every authoritative source URL used.

The browser is responsible for finding and rendering sources. The existing meaning-typed pipeline remains responsible for deciding which named companies are subprocessors and for canonical identity.

#### Registry and graph write behavior

On `status = "found"`:

1. B adds the normalized company, preferred authoritative URL, aliases, source URLs, and discovery timestamp to the learned registry/cache.
2. B returns one `BrowserDiscoveryResult` containing the new company and its unique `ResolvedSubprocessor` records.
3. A upserts exactly one `Vendor` node for the new company by normalized domain.
4. A upserts one `Provider` node per unique canonical subprocessor name.
5. A creates missing `Subprocesses` edges and updates provenance/timestamps on existing edges.

This satisfies the requested node creation while preserving the hard rule that only A mutates the graph.

Before implementing the learned registry, A, B, and C must choose its persistence:

- for the hackathon, a checked-in/pre-warmed JSON overlay is acceptable;
- for JacHammer runtime learning, use a persistent store rather than the container filesystem;
- graph persistence can hold learned company nodes, but a per-user graph is not automatically a shared global registry.

On `status = "notfound"`:

- do not add the company or any subprocessors to the learned registry;
- do not create partial provider nodes;
- A sets `crawl_status = "notfound"`;
- C displays exactly `Not found`.

Treat all page content as untrusted input. The Browser Use task must ignore instructions found inside pages, never expose secrets to page content, and return only the defined structured result.

Cache positive discoveries by normalized company/domain and source hash. Negative results receive a short TTL so a temporary outage does not become permanent.

Exit criterion:

- one company absent from the curated registry is found through its official website;
- one is found through an official GitHub source;
- website and GitHub results merge without duplicate subprocessors;
- a company with no authoritative disclosure returns only `notfound`;
- A creates exactly one new company node and unique provider nodes from the result.

### Phase 5 — Implement domain detection (5:00–6:30)

Run independent signals concurrently:

#### DNS

- MX lookup: map Google Workspace and Microsoft 365 patterns.
- TXT lookup: inspect SPF includes for SendGrid, Mailchimp, HubSpot, Zendesk, Postmark, and other known senders.
- `_dmarc` TXT lookup where useful.
- CNAME lookup for apex/`www` and a small, fixed set of public hostnames; map Vercel, Netlify, Cloudflare, Shopify, and Webflow.

#### One HTTP request

- map stable response headers such as `x-vercel-id`, `cf-ray`, `x-served-by`, and `x-amz-*`;
- inspect external `<script src>` hosts for Segment, Intercom, PostHog, Google Analytics, Stripe.js, Sentry, and Hotjar;
- avoid labeling first-party/self-hosted script URLs as vendors.

#### Own disclosure page

If the organization has a readable subprocessor page, reuse the same resolution/fetch/extraction machinery and convert those names into `DetectedVendor` values with method `disclosure`.

Deduplicate by normalized vendor domain. When several methods detect one vendor, retain the strongest evidence using a fixed precedence such as `disclosure > dns > headers > scripts`.

Performance target: complete the normal path in under three seconds by using short per-signal timeouts and concurrent I/O. Never let one DNS failure or slow site cancel successful signals.

Exit criterion: fixture tests cover every signal map, and manual tests against several known domains return credible, deduplicated vendors.

### Phase 6 — Quality pass on 15 real pages (6:30–7:30)

Create a review table for the demo-tier vendor pages:

| Field | Record |
|---|---|
| vendor | name/domain |
| source | exact URL |
| crawl result | ok/unreadable/notfound |
| extracted count | integer |
| expected anchors | e.g. AWS, GCP, Cloudflare |
| bad inclusions | vendor subsidiaries/examples |
| aliases resolved | count |
| elapsed time | fetch + LLM |
| cached replay | pass/fail |

For each page:

1. compare extracted names with the visible legal disclosure;
2. identify missing major providers;
3. identify false positives;
4. inspect canonical convergence;
5. refine `sem` declarations or deterministic aliases;
6. re-run the whole set after every prompt change.

Quality gate:

- all readable demo pages return at least one plausible record;
- no obvious vendor-owned legal entities remain;
- every AWS/GCP/Azure variant in the set converges;
- extraction failures are isolated per vendor;
- the team can point from every result to its source URL.

### Phase 7 — Pre-warm and prove offline replay (before feature freeze)

The scripted demo must not depend on live crawling or live extraction.

Build a persistent cache manifest keyed by:

- normalized final URL;
- a cache/schema version;
- content hash;
- extraction-semantic version;
- canonicalization-anchor version.

Store:

- cleaned page text, or an approved bounded fixture;
- resolved records;
- source URL;
- learned Browser Use registry entries;
- fetched timestamp;
- crawl status.

Pre-warm every scripted vendor. Then deliberately disable or break network access and run the rehearsed path from a clean process. It passes only if the same graph data appears without making an HTTP or LLM request.

Do not claim that an in-memory cache is pre-warming; it disappears on restart and is insufficient for a stage demo.

Exit criterion: a cold app process can replay the complete scripted dataset from persistent cache.

## 6. Test plan

Run `jac check` continuously and `jac test -d tests/` at every checkpoint.

### Deterministic unit tests

- normalize domains, URLs, legal suffixes, and provider names;
- validate registry uniqueness and required fields;
- resolve known vendor from registry without HTTP;
- trigger Browser Use only for a complete curated/learned registry miss;
- accept official-company and verified-GitHub sources;
- reject snippets, aggregators, unrelated GitHub repositories, and login-gated pages;
- merge website and GitHub records without duplicate companies;
- return only `notfound` when no authoritative source names a subprocessor;
- reject wrong content type, empty shell, error response, timeout, and oversized response;
- parse every supported header, script host, MX, SPF, and CNAME signal;
- deduplicate multi-signal vendor detections;
- merge duplicate resolved subprocessors;
- confirm B's modules contain no graph node/edge creation.

### LLM tests

Use Jac's `MockLLM` support so tests are deterministic and cost-free:

- valid structured extraction;
- malformed structured output followed by typed-output retry;
- vendor-owned legal entity exclusion;
- known alias resolution;
- unknown cleaned provider;
- empty input;
- duplicate records.

### Live integration tests

Keep live-network tests separate from the default fast suite. Run them manually for the 15-page quality pass and cache warm. Record failures rather than letting a transient 403 obscure deterministic regressions.

### Cross-layer contract test

With A:

1. `await resolve_url`;
2. on a registry miss, `await discover_with_browser`;
3. if found, upsert the new company and its unique providers;
4. otherwise display `Not found` and stop;
5. for a registry hit, `await fetch_page` and call `extract_and_resolve`;
6. create provider nodes from returned strings;
7. run chokepoints;
8. verify a canonical provider has the expected inbound vendor edges.

This is the +2 hour alarm and the most important test in the project.

## 7. Handoffs and communication

### To Person A

Provide:

- exact import paths and async signatures;
- frozen type definitions;
- return/error semantics;
- three sample payloads;
- demo cache lookup behavior;
- known status mapping: no URL = `notfound`, no text = `unreadable`;
- a warning before any semantic or field change.

Person A must pass the graph's existing provider names into `extract_and_resolve`; B combines them with the seed anchors.

### To Person C

Request:

- dependencies in `jac.toml`;
- byLLM model/capability setup;
- safe environment-variable handling for the model key;
- a decision on whether the warmed cache is checked in or attached at deploy time.

Provide C with:

- detection and crawl progress labels;
- coverage status definitions;
- source URL and timestamp for display;
- `Searching official website and GitHub…` and `Not found` states;
- expected demo latency for cached and live paths.

### Commit discipline

- Commit approximately every 20 minutes.
- Touch only B-owned implementation/tests/fixtures.
- Pull with rebase before pushing.
- Do not run a repository-wide formatter.
- Announce contract changes before committing them.

## 8. Time-pressure cuts

Cut in this order:

1. defense/DOD adapter;
2. registry entries beyond the verified room tier;
3. own-disclosure detection;
4. lower-value DNS/script signatures;
5. searching both official web and GitHub sources—retain at least the official-site Browser Use fallback.

Never cut:

- anchor providers and alias mapping;
- one real extraction path;
- typed extraction and canonicalization;
- the demo-tier registry;
- persistent cache pre-warm;
- the 15-page quality pass;
- the +2 hour end-to-end integration;
- rehearsals.

If only a few hours remain, ship 12–15 verified vendors with perfect cached convergence instead of 150 questionable registry entries.

## 9. Definition of done

Person B is done when:

- [ ] The real multi-file project compiles.
- [ ] `types.jac` and async exports are frozen and consumed by A.
- [ ] B's files contain no graph mutation.
- [ ] The demo-tier registry is hand-verified.
- [ ] The registry resolves scripted vendors without network access.
- [ ] A registry miss invokes Browser Use exactly once per uncached company.
- [ ] Browser Use accepts only authoritative company-site or verified-GitHub evidence.
- [ ] Website and GitHub findings merge into unique canonical subprocessors.
- [ ] A upserts one new Vendor and unique Provider nodes from a found result.
- [ ] No authoritative result produces only `Not found` and no partial nodes.
- [ ] Fetching uses a real user agent, five-second timeout, redirects, a global concurrency limit of 10, and caching.
- [ ] Typed extraction uses explicit `sem` declarations and handles malformed output.
- [ ] anchors and aliases converge AWS/GCP/Azure variants.
- [ ] `extract_and_resolve` returns deduplicated `ResolvedSubprocessor` values.
- [ ] Domain detection covers DNS, HTTP headers, and script tags.
- [ ] Fifteen real pages have recorded quality results.
- [ ] The persistent demo cache replays from a clean process with network/LLM disabled.
- [ ] A's real walker produces at least one visible chokepoint from B's records.
- [ ] Expected failures surface as `ok`, `unreadable`, or `notfound` rather than crashing.
- [ ] Person B can answer the meaning-typed/data Q&A without notes.

## 10. Person B's Q&A brief

Prepare these four answers:

1. **Why `by llm()` instead of a parser?** The legal pages use incompatible table and prose layouts. The typed return signature makes layout variance an extraction problem while preserving a strict application contract.
2. **Why is canonicalization load-bearing?** Without it, AWS legal entities and aliases become separate low-degree providers, so the concentration signal disappears.
3. **Where does the data come from?** The vendor's own public legal disclosure. Every result retains source URL and observation time, and unreadable coverage is reported honestly.
4. **How is this different from BuiltWith?** BuiltWith detects first-layer technology on the target site. This pipeline then follows legal disclosures into the second layer and resolves shared providers across vendors.
5. **What happens for a company outside the registry?** A bounded Browser Use worker searches the company's official site and verified GitHub sources, extracts typed subprocessor records, merges canonical duplicates, and teaches the learned registry. With no authoritative result, it returns only `Not found`.

Pitch sentence:

> "The extractor returns a typed legal record, and the resolver maps legal aliases onto one provider identity; without that meaning-typed step, the graph never converges and there is no chokepoint to find."

## References checked

- [Jac byLLM reference](https://docs.jaseci.org/reference/plugins/byllm/)
- [Jac concurrency reference](https://docs.jaseci.org/reference/language/concurrency/)
- [Jac testing reference](https://docs.jaseci.org/reference/testing/)
- [Jac CLI and package-management reference](https://docs.jaseci.org/reference/cli/)
- [Jac import reference](https://docs.jaseci.org/quick-guide/import-anything/)
- [Browser Use harness](https://github.com/browser-use/browser-harness)
