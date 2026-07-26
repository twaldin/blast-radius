# Blast Radius — 3-minute demo script

**Snehil pitches. C drives the laptop.** Rehearse twice on the deployed URL, not localhost.

Pre-flight (every rehearsal and the real run):

```bash
jac clean --all --force        # stale NodeAnchor errors kill graph demos on stage
jac start main.jac --port 8000 # NOT --dev: the dev proxy has an IPv6/ECONNREFUSED bug
```

Open `/atlas` with the outage **cleared**. `/` is the memo landing and `/brief` is the
auditor document — both one click away in the top-right switcher. There is no `/console`
any more; its outage controls live on the Atlas board.

> ## Read before speaking any of this
>
> **The seeded graph is fixture data, not crawled filings.** SPEC-V2 §2 records
> `DEMO_VENDORS`, `DEMO_SUBPROCESSORS`, every `downtime_hours_ytd`, and the Fastly
> SOC 2 / watchlist flags as fabricated. Until B's precompute lands and the graph is
> built from real Article 28 pages, **do not claim provenance on stage** — no "read
> from their own filings", no downtime hours, no compliance verdicts.
>
> The rule, from SPEC-V2: *if a real filing or a citable source didn't give it to us,
> we don't ship it.* A judge who probes one invented number takes the room with them.
>
> Two versions of the reveal, pick by what is true at showtime:
> - **On fixtures:** "This is a worked example of the shape — eight vendors, five
>   providers, five of them landing on one." Describe the mechanism, claim nothing.
> - **On crawled data:** the lines below as written.

---

| Time | Beat | Driver action | Spoken |
|---|---|---|---|
| 0:00 | Hook | Sit on Atlas, nothing selected | "Your vendors have vendors. You've never seen that list. Name your company." |
| 0:20 | The org | Point at the left node | "This is JacHammer. Eight vendors it can name." |
| 0:35 | The second layer | Sweep right across the graph | "These five on the right are what those vendors run on. Most B2B vendors publish a sub-processor list — it's how Article 28 authorization and change-notice works in practice. We normalize those disclosures across a whole stack, which nobody does by hand." |
| 0:55 | **The reveal** | Point at the AWS node — biggest circle | "Eight vendors resolve to five providers. Sixty-three percent of the stack terminates at AWS. Your redundancy is a myth." |
| 1:10 | Why it's ranked | Point to Concentration panel | "We rank by how much of the stack each provider carries. Five of eight vendors terminate at AWS — that's structure, not a score." |
| 1:25 | Coverage | Point at the coverage strip | "The strip reports what we could and could not read. Unreadable pages are reported, not guessed — we don't assert more than the source does." |
| 1:40 | **Money shot** | Click **Simulate outage** | "Watch the failure propagate backwards." *(let it play ~1.5s)* "That animation is one line of Jac: `[prov <-:Subprocesses:<-]`." |
| 2:00 | The output | Point at the outage panel | "Five vendors down, four features down, and a drafted customer status update — while everyone else is still guessing which systems are involved." |
| 2:15 | The artifact | Click **Brief** | "Same graph, different job. This is the concentration-risk section of a security questionnaire. Copy as text, paste into the questionnaire. That's the thing that currently costs days." |
| 2:30 | Scale invariance | Open the deployed URL on the judge's phone | "Same file. `jac run`, `jac start`, `jac start --scale`. Kubernetes, Mongo, Redis — no Dockerfile, no migrations, no tenancy code." |
| 2:50 | Close | Show `/docs` Swagger or the admin portal graph for ~5 seconds | "Every walker is a REST endpoint for free. That's the language, not us." |

---

## Q&A — C's pillar: scale invariance

- **"Why JacHammer?"** One file runs three ways with an empty diff: `jac run` locally, `jac start` as a server, `jac start --scale` as a Kubernetes deployment with Mongo and Redis provisioned. Walkers become REST endpoints and Swagger with no routing code.
- **"What's scale-to-zero?"** jac-scale's KEDA autoscaler can hold a deployment at zero replicas behind a stable URL and wake it on the first request. **We deliberately pinned `min_replicas = 1` for the demo** so nothing cold-starts on stage — the capability is the platform's, the setting is ours.
- **"Who pays?"** The startup that just got a security questionnaire with a concentration-risk question in it, and the fintech whose bank partner pushes third-party-risk requirements downstream contractually.
- **"What's the wedge?"** The questionnaire artifact — the `/brief` view. Retention is the monitor: vendors add subprocessors quietly and most DPAs give you 30 days to object.
- **"How is this not Vanta?"** Vanta tracks your first-layer vendor list for compliance checkboxes. It doesn't expand transitively and doesn't compute concentration. Their output is "you have a DPA on file." Ours is "three of these die together."
- **"How do you know the data's right?"** We don't assert more than the source does. It's the vendor's own legal disclosure, and every edge carries `source_url` and `last_seen`.

## Cut order under time pressure

Delete from the bottom simultaneously: defense adapter → second-user login → coverage strip → diff monitor → risk memo. **Do not cut the rehearsals.**
