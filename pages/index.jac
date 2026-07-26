"""Landing — the front door. Swiss editorial memo; the working app lives at /atlas."""

cl import "./index.css";
cl import from "@jac/runtime" { useNavigate }

cl {
import from ..risk.store { useRisk }
import from ..risk.MiniGraph { MiniGraph }

glob COMPANIES: list[any] = [
    {"domain": "jachammer.ai", "label": "jachammer.ai"},
    {"domain": "openai.com", "label": "OpenAI"},
    {"domain": "anthropic.com", "label": "Anthropic"},
    {"domain": "composio.dev", "label": "Composio"},
    {"domain": "stripe.com", "label": "Stripe"},
    {"domain": "notion.so", "label": "Notion"},
    {"domain": "vercel.com", "label": "Vercel"},
    {"domain": "linear.app", "label": "Linear"}
];

def pct(share: any) -> str {
    return str(round((share as float) * 100));
}

def:pub page() -> JsxPage {
    risk: any = useRisk();
    nav: any = useNavigate();
    st: any = risk["state"];
    acts: any = risk["actions"];
    meta: any = risk["meta"];

    has picked: str = "jachammer.ai";

    headline: any = st["headline"];
    fallout: any = st["fallout"];
    top: any = st["top"];
    org_label: any = st["org_label"] or "the mapped org";

    clause_num: int = 0;

    def open_atlas() -> None {
        acts["ingest"](picked);
        nav("/atlas");
    }

    return <div className="memo">
        <div className="memo-grid" aria-hidden="true"></div>
        <div className="memo-wrap">

            <header className="m-mast-top">
                <span className="m-docno"><span className="m-redsq"></span>TECHNICAL MEMORANDUM - SUPPLY-CHAIN RISK</span>
                <span>JACKHACKS - JUL 2026</span>
                <span>TRACK: AGENTIC AI + JAC</span>
            </header>
            <div className="m-rule"></div>

            <h1 className="m-display">BLAST RADIUS<span className="m-dot"></span></h1>
            <div className="m-rule m-rule-thin"></div>

            {if meta["loading"] {
                <div className="m-loading">READING SUBPROCESSOR FILINGS...</div>
                skip;
            }}

            <section className="m-deck">
                <div className="m-deck-lede">
                    {if top {
                        <p>
                            {"Your vendors have vendors. One of them is carrying "}
                            <span className="m-red">{pct(top["share"]) + "%"}</span>
                            {" of your stack."}
                        </p>
                        skip;
                    }}
                    {if not top {
                        <p>Your vendors have vendors. We map who is really carrying your stack.</p>
                        skip;
                    }}
                </div>
                <div className="m-deck-desc">
                    <p>Blast Radius reads every vendor's own subprocessor filings to build the second layer of
                    your SaaS stack, surfaces the single provider your "redundant" tools secretly share, and
                    turns that concentration into a risk memo, a live outage simulation, and a compliance-fallout
                    report — no survey, no guesswork.</p>
                </div>
            </section>

            <section className="m-section">
                <div className="m-shead">
                    <span className="m-snum">01</span>
                    <span className="m-stitle">DEPENDENCY DIAGRAM</span>
                    <span className="m-sfill"></span>
                </div>

                <div className="m-diagram-ctrl">
                    <select className="m-select" value={picked} onChange={lambda (e: any) { picked = e.target.value; }}>
                        {for c in COMPANIES {
                            <option key={c["domain"]} value={c["domain"]}>{c["label"]}</option>
                        }}
                    </select>
                    <button className="btn" onClick={lambda { open_atlas(); }}>Open in Atlas</button>
                </div>

                <div className="m-figure">
                    <MiniGraph />
                    {if meta["loading"] {
                        <div className="loadstate">READING SUBPROCESSOR FILINGS...</div>
                        skip;
                    }}
                </div>
                <p className="m-caption">
                    <em>{"Figure 1 - second-layer dependency map of " + (org_label as str) + "."}</em>
                    {" The shape is drawn from the vendors' own disclosed subprocessor lists, not a survey."}
                </p>
            </section>

            <section className="m-section">
                <div className="m-shead">
                    <span className="m-snum">02</span>
                    <span className="m-stitle">ONE-LOOK ASSESSMENT</span>
                    <span className="m-sfill"></span>
                </div>
                {if headline {
                    <div className="m-quote-grid">
                        <div className="m-qmark">&#8220;</div>
                        <blockquote>{headline["biggest_risk"]}</blockquote>
                        <div className="m-reco">
                            <span className="m-rlabel">RECOMMENDATION</span>
                            <p>{headline["biggest_suggestion"]}</p>
                        </div>
                    </div>
                    skip;
                }}
                {if not headline {
                    <p className="m-empty">Assessment pending — waiting on subprocessor filings.</p>
                    skip;
                }}
            </section>

            <section className="m-section">
                <div className="m-shead">
                    <span className="m-snum">03</span>
                    <span className="m-stitle">COMPLIANCE FALLOUT</span>
                    <span className="m-sfill"></span>
                </div>
                <div className="m-clauses">
                    {for f in fallout {
                        clause_num = clause_num + 1;
                        <div className="m-clause" key={f["vendor"]}>
                            <span className="m-cno">{"3." + str(clause_num)}</span>
                            <span className="m-ctext"><span className="m-bold">{f["vendor"]}</span>{" -> "}<span className="m-bold">{f["provider"]}</span>{": " + (f["reason"] as str) + " " + (f["breaks"] as str)}</span>
                            <span className="m-ctag">{"PII EXPOSURE PATH" if f["handles_pii"] else "COMPLIANCE GAP INHERITED"}</span>
                        </div>
                    }}
                    {if len(fallout as list) == 0 {
                        <p className="m-empty">No compliance fallout recorded yet.</p>
                        skip;
                    }}
                </div>
            </section>

            <footer className="m-foot">
                <span className="m-foot-sig">BLAST RADIUS - YOUR VENDORS HAVE VENDORS.</span>
                <span>SET IN ARCHIVO &amp; IBM PLEX MONO</span>
                <span>END OF MEMORANDUM</span>
            </footer>
        </div>
    </div>;
}
}
