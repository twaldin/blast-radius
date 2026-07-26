"""Shared chrome. The provider lives here so every view reads one crawl."""

import "./base.css";
import from "@jac/runtime" { Outlet, Link, useLocation }
import from ..risk.store { RiskProvider, useRisk }

def:pub ViewNav() -> JsxElement {
    here: any = useLocation();
    path: str = here["pathname"] as str;

    return <nav className="views">
        <Link to="/" className={"on" if path == "/" else ""}>Memo</Link>
        <Link to="/atlas" className={"on" if path == "/atlas" else ""}>Atlas</Link>
        <Link to="/brief" className={"on" if path == "/brief" else ""}>Brief</Link>
    </nav>;
}

def:pub Scope() -> JsxElement {
    risk: any = useRisk();
    st: any = risk["state"];
    meta: any = risk["meta"];

    if not st["org_label"] {
        return <span className="chrome-scope">{"Reading filings…" if meta["crawling"] else "No graph"}</span>;
    }

    return <span className="chrome-scope">
        <b>{st["org_label"]}</b>
        <span>{str(st["vendor_total"]) + " vendors · " + str(st["provider_total"]) + " providers"}</span>
        {st["top"] and <span>{"chokepoint " + (st["top"]["provider"] as str)}</span>}
    </span>;
}

def:pub layout() -> JsxLayout {
    return <RiskProvider>
        <div className="shell">
            <header className="chrome">
                <span className="chrome-mark"><span className="chrome-sq"></span>Blast Radius</span>
                <Scope />
                <ViewNav />
            </header>
            <main className="view">
                <Outlet />
            </main>
        </div>
    </RiskProvider>;
}
