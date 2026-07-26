# Registry batch audit

Audited on 2026-07-26. Scope: the six completed
`research/registry-*.json` files present during this audit. The batch JSON files
were not modified.

## Post-audit repair status

**PASS — all five source-scope failures were repaired.**

After the initial audit:

- Microsoft Azure was replaced by Temporal Technologies and its complete
  official public list.
- Brex was replaced by BlackLine and its complete official public list.
- Ramp was replaced by Allvue Systems and its official current PDF.
- Revolut People was replaced by Tilled and its complete embedded-payments
  list.
- Chargebee now points to its general multi-product subprocessor list.
- Salesforce now points to its general Infrastructure and Sub-processors
  document.
- Vercel remains, with an explicit requirement to use Browser Use because its
  complete list is client-rendered.

The repaired six-batch set contains exactly 150 entries and passes the Jac
validator with no duplicate names, domains, or URLs. The remaining REVIEW
items are browser/runtime extraction checks for client-rendered or opaque
documents, not known provenance or scope failures.

## Initial verdict before repairs

**FAIL — the registry is not ready to build.**

- Six batches contain 25 entries each: **150 entries total**.
- The required registry count is complete.
- All 150 present records pass the mechanical schema checks.
- The suspicious-source review found **5 FAIL** entries and **12 REVIEW**
  entries. These should be resolved before generating the Jac registry.

## Structural checks

| Check | Result | Detail |
| --- | --- | --- |
| JSON shape | PASS | All six files are arrays. |
| Per-file count | PASS | `registry-dev-infra.json`, `registry-fintech.json`, `registry-hr-data-ai.json`, `registry-productivity.json`, `registry-sales-marketing.json`, and `registry-security.json` each contain exactly 25 entries. |
| Total target | PASS | 150 present, matching the required total. |
| Exact schema | PASS | Every entry has exactly `name`, `domain`, `subprocessor_url`, `source_type`, `verified_on`, and `notes`; no extra or missing keys. |
| Non-empty fields | PASS | No empty string fields. |
| Source type | PASS | All records use `official_website`. |
| HTTPS | PASS | All `subprocessor_url` values begin with `https://`. |
| Verification date | PASS | All records use `2026-07-26`. |
| Duplicate names | PASS | None, case-insensitively, across all six files. |
| Duplicate domains | PASS | None, case-insensitively, across all six files. |
| Duplicate URLs | PASS | None across all six files. |

The structural checks validate shape, not truthfulness or breadth of the source.

## Source findings requiring action

### FAIL

#### Microsoft Azure — FAIL

The record is named **Microsoft Azure**, but its source is a one-product
“Microsoft Commercial Support Subprocessors” PDF. Commercial Support is not a
defensible proxy for the Azure service, so graph expansion would attach
support-service suppliers to the Azure company/product node.

Replacement advice: either:

1. rename the record to **Microsoft Commercial Support** and make the notes
   explicitly say it is support-only; or
2. retain **Microsoft Azure** only after finding and opening a current official
   Microsoft source that names subprocessors or subcontractors applicable to
   Azure itself.

Do not use the old 2016 “Microsoft Azure Subcontractors” PDF as a current
replacement.

#### Brex — FAIL

`https://trust-portal.brex.com/` is a generic Trust Center homepage. Its public
text exposes a February 2024 *change notice* naming Extend and Transcend and
removing OneTrust, but not the complete current named subprocessor list. A
change notice is not enough to reconstruct current state.

Replacement advice: open the Trust Center’s **Legal → Subprocessors** item in a
real browser and store a stable list-specific public URL only if it renders the
full current names. If the list is access-gated or has no stable public URL,
remove Brex rather than treating update notices as the list.

#### Ramp — FAIL

`https://trust.ramp.com/` is a generic Trust Center homepage. Public update
notices name several additions, but also identify at least one provider as no
longer in use. The homepage does not expose a complete current list, so
collecting names from notices can create stale provider nodes.

Replacement advice: open **Legal → Subprocessors** and capture a stable,
public, list-specific URL that displays the complete current list. If only
notices are public, remove Ramp from the curated registry and let browser
discovery return “Not found” instead of learning partial history.

#### Chargebee — FAIL

The company is labeled **Chargebee**, but the stored page is explicitly
“Chargebee Reveal and Revive Sub-processors” and names only the providers for
those products. A broader current official Chargebee list exists and includes
Billing, Retention/Growth, RevRec, Receivables, and Reveal.

Replacement advice: use
`https://www.chargebee.com/privacy/sub-processors/`, then reopen it and update
the note to its actual effective date and product coverage. Alternatively,
rename the company node to **Chargebee Reveal and Revive** if narrow
product-level nodes are intentional.

