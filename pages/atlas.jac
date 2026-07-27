"""Atlas — the working instrument.

Data-maximalist panel grid, Swiss editorial skin. Every panel here is backed
by a real field from the walker contract; nothing here is invented data.
"""

cl import "./atlas.css";

cl {
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

    has search_in: str = "";
    has timer: any = None;
    has manual_in: str = "";

    a: any = st["active"];
    o: any = st["outage"];
    h: any = st["headline"];
    cov: any = st["coverage"];
    counts: any = cov["counts"];
    chokes: any = st["chokes"];
    nodes: any = st["nodes"];
    s: any = st["search"];

    # Citation gating: the backend re-ranks by share when the top choke row's
    # downtime figure is not backed by a cited source. Mirror that here --
    # never render an uncited downtime number, and label the rank panel after
    # the metric it is actually sorted by.
    top_cited: bool = False;
    if chokes and len(chokes as list) > 0 and chokes[0]["downtime_cited"] {
        top_cited = True;
    }
    metric_key: str = "exposure" if top_cited else "share";
    max_met: float = (chokes[0][metric_key] as float) if chokes and len(chokes as list) > 0 else 1.0;

    # Provenance: the current company's own filing must be inspectable.
    cur_src: str = "";
    for co in st["companies"] {
        if (co["domain"] as str) == (st["company_domain"] as str) {
            cur_src = ((co["source_url"] or "") as str);
            break;
        }
    }

    def on_query(q: str) -> None {
        search_in = q;
        if timer {
            (clearTimeout as any)(timer);
            timer = None;
        }
        if (q or "").strip() {
            timer = setTimeout(lambda { acts["search"](q); }, 300);
        } else {
            acts["clearSearch"]();
        }
    }

    def submit_query() -> None {
        if timer {
            (clearTimeout as any)(timer);
            timer = None;
        }
        if (search_in or "").strip() {
            acts["search"](search_in);
        }
    }

    def pick_hit(hit: any) -> None {
        if timer {
            (clearTimeout as any)(timer);
            timer = None;
        }
        if hit["match"] == "registry" {
            # Known but unmapped: same path as "Map it now" -- let the agent map it.
            acts["discover"]((s["q"] as str));
        } else {
            acts["view"]((hit["domain"] as str));
            acts["clearSearch"]();
            search_in = "";
        }
    }

    # Vendor nodes no longer carry a `features` list -- SPEC-V2 section 2 cut
    # the hand-mapped Feature type. The real text is the `purpose` recorded on
    # each subprocesses edge, straight from the filing, so derive from that.
    label_of: dict = {};
    for n in nodes { label_of[n["id"]] = n["label"]; }

    feature_rows: list[any] = [];
    seen_purpose: dict = {};
    for l in st["links"] {
        if l["kind"] != "subprocesses" { continue; }
        purpose: str = ((l["purpose"] or "") as str);
        if not purpose { continue; }
        src: str = (l["source"] as str);
        key: str = src + "|" + purpose;
        if key in seen_purpose { continue; }
        seen_purpose[key] = True;
        feature_rows = feature_rows + [{
            "feature": purpose,
            "vendor": label_of[src] if src in label_of else src,
            "id": key
        }];
    }

    edge_set: dict = ((st["edge_keys"] or {}) as dict);

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

        {#* ---------------------------------------------------------- search strip *#}
        <div className="sbar">
            <div className="sbar-row">
                <span className="sbar-tag">Company</span>
                <div className="sbox">
                    <input
                        className="sbox-in"
                        value={search_in}
                        placeholder="Search the atlas — figma.com, Okta, a domain or a name…"
                        onChange={lambda (e: ChangeEvent) { on_query(e.target.value); }}
                        onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Enter" { submit_query(); } }}
                    />
                    {if s["busy"] {
                        <span className="spin sbox-spin"></span>
                        skip;
                    }}
                </div>
                <select
                    className="sbar-sel"
                    value={st["company_domain"]}
                    onChange={lambda (e: ChangeEvent) { acts["view"]((e.target.value as str)); }}
                >
                    {if not (st["company_domain"] as str) {
                        <option value="">Pick a company…</option>
                        skip;
                    }}
                    {for co in st["companies"] {
                        <option key={(co["domain"] as str)} value={(co["domain"] as str)}>{co["name"]}</option>
                    }}
                </select>
            </div>

            {if s["done"] and len(s["hits"] as list) > 0 {
                <div className="sres">
                    {for hit in s["hits"] {
                        <button key={(hit["id"] as str)} className="shit" onClick={lambda { pick_hit(hit); }}>
                            <span className="shit-n">{hit["name"]}</span>
                            <span className="shit-d">{hit["domain"]}</span>
                            <span className="shit-s">{hit["state"]}</span>
                            <span className="fig shit-f">{str(hit["filing_count"]) + " filings"}</span>
                            {if hit["match"] == "registry" {
                                <span className="shit-tag">not mapped yet</span>
                                skip;
                            }}
                            <span className={"chip" + (" chip-reg" if hit["match"] == "registry" else "")}>{((hit["match"] as str) as any).toUpperCase()}</span>
                        </button>
                    }}
                </div>
                skip;
            }}

            {if s["done"] and len(s["hits"] as list) == 0 and (s["q"] as str) {
                <div className="sres sres-empty">
                    <span className="sres-none">No match in the atlas.</span>
                    {if s["discovering"] {
                        <span className="sdisc"><span className="spin"></span>Agent reading filings…</span>
                        skip;
                    }}
                    {if not s["discovering"] {
                        <button className="btn btn-map" onClick={lambda { acts["discover"]((s["q"] as str)); }}>Map it now →</button>
                        skip;
                    }}
                </div>
                skip;
            }}

            {if s["discovered"] and s["resolved"] {
                <div className="sres sres-found">
                    <span className="chip chip-disc">Discovered</span>
                    <span className="sres-rn">{s["resolved"]["name"]}</span>
                    <span className="sres-rd">{s["resolved"]["domain"]}</span>
                </div>
                skip;
            }}

            {if (s["error"] as str) {
                <div className="sres sres-err"><span className="serr">{s["error"]}</span></div>
                skip;
            }}
        </div>

        {#* ---------------------------------------------------------- region filter *#}
        {if len(st["regions"] as list) > 0 {
            <div className="regs">
                <button
                    className={"reg" + (" on" if not (st["region"] as str) else "")}
                    onClick={lambda { acts["setRegion"](""); }}
                >ALL</button>
                {for code in st["regions"] {
                    <button
                        key={(code as str)}
                        className={"reg" + (" on" if (st["region"] as str) == code else "")}
                        onClick={lambda { acts["setRegion"]((code as str)); }}
                    >{((code as str) as any).toUpperCase()}</button>
                }}
            </div>
            skip;
        }}

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
                            <span className="fig met-v">{((str(a["downtime_hours_ytd"]) + "h") if a and a["downtime_cited"] else "—")}</span>
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
                    <div className="pan-h">
                        <span><span className="pan-n">02</span><span className="pan-t">Crawl coverage</span></span>
                        <span className="pan-meta fig">
                            {str(cov["done"]) + "/" + str(cov["total"])}
                            {if cur_src {
                                <a className="cov-file" href={cur_src} target="_blank" rel="noreferrer">filing ↗</a>
                                skip;
                            }}
                        </span>
                    </div>
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
                    <div className="pan-h"><span><span className="pan-n">03</span><span className="pan-t">Vendor × provider</span></span><span className="pan-meta fig">{str(len(st["links"] as list)) + " edges"}</span></div>
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
                    <span className="pan-meta fig">{str(len(nodes as list)) + "n / " + str(len(st["links"] as list)) + "e"}</span>
                </div>
                <div className="canvas-b">
                    <DependencyGraph />
                    <LoadState />
                    {if len(nodes as list) == 0 and not meta["loading"] and not meta["crawling"] {
                        <div className="intake">
                            <p className={"intake-k" + (" bad" if meta["failed"] else "")}>{"Detection failed" if meta["failed"] else "No graph yet"}</p>
                            <p className="intake-say">{"The server rejected the request — check it is running, then try again." if meta["failed"] else "Search a company above, or add vendor domains by hand."}</p>
                            <div className="intake-row">
                                <input
                                    className="intake-in"
                                    value={manual_in}
                                    placeholder="notion.so, linear.app — comma-separated domains"
                                    onChange={lambda (e: ChangeEvent) { manual_in = e.target.value; }}
                                    onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Enter" { acts["addManual"](manual_in); } }}
                                />
                                <button className="btn btn-quiet" onClick={lambda { acts["addManual"](manual_in); }}>Add manually</button>
                            </div>
                        </div>
                        skip;
                    }}
                </div>
                <div className={"canvas-f" + (" hot" if o else "")}>
                    {if o {
                        <span className="blast-line">
                            <b>Blast radius — {(o["provider"] as str)} down</b>
                            <span className="blast-count">{"→ " + str(len(o["vendors_down"] as list)) + "/" + str(st["vendor_total"]) + " vendors"}</span>
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
                    <div className="pan-h"><span><span className="pan-n">05</span><span className="pan-t">Chokepoint rank</span></span><span className="pan-meta">{metric_key}</span></div>
                    <div className="pan-b">
                        {for c in chokes {
                            <button
                                key={c["provider_id"]}
                                className={"rank" + (" on" if c["provider_id"] == st["selected"] else "")}
                                onClick={lambda { acts["select"](c["provider_id"] as str); }}
                            >
                                <span className="rank-top">
                                    <span className="rank-n">{c["provider"]}</span>
                                    <span className="fig rank-e">{(str(c["exposure"]) if top_cited else (pct(c["share"]) + "%"))}</span>
                                </span>
                                <span className="rank-track">
                                    <span
                                        className={"rank-fill" + (" lead" if (c[metric_key] as float) == max_met else "")}
                                        style={{"width": str(round(((c[metric_key] as float) / max_met) * 100)) + "%"}}
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
                            <p className="hot-v">{", ".join(o["vendors_down"] as list)}</p>
                            <span className="hot-k">Features down</span>
                            <p className="hot-v">{", ".join(o["features_down"] as list)}</p>
                            <span className="hot-k">Drafted status update</span>
                            <p className="hot-post">{o["status_post"]}</p>
                        </div>
                    </section>
                    skip;
                }}

                {if not o and len(feature_rows) > 0 {
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

                {if len(st["fallout"] as list) > 0 {
                    <section className="pan">
                        <div className="pan-h"><span><span className="pan-n">07</span><span className="pan-t">Compliance fallout</span></span><span className="pan-meta fig">{str(len(st["fallout"] as list)) + " flagged"}</span></div>
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
}
