# Blast Radius — state of the build

Read against the merged tree at `e4b7caf`, working dir clean except a modified `jac.toml`.

**Verdict: the hard part is done and it is genuinely strong. The demo currently does not show it.**

You have 555 real disclosed dependencies across 293 companies sitting in `seed/atlas/`, and
the frontend renders an 8-vendor fabricated fixture instead. Everything below is downstream
of that one fact.

---

## 1. What is genuinely award-winning here

Not padding — these are the things that separate this from the other projects in the room.

**Real data from real legal filings.** 19 of 20 companies crawled clean: Stripe 40
subprocessors, Okta 89, Figma 54, Intercom 43. With `source_url` and `fetched_at` per row and
raw text snapshots committed alongside the parsed JSON in `seed/raw/`. Most hackathon demos
run on invented fixtures. Yours runs on Article 28 disclosures you can put on screen. That is
the single most defensible thing you have and it is worth leading with.

**The honesty architecture is real, not rhetoric.** `main.jac` gates every risk number behind
`cited = c.risk_source_url != ""`, so uncited downtime returns `0.0` and `compliance_fallout`
returns `[]`. Chokepoints re-rank by `share` instead of `exposure` when nothing is cited. A
judge who probes a number finds a system that refuses to invent one. Very few teams build
this, and the ones who do tend to win the rooms with senior judges in them.

**The atlas pivot is the strongest strategic call in the project.** "Every company in the
registry is already a graph root — we own the atlas, we just haven't crawled it" reframes the
demo from one org's stack to an industry map. It is a better product and a better pitch.

**Walking vs. crawling is a genuinely good architectural distinction.** Unbounded free reads
(`O(V+E)` BFS over one-node-per-company) with the budget on `max_new_companies` instead of a
depth cap. This is the best Jac talking point you have: *reads are free because the graph is
the database — there is no query to optimize, no join, no ORM.* Say exactly that.

**The single `Company` node type** with per-view computed tiers is elegant, kills the
Vendor↔Provider identity duplication, and kept the wire contract byte-identical so the
frontend didn't have to move. That's real engineering judgment.

**Craft signals everywhere.** 12 design drafts with blast-state screenshots, four `.test.jac`
suites, measured latencies (graph 729ms, chokepoints 122ms, search 60ms), a 150-company
registry with audit notes, and `jac.toml` comments that explain *why* each pin exists.

---

## 2. The one thing that is actually wrong

**The frontend never migrated to contract v2, so the real atlas is invisible.**

`risk/store.jac:123-134`:

```jac
graph = await call_walker("expand", {});          # no domain
if len(graph["nodes"] as list) == 0 {
    await call_walker("detect_vendors", {"domain": SEED_DOMAIN});   # <- fabricated
    graph = await call_walker("expand", {});
}
```

A shipped `atlas {}`, `graph {domain}`, `search {q}`, `seed_atlas {}`. The client calls none
of them. It calls `expand {}` with no domain and falls back to `detect_vendors`, which
resolves to `DEMO_VENDORS` in `demo_data.jac` — the eight-vendor jachammer.ai stack that
SPEC-V2 §2 marked **fabricated by A, DELETE**.

So the running app shows invented data while 555 real edges sit unused on disk. This is a
handoff gap, not a bug in anyone's lane, and it is roughly a 30–45 minute fix.

`pages/atlas.jac:160` is currently honest about it, which is the right instinct:

> *"The seeded stack is fixture data, not crawled filings."*

That line should be deletable by showtime.

---

## 3. Deploy risks, in order of how badly they end the demo

**1. It is not deployed.** No URL anywhere in the repo. SPEC-V2 called this the highest risk
in the project several hours ago and it is still open. The `jac.toml` comments show the
JacHammer builder already failed once on `import from byllm.lib`, and **the fix for that is
still uncommitted** — `jac.toml` is modified in the working tree. Commit and push it.

