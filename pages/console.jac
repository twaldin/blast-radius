"""Console — mission-control telemetry. Same data, instrument-panel treatment."""

import "./console.css";
import from ..risk.DependencyGraph { DependencyGraph }
import from ..risk.store { useRisk }
import from ..risk.ui { OutageReport, LoadState }

glob CONSOLE_PALETTE: dict = {
    "org": "#8fe0ff",
    "vendor": "#3d8fa8",
    "provider": "#2fb8e8",
    "flag": "#e0a44a",
    "down": "#ff4d4d",
    "edge": "rgba(60,160,190,0.2)",
    "edgeHot": "rgba(255,77,77,0.75)",
    "dim": "rgba(60,160,190,0.12)",
    "label": "rgba(150,220,240,0.68)",
    "labelOn": "rgba(220,250,255,0.98)",
    "font": "ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace"
};

def total_exposure(chokes: any) -> float {
    total = 0.0;
    for c in chokes { total = total + (c["exposure"] as float); }
    return total;
}

def top_share(chokes: any) -> float {
    top = 0.0;
    for c in chokes {
        s = c["share"] as float;
        if s > top { top = s; }
    }
    return top;
}

def flagged_count(nodes: any) -> int {
    n = 0;
    for nd in nodes { if nd["flagged"] { n = n + 1; } }
    return n;
}

def:pub ReadoutCell(k: str, v: str) -> JsxElement {
    return <div className="rc-cell">
        <span className="rc-v">{v}</span>
        <span className="rc-k">{k}</span>
    </div>;
}

def:pub ChokeRow(c: any, selected: str, onSelect: Callable[[str], None]) -> JsxElement {
    def handle_click(e: MouseEvent) { onSelect(c["provider"] as str); }
    pct: str = str(round((c["share"] as float) * 100)) + "%";
    return <button
        key={c["provider"]}
        className={"cr-row" + (" on" if c["provider"] == selected else "")}
        onClick={handle_click}
    >
        <span className="cr-provider">{c["provider"]}</span>
        <span className="cr-bar">
            <span className="cr-bar-fill" style={{"width": pct}}></span>
        </span>
        <span className="cr-share">{pct}</span>
        <span className="cr-downtime">{str(c["downtime_hours_ytd"]) + "h"}</span>
        <span className="cr-exposure">{str(c["exposure"])}</span>
    </button>;
}

def:pub Console() -> JsxPage {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];
    chokes: any = st["chokes"];

    exposure: float = total_exposure(chokes);
    share: float = top_share(chokes);
    flagged: int = flagged_count(st["nodes"]);

    return <div className="console">
        <LoadState />

        <div className="console-readouts">
            <ReadoutCell k="total exposure" v={str(round(exposure, 1))} />
            <ReadoutCell k="top provider share" v={str(round(share * 100)) + "%"} />
            <ReadoutCell k="vendors" v={str(st["vendor_total"])} />
            <ReadoutCell k="flagged providers" v={str(flagged)} />
        </div>

        <div className="console-body">
            <div className="console-graph">
                <span className="console-frame-label">DEPENDENCY GRAPH</span>
                <DependencyGraph palette={CONSOLE_PALETTE} />
            </div>

            <div className="console-telemetry">
                <span className="console-frame-label">CHOKEPOINTS</span>
                {if st["outage"] {
                    <OutageReport />
                    skip;
                }}
                {if not st["outage"] {
                    <div className="cr-head">
                        <span>PROVIDER</span>
                        <span>SHARE</span>
                        <span></span>
                        <span>DOWNTIME</span>
                        <span>EXPOSURE</span>
                    </div>
                    for c in chokes {
                        <ChokeRow c={c} selected={st["selected"] as str} onSelect={acts["select"]} key={c["provider"]} />
                    }
                }}
                <div className="console-controls">
                    {if st["outage"] {
                        <button className="btn-ghost" onClick={acts["clear"]}>Clear</button>
                        skip;
                    }}
                    {if not st["outage"] {
                        <button className="btn-primary" onClick={acts["simulate"]}>Simulate</button>
                        skip;
                    }}
                </div>
            </div>
        </div>

        {if len(st["fallout"]) > 0 {
            <div className="console-log">
                {for f in st["fallout"] {
                    <div className="log-line" key={f["vendor"]}>
                        <span className="log-tag">WARN</span>
                        <span className="log-text">{(f["vendor"] as str) + " → " + (f["provider"] as str) + " · " + (f["reason"] as str) + " · " + (f["breaks"] as str)}</span>
                    </div>
                }}
            </div>
            skip;
        }}
    </div>;
}
