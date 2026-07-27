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

    has domain_in: str = "";
    has manual_in: str = "";
    has search_in: str = "";
    has search_results: list[any] = [];
    has search_loading: bool = False;
    has search_complete: bool = False;
    has search_used_ai: bool = False;
    has search_discovered: bool = False;
    has search_error: str = "";

    async def run_search(allow_discovery: bool) -> None {
        query: str = search_in.strip();
        if not query or search_loading { return; }
        search_loading = True;
        search_complete = False;
        search_used_ai = allow_discovery;
        search_discovered = False;
        search_error = "";
        try {
            payload: any = await acts["search"](
                query,
                allow_discovery
            );
            search_results = (
                payload["results"] as list[any]
                if payload and payload["results"]
                else []
            );
            search_discovered = (
                payload["discovered"] as bool
                if payload
                else False
            );
            search_complete = True;
        } except Exception as e {
            console.error("[blast-radius] search failed", e);
            search_results = [];
            search_error = "Search failed. Check the server and try again.";
            search_complete = True;
        } finally {
            search_loading = False;
        }
    }

    async def submit_registry(e: FormEvent) -> None {
        e.preventDefault();
        await run_search(False);
    }

    async def search_with_ai() -> None {
        await run_search(True);
    }

    async def choose_result(result: any) -> None {
        domain: str = result["domain"] as str;
        if not domain { return; }
        search_loading = True;
        try {
            # Registry rows are read-only offers. A URL-shaped discovery query
            # deliberately misses the seven text tiers, resolves the trusted
            # registry URL, and persists through `_upsert_company`.
            if result["state"] == "registry" {
                mapped: any = await acts["search"](
                    "https://" + domain + "/",
                    True
                );
                search_discovered = (
                    mapped["discovered"] as bool
                    if mapped
                    else False
                );
            }
            await acts["openCompany"](domain);
            search_results = [];
            search_complete = False;
        } except Exception as e {
            console.error("[blast-radius] result load failed", e);
            search_error = "The company was found, but its graph could not be opened.";
        } finally {
            search_loading = False;
        }
    }

    a: any = st["active"];
    o: any = st["outage"];
    h: any = st["headline"];
    cov: any = st["coverage"];
    counts: any = cov["counts"];
    chokes: any = st["chokes"];
    nodes: any = st["nodes"];
    max_exp: float = (chokes[0]["exposure"] as float) if chokes and len(chokes as list) > 0 else 1.0;
    max_share: float = (chokes[0]["share"] as float) if chokes and len(chokes as list) > 0 else 1.0;
    cited: bool = True if chokes and len(chokes as list) > 0 and chokes[0]["downtime_cited"] else False;
    comps: any = st["companies"] or [];
    regions: any = st["regions"] or [];

    src_url: str = "";
    for comp in comps {
        if (comp["domain"] as str) == (st["company_domain"] as str) {
            src_url = ((comp["source_url"] or "") as str);
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

        <section className="finder" aria-label="Company search">
            <div className="finder-copy">
                <span className="finder-k">Search atlas</span>
                <span className="finder-note">Registry first · AI only after a miss</span>
            </div>
            <form className="finder-form" onSubmit={submit_registry}>
                <input
                    className="finder-in"
                    value={search_in}
                    placeholder="Company or domain — e.g. Airbyte"
                    aria-label="Company or domain"
                    onChange={lambda (e: ChangeEvent) {
                        search_in = e.target.value;
                        search_complete = False;
                        search_error = "";
                    }}
                />
                <button
                    className="btn"
                    type="submit"
                    disabled={search_loading or not search_in.strip()}
                >{("Searching…" if search_loading and not search_used_ai else "Search registry")}</button>
                <button
                    className="btn btn-quiet"
                    type="button"
                    onClick={search_with_ai}
                    disabled={search_loading or not search_in.strip()}
                >{("AI searching…" if search_loading and search_used_ai else "Search with AI")}</button>
                {if len(comps as list) > 0 {
                    <select
                        className="finder-sel"
                        value={(st["company_domain"] as str)}
                        aria-label="Active company"
                        onChange={lambda (e: ChangeEvent) { acts["view"]((e.target.value as str)); }}
                    >
                        {for comp in comps {
                            <option key={(comp["domain"] as str)} value={(comp["domain"] as str)}>{comp["name"]}</option>
                        }}
                    </select>
                }}
            </form>
            <div className="finder-status" aria-live="polite">
                {if search_loading {
                    <span>{"Agent checking first-party sources…" if search_used_ai else "Checking graph and registry…"}</span>
                }}
                {if search_error {
                    <span className="finder-bad">{search_error}</span>
                }}
                {if search_complete and not search_loading and len(search_results) == 0 and not search_error {
                    <span>{"No authoritative source found." if search_used_ai else "No registry match. Try Search with AI."}</span>
                }}
                {if search_discovered and not search_loading {
                    <span className="finder-good">New company mapped by discovery.</span>
                }}
            </div>
            {if len(search_results) > 0 {
                <div className="finder-results" role="listbox">
                    {for result in search_results {
                        <button
                            key={(result["id"] as str) + (result["domain"] as str)}
                            className="finder-hit"
                            type="button"
                            onClick={lambda { choose_result(result); }}
                        >
                            <span>
                                <b>{result["name"]}</b>
                                <small>{result["domain"]}</small>
                            </span>
                            <span className="finder-source">
                                <em>{result["match"]}</em>
                                <span>{"Map from registry →" if result["state"] == "registry" else "Open graph →"}</span>
                            </span>
                        </button>
                    }}
                </div>
            }}
        </section>

        {if len(regions as list) > 0 {
            <div className="regions" aria-label="Region filter">
                <button
                    className={"reg-chip" + (" on" if not st["region"] else "")}
                    onClick={lambda { acts["setRegion"](""); }}
                >ALL</button>
                {for rc in regions {
                    <button
                        key={(rc as str)}
                        className={"reg-chip" + (" on" if (rc as str) == (st["region"] as str) else "")}
                        onClick={lambda { acts["setRegion"]((rc as str)); }}
                    >{((rc as str) as any).toUpperCase()}</button>
                }}
            </div>
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
                            <span className="fig met-v">{(str(a["downtime_hours_ytd"]) + "h") if a and a["downtime_cited"] else "—"}</span>
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
                    <div className="pan-h"><span><span className="pan-n">02</span><span className="pan-t">Crawl coverage</span></span><span className="pan-meta fig">{str(cov["done"]) + "/" + str(cov["total"])}{if src_url {<a className="cov-file" href={src_url} target="_blank" rel="noreferrer">{"filing ↗"}</a>}}</span></div>
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
                    <div className="pan-h"><span><span className="pan-n">05</span><span className="pan-t">Chokepoint rank</span></span><span className="pan-meta">{"exposure" if cited else "share"}</span></div>
                    <div className="pan-b">
                        {for c in chokes {
                            <button
                                key={c["provider_id"]}
                                className={"rank" + (" on" if c["provider_id"] == st["selected"] else "")}
                                onClick={lambda { acts["select"](c["provider_id"] as str); }}
                            >
                                <span className="rank-top">
                                    <span className="rank-n">{c["provider"]}</span>
                                    <span className="fig rank-e">{str(c["exposure"]) if cited else (pct(c["share"]) + "%")}</span>
                                </span>
                                <span className="rank-track">
                                    <span
                                        className={"rank-fill" + (" lead" if (cited and c["exposure"] == max_exp) or (not cited and c["share"] == max_share) else "")}
                                        style={{"width": (str(round(((c["exposure"] as float) / max_exp) * 100)) if cited else str(round(((c["share"] as float) / max_share) * 100))) + "%"}}
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
