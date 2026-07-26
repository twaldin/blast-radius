"""Atlas — the working instrument.

Data-maximalist panel grid, Swiss editorial skin. Every panel here is backed
by a real field from the walker contract; nothing here is invented data.
"""

import "./atlas.css";
import from ..risk.DependencyGraph { DependencyGraph }
import from ..risk.store { useRisk }
import from ..risk.ui { LoadState }

def pct(x: any) -> str {
    return str(round((x as float) * 100));
}

def:pub page() -> JsxPage {
    risk: any = useRisk();
    st: any = risk["state"];
    acts: any = risk["actions"];
    meta: any = risk["meta"];

    has domain_in: str = "";
    has manual_in: str = "";

    a: any = st["active"];
    o: any = st["outage"];
    h: any = st["headline"];
    cov: any = st["coverage"];
    counts: any = cov["counts"];
    chokes: any = st["chokes"];
    nodes: any = st["nodes"];
    max_exp: float = (chokes[0]["exposure"] as float) if chokes and len(chokes as list) > 0 else 1.0;

    feature_rows: list[any] = [];
    for v in st["vendors"] {
        for f in v["features"] {
            feature_rows = feature_rows + [{"feature": f, "vendor": v["label"], "id": v["id"]}];
        }
    }

    edge_set: dict = st["edge_keys"] or {};

    return <div className="atlas">
        {#* ---------------------------------------------------------- header strip *#}
        <header className="hdr">
            <div className="hdr-l">
                <span className="hdr-tag">One-look</span>
                <p className="hdr-say">{h["biggest_risk"] if h else "Reading subprocessor filings…"}</p>
            </div>
            <div className="hdr-r">
                <span className="hdr-tag">Recommendation</span>
                <p className="hdr-fix">{h["biggest_suggestion"] if h else "—"}</p>
            </div>
        </header>

        <div className="board">
            {#* ------------------------------------------------------ left rail *#}
            <div className="rail">
                <section className="pan">
                    <div className="pan-h"><span><span className="pan-n">01</span><span className="pan-t">Stack metrics</span></span><span className="pan-meta">ytd</span></div>
                    <div className="pan-b metrics">
                        <div className="met">
                            <span className="fig met-v met-hot">{(pct(a["share"]) if a else "—") + "%"}</span>
                            <span className="met-k">Stack share</span>
                        </div>
                        <div className="met">
                            <span className="fig met-v">{(str(a["downtime_hours_ytd"]) if a else "—") + "h"}</span>
                            <span className="met-k">Downtime ytd</span>
                        </div>
                        <div className="met">
                            <span className="fig met-v">{str(a["exposure"]) if a else "—"}</span>
                            <span className="met-k">Exposure</span>
                        </div>
                        <div className="met">
                            <span className="fig met-v">{str(st["provider_total"])}</span>
                            <span className="met-k">Providers</span>
                        </div>
                    </div>
                </section>

                <section className="pan">
                    <div className="pan-h"><span><span className="pan-n">02</span><span className="pan-t">Crawl coverage</span></span><span className="pan-meta fig">{str(cov["done"]) + "/" + str(cov["total"])}</span></div>
                    <div className="pan-b">
                        <div className="cov-bar">
                            <span className="cov-seg cov-ok" style={{"flex": str(counts["ok"])}}></span>
                            <span className="cov-seg cov-un" style={{"flex": str(counts["unreadable"])}}></span>
                            <span className="cov-seg cov-nf" style={{"flex": str(counts["notfound"])}}></span>
                            <span className="cov-seg cov-pd" style={{"flex": str(counts["pending"])}}></span>
                        </div>
                        <div className="cov-keys">
                            <span><span className="k-ok"></span>{(str(counts["ok"]) as str) + " ok"}</span>
                            <span><span className="k-un"></span>{(str(counts["unreadable"]) as str) + " unreadable"}</span>
                            <span><span className="k-nf"></span>{(str(counts["notfound"]) as str) + " notfound"}</span>
                            <span><span className="k-pd"></span>{(str(counts["pending"]) as str) + " pending"}</span>
                        </div>
                        <p className="cov-note">Read from each vendor's own subprocessor filing. Unreadable pages are reported, not guessed.</p>
                    </div>
                </section>

                <section className="pan pan-grow">
                    <div className="pan-h"><span><span className="pan-n">03</span><span className="pan-t">Vendor × provider</span></span><span className="pan-meta fig">{str(len(st["links"])) + " edges"}</span></div>
                    <div className="pan-b">
                        <table className="matrix">
                            <thead>
                                <tr>
                                    <th></th>
                                    {for p in st["providers"] {
                                        <th key={p["id"]} className={"mx-h" + (" on" if p["id"] == st["selected"] else "")}>{(((p["label"] as str)[0:4]) as any).toUpperCase()}</th>
                                    }}
                                </tr>
                            </thead>
                            <tbody>
                                {for v in st["vendors"] {
                                    <tr key={v["id"]}>
                                        <td className="mx-v">{v["label"]}</td>
                                        {for p in st["providers"] {
                                            <td key={p["id"]} className={"mx-c" + (" hit" if ((v["id"] as str) + ">" + (p["id"] as str)) in edge_set else "") + (" core" if (((v["id"] as str) + ">" + (p["id"] as str)) in edge_set) and p["id"] == st["selected"] else "")}></td>
                                        }}
                                    </tr>
                                }}
                            </tbody>
                        </table>
                    </div>
                </section>
            </div>

            {#* ------------------------------------------------------ centre canvas *#}
            <section className="pan canvas">
                <div className="pan-h">
                    <span><span className="pan-n">04</span><span className="pan-t">Dependency graph</span></span>
                    <span className="pan-meta fig">{str(len(nodes)) + "n / " + str(len(st["links"])) + "e"}</span>
                </div>
                <div className="canvas-b">
                    <DependencyGraph />
                    <LoadState />
                    {if len(nodes) == 0 and not meta["loading"] and not meta["crawling"] {
                        <div className="intake">
                            <p className={"intake-k" + (" bad" if meta["failed"] else "")}>{"Detection failed" if meta["failed"] else "No graph yet"}</p>
                            <p className="intake-say">{"The server rejected the request — check it is running, then try again." if meta["failed"] else "Load the seeded demo stack, or add vendor domains by hand."}</p>
                            <div className="intake-row">
                                <input
                                    className="intake-in"
                                    value={domain_in}
                                    placeholder="jachammer.ai"
                                    onChange={lambda (e: ChangeEvent) { domain_in = e.target.value; }}
                                    onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Enter" { acts["ingest"](domain_in or "jachammer.ai"); } }}
                                />
                                <button className="btn" onClick={lambda { acts["ingest"](domain_in or "jachammer.ai"); }}>Detect vendors</button>
                            </div>
                            <div className="intake-row">
                                <input
                                    className="intake-in"
                                    value={manual_in}
                                    placeholder="notion.so, linear.app — what detection cannot see"
                                    onChange={lambda (e: ChangeEvent) { manual_in = e.target.value; }}
                                    onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Enter" { acts["addManual"](manual_in); } }}
                                />
                                <button className="btn btn-quiet" onClick={lambda { acts["addManual"](manual_in); }}>Add manually</button>
                            </div>
                            <p className="intake-fine">The seeded stack is fixture data, not crawled filings. Live detection and real subprocessor crawling are still landing.</p>
                        </div>
                        skip;
                    }}
                </div>
                <div className={"canvas-f" + (" hot" if o else "")}>
                    {if o {
                        <span className="blast-line">
                            <b>Blast radius — {(o["provider"] as str)} down</b>
                            <span className="blast-count">{"→ " + str(len(o["vendors_down"])) + "/" + str(st["vendor_total"]) + " vendors"}</span>
                            <span className="blast-feats">
                                {for f in o["features_down"] {
                                    <span className="blast-feat" key={f}>{f}</span>
                                }}
                            </span>
                        </span>
                        <button className="btn btn-quiet" onClick={acts["clear"]}>Reset</button>
                        skip;
                    }}
                    {if not o {
                        <span>Click a provider to select · simulate to trace its blast radius</span>
                        <button className="btn" onClick={acts["simulate"]} disabled={not a}>Simulate outage →</button>
                        skip;
                    }}
                </div>
            </section>

            {#* ------------------------------------------------------ right rail *#}
            <div className="rail">
                <section className="pan">
                    <div className="pan-h"><span><span className="pan-n">05</span><span className="pan-t">Chokepoint rank</span></span><span className="pan-meta">exposure</span></div>
                    <div className="pan-b">
                        {for c in chokes {
                            <button
                                key={c["provider_id"]}
                                className={"rank" + (" on" if c["provider_id"] == st["selected"] else "")}
                                onClick={lambda { acts["select"](c["provider_id"] as str); }}
                            >
                                <span className="rank-top">
                                    <span className="rank-n">{c["provider"]}</span>
                                    <span className="fig rank-e">{str(c["exposure"])}</span>
                                </span>
                                <span className="rank-track">
                                    <span
                                        className={"rank-fill" + (" lead" if c["exposure"] == max_exp else "")}
                                        style={{"width": str(round(((c["exposure"] as float) / max_exp) * 100)) + "%"}}
                                    ></span>
                                </span>
                            </button>
                        }}
                    </div>
                </section>

                {if o {
                    <section className="pan pan-hot">
                        <div className="pan-h"><span><span className="pan-n">06</span><span className="pan-t">Blast radius</span></span><span className="pan-meta">{o["provider"]}</span></div>
                        <div className="pan-b">
                            <span className="hot-k">Vendors down</span>
                            <p className="hot-v">{", ".join(o["vendors_down"])}</p>
                            <span className="hot-k">Features down</span>
                            <p className="hot-v">{", ".join(o["features_down"])}</p>
                            <span className="hot-k">Drafted status update</span>
                            <p className="hot-post">{o["status_post"]}</p>
                        </div>
                    </section>
                    skip;
                }}

                {if not o {
                    <section className="pan pan-grow">
                        <div className="pan-h"><span><span className="pan-n">06</span><span className="pan-t">Feature exposure</span></span><span className="pan-meta fig">{str(len(feature_rows)) + " surfaces"}</span></div>
                        <div className="pan-b">
                            {for r in feature_rows {
                                <div className="feat" key={(r["id"] as str) + (r["feature"] as str)}>
                                    <span className="feat-n">{r["feature"]}</span>
                                    <span className="feat-v">{r["vendor"]}</span>
                                </div>
                            }}
                        </div>
                    </section>
                    skip;
                }}

                {if len(st["fallout"]) > 0 {
                    <section className="pan">
                        <div className="pan-h"><span><span className="pan-n">07</span><span className="pan-t">Compliance fallout</span></span><span className="pan-meta fig">{str(len(st["fallout"])) + " flagged"}</span></div>
                        <div className="pan-b">
                            {for f in st["fallout"] {
                                <div className="gap" key={(f["vendor"] as str) + (f["provider"] as str)}>
                                    <span className="gap-pair">{(f["vendor"] as str) + " → " + (f["provider"] as str)}</span>
                                    <span className="gap-why">{f["reason"]}</span>
                                    <p className="gap-txt">{f["breaks"]}</p>
                                    <span className="gap-tag">{"PII exposure path" if f["handles_pii"] else "Compliance gap inherited"}</span>
                                </div>
                            }}
                        </div>
                    </section>
                    skip;
                }}
            </div>
        </div>

        {#* ---------------------------------------------------------- ticker *#}
        <div className="wire">
            <span>Exposure index <span className="fig wire-b">{str(a["exposure"]) if a else "—"}</span></span>
            <span>Chokepoint <span className="wire-b">{(a["provider"] as str) if a else "—"}</span> at <span className="fig wire-b">{(pct(a["share"]) if a else "—") + "%"}</span> share</span>
            <span>Coverage <span className="fig wire-b">{str(counts["ok"]) + "/" + str(cov["total"])}</span> filings read</span>
            {if o {
                <span className="wire-hot">Simulation · {o["provider"]} outage</span>
                skip;
            }}
        </div>
    </div>;
}