#### Salesforce — FAIL

The record is labeled **Salesforce**, but its PDF is expressly scoped to
**Professional Services**. It lists third-party tools used while Salesforce
performs professional services, not the subprocessors for Salesforce online
services generally.

Replacement advice: use the current Salesforce “Infrastructure and
Sub-processors” document at
`https://www.salesforce.com/en-us/wp-content/uploads/sites/4/documents/legal/misc/salesforce-infrastructure-and-subprocessors.pdf`
and extract only the section(s) applicable to Salesforce Services. If the
Professional Services PDF is retained, rename the record **Salesforce
Professional Services**.

### REVIEW

#### Revolut — REVIEW

The page is valid and its DPA Annex B names Google Cloud and OpenAI, but it is
unambiguously limited to **Revolut People**. It does not support company-wide
Revolut provider inference.

Resolution: rename the entry **Revolut People** and treat it as a product-level
vendor, or replace it with a current official list covering the intended
Revolut service. Do not silently attach these two providers to a generic
Revolut node.

#### Vercel — REVIEW

The URL resolves to Vercel’s official SafeBase Trust Center subprocessor item
and public updates name several AI providers. In non-interactive extraction,
however, the actual “Subprocessors” result area is blank; only change notices
are readable. This may be a client-rendered list, but the full current list was
not independently captured in this audit.

Resolution: verify with Browser Use that the search/list widget renders a
complete named table, then keep the item URL and record a small sample of names
in the note. If Browser Use sees only notices, classify it like Brex/Ramp and
remove it.

#### Canva — REVIEW

The opaque `content-management-files.canva.com` URL could not be directly
rendered by the audit fetcher. Official provenance is nevertheless defensible:
Canva’s first-party `https://www.canva.com/policies/subprocessors/` page links
that exact asset as the most recent version of Canva’s list.

Resolution: prefer storing the stable first-party policy page URL and have the
fetcher follow its “most recent version” link. If the direct asset URL is kept,
open it in Browser Use and record the document title, effective date, and at
least two named providers in the note.

#### Rippling — REVIEW

The generic Trust Center homepage visibly identifies a public document titled
“Rippling Sub-processors (April 30, 2026).pdf,” but the stored URL does not
present the document contents or any named provider.

Resolution: use Browser Use to open that Additional Documents item and save its
stable public document URL. Keep Rippling only after confirming named providers
inside the PDF; the homepage title alone is insufficient for extraction.

#### Ashby — REVIEW

The SafeBase item is official and update notices link it as the “full list,”
but non-interactive retrieval exposes only additions such as Braintrust,
Polytomic, Plain, Seon, Assembly AI, and Recall AI—not the complete current
table.

Resolution: verify that the exact item renders the full list in Browser Use and
record a current sample in the note. If only the historical additions render,
remove it for the same reason as Brex and Ramp.

#### Airbyte — REVIEW

`https://trust.airbyte.com/subprocessors` is appropriately list-specific, but
its response is entirely client-rendered and yielded no auditable names in
read-only retrieval.

Resolution: open it in Browser Use, confirm the full table and its current
state, and retain it only if the browser fallback can reliably extract the
names.

#### PostHog — REVIEW

The stored SafeBase item is official but its complete list is client-rendered;
non-interactive retrieval did not expose the named table.

Resolution: verify the exact item with Browser Use and add a current provider
sample to the note. Do not learn provider nodes from update notices alone.

#### Anthropic — REVIEW

`https://trust.anthropic.com/subprocessors` is a direct, official route, but its
named table is client-rendered and yielded no auditable content in read-only
retrieval.

Resolution: verify the complete list with Browser Use and confirm that the
production discovery adapter can extract it. Otherwise this curated anchor
will fail at runtime despite being a semantically correct URL.

#### Vanta — REVIEW

The direct official `/subprocessors` route is entirely client-rendered and
yielded no auditable names in read-only retrieval.

Resolution: verify the full list in Browser Use and confirm that the production
adapter can extract it; otherwise the curated anchor is not operational.

#### Fortinet — REVIEW

The generic Trust Resource Center has a client-rendered Subprocessors search
area, but non-interactive retrieval exposes only change notices. Those notices
include additions and removals and therefore are not a safe substitute for the
complete current table.

Resolution: capture a stable list-specific route if the portal provides one,
or verify with Browser Use that the full table is rendered and extractable from
the stored homepage. Do not construct current state from update notices.

#### Teleport — REVIEW

The direct official `/subprocessors` route is entirely client-rendered and
yielded no auditable names in read-only retrieval.