**2. `max_replicas = 4` with no Mongo configured.** `[scale.kubernetes]` is set but there is
no `[plugins.scale.database]`, so each replica gets its own SQLite and users see different
graphs depending on which pod they hit. SPEC-V2 flagged this as deploy-fatal and it is
unchanged. **Set `max_replicas = 1`.** One line, cannot fail on stage.

**3. `seed_atlas` is never called automatically.** It exists, it's idempotent, it's tested —
and nothing invokes it. A fresh deploy serves an empty atlas until someone remembers to
`curl -X POST /walker/seed_atlas`. Worse, it resolves `Path("seed/atlas")` **relative to the
process CWD**; if the container's working directory differs, `base.exists()` is `False`, the
walker reports `seeded: 0` and succeeds silently. Two fixes, both cheap: resolve the path
relative to the module file rather than CWD, and have the client fire `seed_atlas` on cold
start when `atlas {}` comes back empty.

**4. `jac-version = "==0.34.7"` vs. an installed toolchain reported as 0.16.7.** Flagged in
SPEC-V2 §C2, still unverified. If the builder honors that pin and can't resolve it, the deploy
fails at install time.

**5. The demo script still narrates the fixture path.** `docs/demo-script.md` has a good
warning block at the top, but the beats underneath still say *"This is JacHammer. Eight
vendors it can name"* and *"Sixty-three percent of the stack terminates at AWS."* Both are
fixture numbers. Once §2 is fixed these become real numbers off a real company — rewrite the
beats then, and delete the warning block.

---

## 4. What is left, in the order I would do it

| # | Task | Owner | Why now |
|---|---|---|---|
| 1 | Commit `jac.toml`, set `max_replicas = 1`, **deploy** | C | Nothing else matters if there's no URL |
| 2 | `seed_atlas` on cold start + module-relative path | A + C | Deployed instance is empty without it |
| 3 | Client → contract v2: `atlas {}` for the landing, `graph {domain}` on select | C | Makes the real data visible. Biggest single win |
| 4 | Delete the `detect_vendors` / `DEMO_VENDORS` fallback path | C | Removes the last fabricated surface |
| 5 | Rewrite demo-script beats against real numbers; drop the warning block | Snehil + C | Script must match what's on screen |
| 6 | Rehearse twice **on the deployed URL** | all | Non-negotiable |

Everything below this line is bonus and should be cut without discussion if 1–6 aren't done:
`industry_map` UI (the Map), search UI, compliance panel, `root.shared`, diff monitor UI,
defense adapter.

**On the compliance panel:** B has not landed cited SOC 2 / outage facts, so
`compliance_fallout` returns `[]` and the panel renders empty. An empty panel reads as broken.
Cut it from the UI rather than shipping it hollow.

---

## 5. Pitch adjustments the new architecture earns you

The atlas pivot changed what your best lines are. Update the pitch to match:

- **Lead with provenance, not the graph.** "Nineteen companies, 555 disclosed dependencies,
  every one read from a public Article 28 filing with the source URL attached." That sentence
  beats any visual.
- **The coverage gap is an asset.** `openrouter.ai` came back `unreadable`. Show it. "One of
  twenty we could not read — it's a client-rendered trust center. We report that instead of
  guessing." Judges remember the team that showed its own miss.
- **New best Jac line:** "Reads are unbounded and free — full BFS over the whole reachable
  component in 729 milliseconds — because in Jac the graph *is* the database. We put the
  budget on crawling, which costs money, not on depth, which doesn't."
- **The three Jac pillars still split cleanly** — A on object-spatial, B on meaning-typed
  extraction and canonicalization, C on scale invariance. That's unchanged and it's good.

---

## 6. Honest read on where you stand

The engineering is ahead of where most teams are, and the data work is well ahead. The
`cited` gate and the committed raw filings are the kind of thing that wins the judges who
have actually shipped software.

The exposure is entirely in the last mile: **not deployed, and the UI is pointed at the wrong
data source.** Both are fixable in about an hour of focused work by one person each, and
neither is a design problem.

Do 1–6. Cut everything else. You are closer than the repo makes it feel.
