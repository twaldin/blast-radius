# Blast Radius — 3-minute demo script

**Snehil pitches. C drives the laptop.** Rehearse twice on the deployed URL, not localhost.

Pre-flight (every rehearsal and the real run):

```bash
jac clean --all --force        # stale NodeAnchor errors kill graph demos on stage
jac start main.jac --port 8000 # NOT --dev: the dev proxy has an IPv6/ECONNREFUSED bug
```

Open `/` (Atlas) with the outage **cleared**. Have `/console` and `/brief` one click away in the top-right view switcher.

---

| Time | Beat | Driver action | Spoken |
|---|---|---|---|
| 0:00 | Hook | Sit on Atlas, nothing selected | "Your vendors have vendors. You've never seen that list. Name your company." |
| 0:20 | The org | Point at the left node | "This is JacHammer. Eight vendors it can name." |
| 0:35 | The second layer | Sweep right across the graph | "These five on the right are what those vendors run on. Nobody assembled this list — it comes from the vendors' own GDPR Article 28 subprocessor disclosures." |
| 0:55 | **The reveal** | Point at the AWS node — biggest circle | "Eight vendors resolve to five providers. Sixty-three percent of the stack terminates at AWS. Your redundancy is a myth." |
| 1:10 | Why it's ranked | Point to Concentration panel | "We weight share by historical downtime. AWS logged 9.2 hours last year — that's the exposure number, not a vibe." |
| 1:25 | Compliance | Point at amber Fastly node, then the fallout panel | "Fastly is amber because its SOC 2 is invalid and it's on a supply-chain watchlist. Sentry sends error payloads through it — so your SOC 2 inherits that gap." |
| 1:40 | **Money shot** | Click **Simulate outage** | "Watch the failure propagate backwards." *(let it play ~1.5s)* "That animation is one line of Jac: `[prov <-:Subprocesses:<-]`." |
| 2:00 | The output | Point at the outage panel | "Five vendors down, four features down, and a drafted customer status update — while everyone else is still guessing which systems are involved." |
| 2:15 | The artifact | Click **Brief** | "Same graph, different job. This is the concentration-risk section of a security questionnaire. Copy as text, paste into the questionnaire. That's the thing that currently costs days." |
| 2:30 | Scale invariance | Click **Console**, then open the deployed URL on the judge's phone | "Same file. `jac run`, `jac start`, `jac start --scale`. Kubernetes, Mongo, Redis — no Dockerfile, no migrations, no tenancy code." |
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
