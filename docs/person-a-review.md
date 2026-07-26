# Person A Review Handoff — `main.jac`

Branch: `david`

Status: **review required before merge**. Automated checks establish behavior,
but they do not replace Person A's approval of their owned graph/walker file.

## Why `main.jac` changed

Person B's seed, identity, search, and evidence contracts need a narrow graph
integration surface. The current diff is 160 additions and 75 deletions in
`main.jac` (235 changed lines).

## Reviewable change groups

1. **Typed seed import**
   - Replaces unvalidated dictionary parsing with `load_seed_directory`.
   - Rejects the entire import if any seed fails schema, fixture, hash, status,
     sorting, or deduplication validation.
   - Preserves seed timestamps and content hashes.
   - Rebuilds `Subprocesses` edges idempotently and deduplicates canonical
     targets.
2. **Canonical company identity**
   - Uses the resolved canonical domain when creating live-extraction targets.
   - Maps known provider aliases to stable domains during seed import.
3. **Deterministic search**
   - Wraps B's pure `rank_company_matches` helper in A's public `search` walker.
   - Merges registry and graph candidates and returns mapped status, source URL,
     crawl status, and score.
4. **Cited provider evidence**
   - Projects first-party SOC evidence into node payloads.
   - Does not ship or score uncited downtime; `downtime_hours_ytd` remains zero.
   - Leaves unsupported supply-chain claims empty.
5. **Jac 0.34 graph typing**
   - Treats `root ++> Company(...)` as the connected node rather than indexing
     it as a one-element list.
6. **Live crawl cleanup**
   - Removes the demo-cache argument from `resolve_url`.
   - A genuine registry miss remains `notfound`; Browser Harness is not wired as
     a runtime fallback.

## Person A acceptance checklist

- [ ] Seed import failure is intentionally all-or-nothing.
- [ ] Re-importing the same corpus keeps node and edge counts stable.
- [ ] Canonical-domain upserts cannot merge unrelated companies.
- [ ] The additional search response fields are compatible with the frontend.
- [ ] SOC evidence belongs in `_node_payload` rather than persisted `Company`
      fields.
- [ ] The `root ++>` typing change matches the deployed Jac 0.34.7 runtime.
- [ ] Approve the `main.jac` diff, or request changes before merge.

## Reproduction commands

```bash
jac run scripts/validate_atlas_seeds.jac
jac test atlas_seed.jac -v
jac test main.jac -v
jac check main.jac
git diff -- main.jac
```