Resolution: verify the complete directory in Browser Use and test the same
extraction route used by the runtime fallback.

#### Verkada — REVIEW

Verkada’s official privacy page, updated June 2026, links the exact
`docs.verkada.com` PDF as its public Subprocessor List, so provenance is
defensible. The PDF content itself could not be rendered during this audit.

Resolution: open the PDF in Browser Use and record its title and a current
provider sample before acceptance, or store the stable first-party
`https://www.verkada.com/privacy/subprocessors/` landing page and follow its
download link at runtime.

## Suspicious sources that passed

These cases were specifically checked because they are PDFs, CDN assets,
parent-company publications, generic security pages, or product-aware lists.

| Entry | Result | Evidence |
| --- | --- | --- |
| Confluent | PASS | The first-party Confluent legal page links the exact `assets.confluent.io` PDF; the PDF is titled “Confluent Cloud Subprocessors” and contains named providers. |
| Supabase | PASS | The first-party DPA contains Schedule 3, “Sub-processors,” with names and processing descriptions. |
| Render | PASS | Although the URL is a general security page, it contains a visible “Subprocessors” table naming AWS, GCP, Cloudflare, and ClickHouse. |
| Slack | PASS | Salesforce is Slack’s parent company, and the 2026 Salesforce PDF has an explicit Slack section applying to Slack, Slack AI, and GovSlack with named providers. |
| Loom | PASS | Atlassian’s official Loom privacy page explicitly defines Loom subprocessors and names providers with processing descriptions. |
| Miro | PASS | The first-party PDF is titled “Miro Sub-processors,” dated 8 July 2026, and contains a named table plus a separately labeled AI-model-provider section. |
| DocuSign | PASS | The first-party DocuSign subprocessor page links the exact Contentful PDF; the PDF is dated July 2, 2026 and contains product-specific named lists. |
| 1Password | PASS | The first-party PDF is explicitly a list of sub-processors and names affiliates, infrastructure providers, applicable services, activities, and locations. |
| LastPass | PASS | The first-party PDF is titled “LastPass Sub-Processors” and names hosting, third-party, administrative, and affiliate subprocessors. |
| Make | PASS | The first-party Make terms page links the exact Contentful PDF as its current “Subprocessor” document; the PDF contains a named list. |
| Braze | PASS | Braze’s first-party legal/subprocessors page links the exact Sanity CDN PDF; the June 1, 2026 PDF contains named third-party and group subprocessors. |
| Zuora | PASS | The first-party PDF is a current named list of data-center, third-party, and affiliate subprocessors with product applicability. |
| Workday | PASS | The first-party July 1, 2026 PDF contains named affiliate, hosting, CDN, acquisition-specific, and product-specific subprocessor tables. |
| BambooHR | PASS | The first-party PDF is titled “Subcontractor List,” identifies BambooHR as the controller of the list, and contains named third parties. |
| Cohere | PASS | The official Trust Center HTML visibly names providers such as Google Cloud, Fullstory, LaunchDarkly, New Relic, Retool, Sentry, Segment, SendGrid, and Vercel with functions and locations. |
| Workato | PASS | The Workato PDF contains a named list with purposes and regions; Workato’s first-party legal page identifies the April 17, 2026 asset in its version history. |
| Celonis | PASS | Celonis’s first-party Services legal hub links the exact Adobe AEM asset as “Subprocessor Listing March 2026,” establishing the otherwise opaque asset’s provenance. |
| Palo Alto Networks | PASS | The first-party April 2026 PDF visibly names product, Unit 42, global-support, affiliate, and generative-AI subprocessors with applicability and activities. |
| Qualys | PASS | The first-party Qualys CDN PDF contains Annex III with named subprocessors, addresses, and processing purposes. |
| Netskope | PASS | The first-party February 2026 PDF visibly contains named product, hosting, support, and affiliate subprocessor tables. |

Direct CDN hosting is acceptable only when a current first-party company page
links the exact asset. The provenance chain was confirmed for Confluent,
DocuSign, Make, Braze, Canva, Workato, Celonis, and Verkada; Canva and Verkada
remain REVIEW because the asset content itself was not rendered.

## Audit limitation

The Browser Use harness could not attach because no local Chrome/Edge daemon
was running. Live source checking continued through read-only web retrieval.
The Vercel, Canva, Rippling, Ashby, Airbyte, PostHog, Anthropic, Vanta,
Fortinet, Teleport, and Verkada REVIEW items require a real browser pass before
acceptance. This limitation does not affect the structural results or the five
source-scope/completeness failures above.
