"""Bounded Browser Harness adapter and authoritative-source validation."""

import asyncio;
import json;
import os;
import re;
import subprocess;
import from pathlib { Path }
import from urllib.parse { urlparse }


obj BrowserPageResult {
    has status: str = "error";
    has final_url: str = "";
    has page_text: str = "";
    has source_urls: list[str] = [];
    has error: str = "";
}


glob BROWSER_RESULT_PREFIX: str = "BLAST_RADIUS_BROWSER_RESULT:";
glob BROWSER_WORKER_PATH: Path = Path("browser_worker.py");


def normalize_identity(value: str) -> str {
    return re.sub(r"[^a-z0-9]+", "", value.casefold());
}


def normalize_company_domain(domain: str) -> str {
    value: str = domain.strip().casefold();
    if "://" in value {
        value = urlparse(value).hostname or "";
    } else {
        value = value.split("/", 1)[0];
    }
    return value.removeprefix("www.").rstrip(".");
}


def is_authoritative_source(
    url: str,
    company_domain: str,
    company_keyword: str
) -> bool {
    parsed = urlparse(url);
    host: str = (parsed.hostname or "").casefold().removeprefix("www.");
    normalized_domain: str = normalize_company_domain(company_domain);
    if (
        normalized_domain
        and (host == normalized_domain or host.endswith("." + normalized_domain))
    ) {
        return True;
    }
    if host != "github.com" {
        return False;
    }
    parts: list[str] = [
        part for part in parsed.path.split("/") if part
    ];
    if len(parts) < 2 {
        return False;
    }
    organization: str = normalize_identity(parts[0]);
    keyword_key: str = normalize_identity(company_keyword);
    domain_key: str = normalize_identity(
        normalized_domain.split(".", 1)[0] if normalized_domain else ""
    );
    path_key: str = normalize_identity(parsed.path);
    identity_matches: bool = (
        organization == keyword_key
        or organization == domain_key
        or (keyword_key != "" and organization in keyword_key)
    );
    disclosure_matches: bool = (
        "subprocessor" in path_key
        or "subprocessors" in path_key
        or "dpa" in path_key
        or "privacy" in path_key
    );
    return identity_matches and disclosure_matches;
}


def _string_field(raw: dict[str, object], key: str) -> str {
    value = raw.get(key);
    return value if isinstance(value, str) else "";
}


def _string_list_field(
    raw: dict[str, object],
    key: str
) -> list[str] {
    value = raw.get(key);
    if not isinstance(value, list) {
        return [];
    }
    return [item for item in value if isinstance(item, str)];
}


def parse_browser_worker_output(stdout: str) -> BrowserPageResult {
    for line in reversed(stdout.splitlines()) {
        if not line.startswith(BROWSER_RESULT_PREFIX) {
            continue;
        }
        try {
            raw_obj = json.loads(
                line.removeprefix(BROWSER_RESULT_PREFIX)
            ) as object;
            if not isinstance(raw_obj, dict) {
                break;
            }
            raw = raw_obj as dict[str, object];
            return BrowserPageResult(
                status=_string_field(raw, "status") or "error",
                final_url=_string_field(raw, "final_url"),
                page_text=_string_field(raw, "page_text"),
                source_urls=_string_list_field(raw, "source_urls"),
                error=_string_field(raw, "error")
            );
        } except json.JSONDecodeError {
            break;
        }
    }
    return BrowserPageResult(
        status="error",
        error="Browser Harness returned no typed result"
    );
}


def _run_browser_worker(
    task: dict[str, str],
    timeout_seconds: int
) -> BrowserPageResult {
    if not BROWSER_WORKER_PATH.exists() {
        return BrowserPageResult(
            status="error",
            error=f"Missing Browser Harness worker: {BROWSER_WORKER_PATH}"
        );
    }
    worker_env = os.environ.copy();
    worker_env["BLAST_RADIUS_BROWSER_TASK"] = json.dumps(task);
    try {
        completed = subprocess.run(
            ["browser-harness"],
            input=BROWSER_WORKER_PATH.read_text(),
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            env=worker_env,
            check=False
        );
    } except subprocess.TimeoutExpired {
        return BrowserPageResult(
            status="error",
            error=f"Browser Harness exceeded {timeout_seconds}s"
        );
    } except OSError as exc {
        return BrowserPageResult(
            status="error",
            error=f"Browser Harness failed to start: {str(exc)}"
        );
    }

    stdout: str = getattr(completed, "stdout", "") as str;
    stderr: str = getattr(completed, "stderr", "") as str;
    result: BrowserPageResult = parse_browser_worker_output(stdout);
    if result.status == "error" and not result.error and stderr {
        result.error = stderr[-500:];
    }
    return result;
}


async def browser_read_url(
    url: str,
    flow_type: str = "rendered_html_guarded",
    timeout_seconds: int = 45
) -> BrowserPageResult {
    task: dict[str, str] = {
        "action": "read",
        "url": url,
        "flow_type": flow_type
    };
    result = await asyncio.to_thread(
        _run_browser_worker,
        task,
        timeout_seconds
    );
    return result as BrowserPageResult;
}


def browser_search(query: str) -> list[str] {
    result = _run_browser_worker(
        {"action": "search", "query": query},
        30
    );
    return result.source_urls if result.status == "found" else [];
}


def browser_search_github(query: str) -> list[str] {
    return browser_search(f"site:github.com {query}");
}


def browser_read(url: str) -> str {
    result = _run_browser_worker(
        {
            "action": "read",
            "url": url,
            "flow_type": "rendered_html_guarded"
        },
        45
    );
    return result.page_text if result.status == "found" else "";
}
