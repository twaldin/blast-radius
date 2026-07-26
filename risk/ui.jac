"""Composable pieces every surface reuses.

Each one reads the shared context itself, so a page composes by placing them —
no prop drilling, no `showX` flags. Structure is passed as `children`.
"""

import from .store { useRisk }

def:pub Panel(label: str = "", tone: str = "base", children: any = None) -> JsxElement {
    return <section className={"panel panel-" + tone}>
        {label and <span className="panel-label">{label}</span>}
        {children}
    </section>;
}

def:pub Headline() -> JsxElement {
    risk: any = useRisk();
    h: any = risk["state"]["headline"];
    if not h { return <span></span>; }
    return <div className="headline">
        <p className="headline-risk">{h["biggest_risk"]}</p>
        <p className="headline-fix">{h["biggest_suggestion"]}</p>
    </div>;
}

def:pub ConcentrationList() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];
    rows: any = st["chokes"];

    return <div className="conc">
        {for c in rows {
            <button
                key={c["provider"]}
                className={"conc-row" + (" on" if c["provider"] == st["selected"] else "")}
                onClick={lambda { acts["select"](c["provider"] as str); }}
            >
                <span className="conc-name">{c["provider"]}</span>
                <span className="conc-track">
                    <span className="conc-fill" style={{"width": str(round((c["share"] as float) * 100)) + "%"}}></span>
                </span>
                <span className="conc-exp">{str(c["exposure"])}</span>
            </button>
        }}
    </div>;
}

def:pub SelectedSummary() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];
    a: any = st["active"];
    if not a { return <span></span>; }
    if st["outage"] { return <span></span>; }

    return <div className="sel">
        <h2 className="sel-name">{a["provider"]}</h2>
        <div className="sel-metrics">
            <div className="metric">
                <span className="metric-v">{str(round((a["share"] as float) * 100)) + "%"}</span>
                <span className="metric-k">of stack</span>
            </div>
            <div className="metric">
                <span className="metric-v">{str(a["vendors_affected"])}</span>
                <span className="metric-k">vendors</span>
            </div>
            <div className="metric">
                <span className="metric-v">{str(a["downtime_hours_ytd"]) + "h"}</span>
                <span className="metric-k">downtime ytd</span>
            </div>
        </div>
        <ul className="sel-deps">
            {for nm in a["names"] {
                <li key={nm}>{nm}</li>
            }}
        </ul>
        <button className="btn-primary" onClick={acts["simulate"]}>Simulate outage</button>
    </div>;
}

def:pub OutageReport() -> JsxElement {
    risk: any = useRisk();
    o: any = risk["state"]["outage"];
    if not o { return <span></span>; }

    return <div className="outage">
        <div className="outage-block">
            <span className="outage-k">Vendors down</span>
            <p className="outage-v">{", ".join(o["vendors_down"])}</p>
        </div>
        <div className="outage-block">
            <span className="outage-k">Features down</span>
            <p className="outage-v">{", ".join(o["features_down"])}</p>
        </div>
        <div className="outage-block">
            <span className="outage-k">Drafted status update</span>
            <p className="outage-post">{o["status_post"]}</p>
        </div>
    </div>;
}

def:pub FalloutList() -> JsxElement {
    risk: any = useRisk();
    rows: any = risk["state"]["fallout"];

    return <div className="fallout">
        {for f in rows {
            <div className="fallout-row" key={f["vendor"]}>
                <span className="fallout-pair">{(f["vendor"] as str) + " → " + (f["provider"] as str)}</span>
                <span className="fallout-reason">{f["reason"]}</span>
                <p className="fallout-breaks">{f["breaks"]}</p>
            </div>
        }}
    </div>;
}

def:pub LoadState() -> JsxElement {
    risk: any = useRisk();
    meta: any = risk["meta"];
    if meta["ready"] { return <span></span>; }
    return <div className="loadstate">
        {if meta["failed"] {
            <span>Backend unreachable — run <code>jac start main.jac --port 8000</code></span>
            skip;
        }}
        {if meta["loading"] {
            <span>Reading subprocessor disclosures…</span>
            skip;
        }}
    </div>;
}
