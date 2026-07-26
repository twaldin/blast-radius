"""Atlas — editorial. The graph is the field; the number is the headline.

No cards, no panels, no chrome boxes. Type sits directly on the canvas.
"""

import "./index.css";
import from ..risk.DependencyGraph { DependencyGraph }
import from ..risk.store { useRisk }
import from ..risk.ui { LoadState }

glob ATLAS_PALETTE: dict = {
    "org": "#ffffff",
    "vendor": "#6d7f95",
    "provider": "#5ec8ff",
    "flag": "#e0a44a",
    "down": "#ff4d4d",
    "edge": "rgba(120,150,180,0.16)",
    "edgeHot": "rgba(255,77,77,0.8)",
    "dim": "rgba(120,138,160,0.13)",
    "label": "rgba(232,238,247,0.55)",
    "labelOn": "rgba(255,255,255,0.98)",
    "font": "-apple-system, Segoe UI, Roboto, sans-serif"
};

def:pub Atlas() -> JsxPage {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];

    a: any = st["active"];
    o: any = st["outage"];
    h: any = st["headline"];
    share_pct: str = (str(round((a["share"] as float) * 100)) + "%") if a else "—";

    return <div className="atlas">
        <DependencyGraph palette={ATLAS_PALETTE} />
        <LoadState />

        <div className="tiers">
            <span>you</span>
            <span>vendors</span>
            <span>shared providers</span>
        </div>

        {if o {
            <div className="hero hero-down">
                <span className="hero-eyebrow">simulated outage</span>
                <h1 className="hero-num">{o["provider"]}</h1>
                <p className="hero-say">{str(len(o["vendors_down"])) + " vendors and " + str(len(o["features_down"])) + " product surfaces go dark together."}</p>
            </div>
            skip;
        }}

        {if not o {
            <div className="hero">
                <span className="hero-eyebrow">concentration</span>
                <h1 className="hero-num">{share_pct}</h1>
                <p className="hero-say">
                    {"of " + (st["org_label"] as str) + "'s stack terminates at " + ((a["provider"] as str) if a else "one provider") + "."}
                </p>
            </div>
            skip;
        }}

        {if not o {
            <div className="ranks">
                {for c in st["chokes"] {
                    <button
                        key={c["provider"]}
                        className={"rank" + (" on" if c["provider"] == st["selected"] else "")}
                        onClick={lambda { acts["select"](c["provider"] as str); }}
                    >
                        <span className="rank-n">{c["provider"]}</span>
                        <span className="rank-x">{str(c["vendors_affected"]) + " vendors"}</span>
                        <span className="rank-e">{str(c["exposure"])}</span>
                    </button>
                }}
                <span className="ranks-key">exposure = share × downtime ytd</span>
            </div>
            skip;
        }}

        {if a and not o {
            <div className="act">
                <div className="act-stats">
                    <span><b>{str(a["downtime_hours_ytd"]) + "h"}</b> downtime ytd</span>
                    <span><b>{str(a["vendors_affected"])}</b> dependents</span>
                </div>
                <button className="act-go" onClick={acts["simulate"]}>Simulate outage →</button>
            </div>
            skip;
        }}

        {if o {
            <div className="down">
                <div className="down-line">
                    <span className="down-k">down</span>
                    <span className="down-v">{", ".join(o["vendors_down"])}</span>
                </div>
                <div className="down-line">
                    <span className="down-k">features</span>
                    <span className="down-v">{", ".join(o["features_down"])}</span>
                </div>
                <p className="down-post">{o["status_post"]}</p>
                <button className="act-go" onClick={acts["clear"]}>← Clear</button>
            </div>
            skip;
        }}

        {if h and not o {
            <p className="fix">{h["biggest_suggestion"]}</p>
            skip;
        }}

        {if len(st["fallout"]) > 0 and not o {
            <div className="gap">
                {for f in st["fallout"] {
                    <p key={f["vendor"]}>
                        <span className="gap-dot"></span>
                        <b>{(f["vendor"] as str) + " → " + (f["provider"] as str)}</b>
                        {" " + (f["reason"] as str)}
                    </p>
                }}
            </div>
            skip;
        }}
    </div>;
}
