# Registry Research Rules

Each `registry-*.json` file is a non-overlapping research batch. Every entry has:

```json
{
  "name": "Example",
  "domain": "example.com",
  "subprocessor_url": "https://example.com/legal/subprocessors",
  "source_type": "official_website",
  "verified_on": "2026-07-26",
  "notes": "Opened and confirmed a named subprocessor list."
}
```

An entry is eligible only when its URL has been opened and verified as one of:

- the company's own legal, privacy, trust, security, DPA, or subprocessor page;
- an official GitHub organization/repository file that publishes the list.

Search snippets, aggregators, AI summaries, generic privacy policies without a
named list, unrelated repositories, and guessed URLs are not valid sources.

Generate the Jac module after all six batches exist:

```bash
jac run scripts/build_registry.jac --expected-count 150
```
