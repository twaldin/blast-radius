# Demo-readiness triage — frontend (Tim), next hour
Baseline: deployed `main` @ `d6e89e8`. All items are atomic (one commit each, no cross-file rewrites). GraphCircuit agent keeps iterating on the ring renderer in parallel; we swap it in ONLY if its final screenshots beat the current graph. Nothing below depends on it.
## {==KILL now (10 min total)==}{>>empty?<<}{id="c1" by="user" at="2026-07-27T01:18:33.260Z"}
| # | What | Why | Scope |
|---|---|---|---|
| K1 | **Region chips row** on Atlas | Looks bad, half-baked, adds nothing to the pitch. Backend `region_codes`/`regions` payload fields stay (additive, David may use later) — only the UI dies. | `pages/atlas.jac` chips block + `.regs/.reg-chip` css. Store `setRegion` stays but unused. |
| K2 | **Vendor × provider matrix** (panel 03) | With deep BFS graphs (128 nodes for Okta) providers get folded to `__other` and the matrix is a sea of empty cells — reads broken. Not fixable small: needs provider capping + column headers redesign. | Delete panel 03 from `pages/atlas.jac`; renumber panels. (If you'd rather cap it to top-8 providers × direct vendors instead of killing, say so — that's ~30 min, not 10.) |
## {==FIX now (atomic, ~45 min total)==}{>>empty?<<}{id="c1" by="user" at="2026-07-27T01:18:33.260Z"}
| # | What | Change | Files |
|---|---|---|---|
| F1 | **Crawl coverage "117 PENDING"** | Reframe honestly: bar counts only ATTEMPTED filings (ok+unreadable+notfound); pending leafs become a muted footnote: "117 discovered sub-processors not yet crawled". Percent = read/attempted. Headline number becomes "11 filings read". | `pages/atlas.jac` panel 02 only (display math; no walker change) |
| F2 | **Stack metrics tiles** | Replace the two dead tiles (`EXPOSURE 0`, `DOWNTIME —` when uncited) with always-real figures: `DIRECT VENDORS`, `TOTAL REACH` (node count), keep `STACK SHARE %`, keep `PROVIDERS`. Downtime/exposure only render when cited (rare) — stop reserving tiles for them. | `pages/atlas.jac` panel 01 |
| F3 | **One-look / Recommendation header** | Keep — it IS derived from real chokepoint data (`_one_look_for`), not fixture. Cosmetic only: when share < 10% soften the copy ("no dominant chokepoint — concentration is healthy") so a 2% headline doesn't oversell. LLM-generated one-look = backend, David's call, not this hour. | `pages/atlas.jac` header strip |
## {==ADD — the one feature worth the hour (flagship)==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
{==**F4 — Live graph build ("watch it walk").** For deep-BFS crawls (search miss → discovery, or any company with pending leaves):==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}

1. {==Draw immediately everything `graph {domain}` already knows (crawled + placeholder nodes).==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
  
2. {==Kick `expand {domain}` in the background (NOT awaited — no loading wall, no spinner page).==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
  
3. {==Poll every ~1.5s: `crawl_progress {domain}` (drives a progress rail: `walking… 14/40 filings · 0:23`) + re-fetch `graph {domain}` and merge — new squares appear as they're discovered, uncrawled nodes render hollow/dashed until their filing is read.==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
  
4. {==Stop when pending stops moving or expand returns. Timer + per-company status list in a side rail replaces the current all-or-nothing loading state.==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
  

{==Files: `risk/store.jac` (background expand + poll merge loop, ~40 lines), graph renderer (hollow-square style for `crawl_status == "pending"` — 1 CSS class + 1 conditional), `pages/atlas.jac` (progress rail markup). No backend change required — walkers all exist. RISK: `expand` live-crawl stability is David's lane (it wedged the dev server once when a request was aborted mid-crawl); I'll coordinate before wiring the trigger, and the demo path for SEEDED companies never triggers it (they're fully cached — instant draw, no poll).==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
## {==KEEP as-is==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
- {==David's search strip + discovery button (works, his lane).==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
  
- {==Landing (real atlas index), Brief (cuttable per WORKSPLIT §7 but harmless), chokepoint rank (share-ranked, cited-gated), coverage provenance "filing ↗" link.==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
  
- {==Current graph renderer until GraphCircuit's ring beats it on screenshots.==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
  
## {==Order==}{>>lets just go no point wasting process cycles on this<<}{id="c2" by="user" at="2026-07-27T01:18:39.473Z"}
K1 → K2 → F1 → F2 → F3 (one push, ~1 commit each) → F4 (rest of the hour) → re-smoke both routes in browser → push → Snehil redeploys.
