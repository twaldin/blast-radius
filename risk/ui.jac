"""The one presentational piece both surfaces share.

Everything else that used to live here was an abstraction with no consumer:
each view renders its own markup because each view is a different document.
"""

import from .store { useRisk }

def:pub LoadState() -> JsxElement {
    risk: any = useRisk();
    meta: any = risk["meta"];
    # failure is owned by the page, which pairs it with a retry control;
    # a blocking overlay there would hide the only way out
    if not meta["loading"] and not meta["crawling"] { return <span></span>; }
    return <div className="loadstate">{"Reading subprocessor filings…" if meta["crawling"] else "Loading…"}</div>;
}
