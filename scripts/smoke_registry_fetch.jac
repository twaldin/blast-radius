"""Live Browser Harness smoke test for one curated registry entry."""

import argparse;
import asyncio;
import from extract { fetch_page, resolve_url }


def parse_args -> argparse.Namespace {
    parser = argparse.ArgumentParser();
    _ = parser.add_argument(
        "domain",
        nargs="?",
        `default="stripe.com",
        help="Curated registry domain to render."
    );
    return parser.parse_args();
}


async def smoke(domain: str) -> int {
    url: str = await resolve_url(domain);
    if not url {
        print(f"notfound domain={domain}");
        return 1;
    }
    page_text: str = await fetch_page(url);
    if not page_text {
        print(f"unreadable domain={domain} url={url}");
        return 2;
    }
    print(
        f"ok domain={domain} url={url} rendered_chars={len(page_text)}"
    );
    return 0;
}


with entry:__main__ {
    args = parse_args();
    raise SystemExit(
        asyncio.run(smoke(args.domain as str))
    );
}
