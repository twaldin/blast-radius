# Registry Research Rules

Each `registry-*.json` file is a non-overlapping research batch. Every entry has:

```json
{
  "name": "Example",
  "domain": "example.com",
  "subprocessor_url": "https://example.com/legal/subprocessors",
  "source_type": "official_website",
  "verified_on": "2026-07-26",
  "notes": "Opened and confirmed a named subprocessor list.",
  "flow_type": "rendered_html",
  "recommended_flow": "Open the official URL in Browser Harness, wait for the rendered page, locate the complete named subprocessor table/list in the DOM, extract its rows or list items, then canonicalize and deduplicate; return notfound if the page does not expose a complete current list."
}
```

An entry is eligible only when its URL has been opened and verified as one of:

- the company's own legal, privacy, trust, security, DPA, or subprocessor page;
- an official GitHub organization/repository file that publishes the list.

Search snippets, aggregators, AI summaries, generic privacy policies without a
named list, unrelated repositories, and guessed URLs are not valid sources.

`flow_type` is selected from a Browser Harness audit of the authoritative URL:

- `rendered_html`: the named list is visible in the rendered DOM;
- `rendered_html_guarded`: rendering, access, or completeness was uncertain;
- `rendered_trust_center`: a client-rendered trust center exposes the list;
- `trust_center_clickthrough`: the trust center requires locating and activating
  its Subprocessors document or section;
- `pdf_text`: the authoritative source is a PDF;
- `github_raw`: an official GitHub source should be opened in Raw view.

Every `recommended_flow` must end in deterministic source validation and say to
return `notfound` when no authoritative complete named list can be extracted.

Generate the Jac module after all six batches exist:

```bash
jac run scripts/build_registry.jac --expected-count 150
```
