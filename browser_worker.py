"""Fixed Browser Harness worker.

This file is executed by the browser-harness CLI, which injects the CDP helpers.
It is intentionally limited to read-only search, navigation, and text extraction.
"""

import json
import os
from urllib.parse import quote_plus, urlparse


RESULT_PREFIX = "BLAST_RADIUS_BROWSER_RESULT:"
MAX_TEXT = 80_000
MAX_LINKS = 5


def emit(payload):
    print(RESULT_PREFIX + json.dumps(payload, ensure_ascii=False))


def rendered_page():
    return js(
        """(() => {
          const text = (document.body?.innerText || '').slice(0, 80000);
          return {
            final_url: location.href,
            page_text: text,
            relevant: /sub.?process|service provider|subcontractor|data processing addendum|authorized processor/i.test(text)
          };
        })()"""
    )


def click_subprocessors():
    nodes = cdp("Accessibility.getFullAXTree").get("nodes", [])
    for node in nodes:
        name = ((node.get("name") or {}).get("value") or "").strip()
        role = ((node.get("role") or {}).get("value") or "")
        backend_id = node.get("backendDOMNodeId")
        if (
            backend_id
            and role in {"link", "button", "tab", "menuitem"}
            and "subprocessor" in name.casefold().replace("-", "")
        ):
            try:
                quad = cdp(
                    "DOM.getBoxModel",
                    backendNodeId=backend_id,
                )["model"]["content"]
                x = sum(quad[0::2]) / 4
                y = sum(quad[1::2]) / 4
                if x >= 0 and y >= 0:
                    click_at_xy(x, y)
                    wait_for_load()
                    return True
            except Exception:
                continue
    return False


def read_url(task):
    url = task.get("url", "")
    flow_type = task.get("flow_type", "rendered_html_guarded")
    if not url.startswith("https://"):
        emit({"status": "error", "error": "Only HTTPS sources are allowed"})
        return

    new_tab(url)
    wait_for_load()
    if flow_type == "pdf_text":
        emit(
            {
                "status": "unreadable",
                "final_url": page_info().get("url", url),
                "page_text": "",
                "source_urls": [url],
                "error": "Chrome PDF surfaces require a PDF text adapter",
            }
        )
        return

    page = rendered_page()
    if flow_type == "trust_center_clickthrough" or (
        flow_type == "rendered_trust_center"
        and not page.get("relevant", False)
    ):
        click_subprocessors()
        page = rendered_page()

    text = page.get("page_text", "")
    relevant = page.get("relevant", False)
    emit(
        {
            "status": "found" if len(text) >= 200 and relevant else "unreadable",
            "final_url": page.get("final_url", url),
            "page_text": text if relevant else "",
            "source_urls": [page.get("final_url", url)],
            "error": "" if relevant else "No complete subprocessor disclosure rendered",
        }
    )


def search_web(task):
    query = task.get("query", "").strip()
    if not query:
        emit({"status": "error", "error": "Search query is empty"})
        return

    new_tab("https://www.google.com/search?q=" + quote_plus(query))
    wait_for_load()
    links = js(
        """(() => [...document.querySelectorAll('a[href]')]
          .map(a => a.href)
          .filter(href => href.startsWith('https://'))
          .filter(href => {
            try {
              const host = new URL(href).hostname;
              return !host.endsWith('google.com') && host !== 'google.com';
            } catch (_) { return false; }
          })
          .slice(0, 30))()"""
    )
    unique = []
    seen = set()
    for link in links:
        try:
            parsed = urlparse(link)
            canonical = parsed._replace(fragment="").geturl()
        except Exception:
            continue
        if canonical not in seen:
            seen.add(canonical)
            unique.append(canonical)
        if len(unique) >= MAX_LINKS:
            break
    emit(
        {
            "status": "found" if unique else "notfound",
            "source_urls": unique,
            "final_url": page_info().get("url", ""),
            "page_text": "",
            "error": "" if unique else "No public search results",
        }
    )


def main():
    try:
        task = json.loads(os.environ.get("BLAST_RADIUS_BROWSER_TASK", "{}"))
        action = task.get("action", "")
        if action == "read":
            read_url(task)
        elif action == "search":
            search_web(task)
        else:
            emit({"status": "error", "error": f"Unsupported action: {action}"})
    except Exception as exc:
        emit({"status": "error", "error": str(exc)[:500]})


main()
