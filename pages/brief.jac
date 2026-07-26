"""Brief — the written artifact a company owes an auditor. Prose, not a console."""

cl import "./brief.css";

cl {
import from ..risk.store { useRisk }
import from ..risk.ui { LoadState }

glob NL: str = chr(10);

def choke_sentence(c: any) -> str {
    pct = str(round((c["share"] as float) * 100));
    return (c["provider"] as str) + " is a shared dependency for " + str(c["vendors_affected"])
        + " of the organization's vendors, representing " + pct + "% of the observed stack. "
        + "Recorded downtime against this provider totals " + str(c["downtime_hours_ytd"])
        + " hours year-to-date.";
}

def build_report_text(risk: any) -> str {
    st: any = risk["state"];
    text = (st["org_label"] as str) + " — Third-Party Concentration Risk" + NL + NL;

    h: any = st["headline"];
    if h {
        text = text + (h["biggest_risk"] as str) + NL + NL;
    }

    text = text + "Findings" + NL;
    idx = 0;
    for c in st["chokes"] {
        idx = idx + 1;
        text = text + str(idx) + ". " + choke_sentence(c) + " Affected vendors: " + ", ".join(c["names"]) + "." + NL;
    }
    text = text + NL;

    text = text + "Compliance exposure" + NL;
    for f in st["fallout"] {
        text = text + (f["vendor"] as str) + " -> " + (f["provider"] as str) + ": " + (f["reason"] as str) + " " + (f["breaks"] as str) + NL;
    }
    text = text + NL;

    text = text + "Recommended remediation" + NL;
    if h {
        text = text + (h["biggest_suggestion"] as str) + NL;
    }
    return text;
}

def:pub CopyButton() -> JsxElement {
    risk: any = useRisk();
    has copied: bool = False;

    async def handle_copy() {
        text_out = build_report_text(risk);
        await navigator.clipboard.writeText(text_out);
        copied = True;
        setTimeout(lambda { copied = False; }, 1600);
    }

    return <button className="btn btn-quiet brief-copy" onClick={handle_copy}>
        {"Copied" if copied else "Copy as text"}
    </button>;
}

def:pub page() -> JsxPage {
    risk: any = useRisk();
    st: any = risk["state"];
    h: any = st["headline"];
    finding_num: int = 0;

    return <div className="brief">
        <LoadState />
        <article className="brief-doc">
            <div className="brief-head">
                <span className="brief-eyebrow">Third-party concentration risk</span>
                <h1 className="brief-title">{st["org_label"] or "—"}</h1>
                <p className="brief-meta">
                    {"Generated " + str(len(st["chokes"])) + " findings across " + str(st["vendor_total"]) + " vendors and " + str(st["provider_total"]) + " shared providers."}
                </p>
                <CopyButton />
            </div>

            {if h {
                <p className="brief-lead">{h["biggest_risk"]}</p>
                skip;
            }}

            <section className="brief-section">
                <h2 className="brief-h"><span className="brief-n">01</span><span className="brief-t">Findings</span><span className="brief-fill"></span></h2>
                {for c in st["chokes"] {
                    finding_num = finding_num + 1;
                    <div className="brief-finding" key={c["provider"] as str}>
                        <span className="brief-finding-num fig">{str(finding_num)}</span>
                        <div className="brief-finding-body">
                            <h3>{c["provider"] as str}</h3>
                            <p>{choke_sentence(c)}</p>
                            <p className="brief-finding-names">{"Affected: " + ", ".join(c["names"] as list)}</p>
                        </div>
                    </div>
                }}
            </section>

            <section className="brief-section">
                <h2 className="brief-h"><span className="brief-n">02</span><span className="brief-t">Compliance exposure</span><span className="brief-fill"></span></h2>
                {for f in st["fallout"] {
                    <div className="brief-exposure" key={f["vendor"]}>
                        <p className="brief-exposure-pair">{(f["vendor"] as str) + " → " + (f["provider"] as str)}</p>
                        <p className="brief-exposure-reason">{f["reason"]}</p>
                        <p className="brief-exposure-breaks">{f["breaks"]}</p>
                    </div>
                }}
            </section>

            <section className="brief-section brief-remediation">
                <h2 className="brief-h"><span className="brief-n">03</span><span className="brief-t">Recommended remediation</span><span className="brief-fill"></span></h2>
                {if h {
                    <p>{h["biggest_suggestion"]}</p>
                    skip;
                }}
            </section>
        </article>
    </div>;
}
}
