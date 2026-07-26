"""Run one bounded real byLLM extraction against a committed filing fixture."""

import json;
import from hashlib { sha256 }
import from pathlib { Path }
import from extract { extract_subprocessors }


def filing_excerpt(text: str, max_chars: int = 8000) -> str {
    marker: str = "Third Party Sub-processors";
    start: int = text.index(marker) if marker in text else 0;
    return text[start:start + max_chars];
}


with entry:__main__ {
    fixture: str = Path("seed/raw/openai.com.txt").read_text();
    records = extract_subprocessors(filing_excerpt(fixture));
    payload: str = json.dumps([
        {
            "name": record.name,
            "purpose": record.purpose,
            "region": record.hosting_region
        }
        for record in records
    ], ensure_ascii=False, separators=(",", ":"), sort_keys=True);
    print(json.dumps({
        "count": len(records),
        "names": [record.name for record in records],
        "sha256": sha256(payload.encode()).hexdigest()
    }, ensure_ascii=False, sort_keys=True));
}
