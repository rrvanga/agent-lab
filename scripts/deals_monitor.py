#!/usr/bin/env python3
"""Daily deals monitor for a Canada-based PC builder (agent-lab issue #6).

Pulls deals from verified curl-accessible sources, filters them against a
watchlist of GPU/RAM/SSD classes, dedupes, ranks, and prints ONE consolidated
plain-text brief to stdout (delivered to Telegram by a no_agent cron).

Exit code: 0 on success (even with zero deals found — this is a daily brief,
not a silent watchdog). Exit 1 only if EVERY enabled source failed.

Sources:
  - Reddit r/bapcsalescanada RSS  (primary deal feed, Atom XML)
  - Canada Computers              (reuses scripts/price_watch.py verbatim)
  - PCPartPicker single-product   (best-effort hook, anchors default empty)

Stdlib only. Fetch transport = subprocess curl (matches price_watch.py).
"""
import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

RSS_URL = "https://www.reddit.com/r/bapcsalescanada/.rss"

CHROME_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
             "Chrome/126.0 Safari/537.36")

# PCPartPicker anchors: (label, product-page url). Empty until slugs are known.
PPP_ANCHORS = []

# Watchlist classes (RSS matcher). ALL primary tokens must match; for classes
# with a non-empty "secondary" list, at least ONE secondary token must match
# too. Tokens are matched case-insensitively against the lowercased title.
WATCH_CLASSES = {
    "gpu_5070ti": {"primary": ("5070 ti",), "secondary": ()},
    "gpu_5060ti16": {"primary": ("5060 ti", "16gb"), "secondary": ()},
    "gpu_3060": {"primary": ("3060", "12gb"), "secondary": ()},
    "ram_ddr5": {"primary": ("ddr5",), "secondary": ()},
    "ssd_1tb": {
        "primary": ("1tb",),
        "secondary": ("nvme", "ssd", "m.2", "pcie", "samsung", "corsair",
                      "crucial", "kingston", "western", "wd", "seagate",
                      "adata", "sabrent", "lexar", "klevv"),
    },
}

ATOM_NS = {"a": "http://www.w3.org/2005/Atom"}

PRICE_RE = re.compile(r"\$(\d[\d,]*(?:\.\d{2})?)")

SOURCE_LABELS = {"reddit": "Reddit", "cc": "CC", "ppp": "PCPartPicker",
                 "craigslist": "Craigslist"}

_price_watch = None


def load_price_watch():
    """Import scripts/price_watch.py from this file's own directory.

    Resolves relative to __file__ (not CWD) so the monitor runs identically
    from the repo and from ~/.hermes/scripts/. Cached: repeated calls return
    the same module object (so tests can patch its fetch/extract/WATCH).
    """
    global _price_watch
    if _price_watch is None:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "price_watch.py")
        spec = importlib.util.spec_from_file_location("price_watch", path)
        _price_watch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_price_watch)
    return _price_watch


def fetch_curl(url):
    """curl a URL with the Chrome UA; return the body or raise RuntimeError."""
    r = subprocess.run(
        ["curl", "-sL", "--max-time", "25", "-A", CHROME_UA, url],
        capture_output=True, text=True, timeout=40)
    if r.returncode != 0:
        raise RuntimeError(f"curl exit {r.returncode}: {r.stderr[:200]}")
    return r.stdout


def fetch_with_browser(url):
    """Fetch rendered HTML through a real browser (Chrome remote-debugging).

    Requires a one-time manual approval that is NOT yet granted in this
    environment: open chrome://inspect and enable remote debugging on the
    running Chrome instance. Until then this hook is unverified and OFF by
    default (only invoked when --browser-fallback is passed AND curl failed).

    The command run is a browser-use python snippet:

        python3 -c "import asyncio, sys; from browser_use import Agent, Browser;
        async def main():
            browser = Browser(keep_alive=False)
            page = await browser.new_page()
            await page.goto(sys.argv[1])
            print(await page.content())
            await browser.close()
        asyncio.run(main())" <url>

    Returns the rendered HTML string, or None on any subprocess failure.
    """
    code = ("import asyncio, sys; from browser_use import Agent, Browser;\n"
            "async def main():\n"
            " browser = Browser(keep_alive=False)\n"
            " page = await browser.new_page()\n"
            " await page.goto(sys.argv[1])\n"
            " print(await page.content())\n"
            " await browser.close()\n"
            "asyncio.run(main())")
    try:
        r = subprocess.run([sys.executable, "-c", code, url],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            return None
        return r.stdout
    except Exception:
        return None


def parse_iso(text):
    """Parse an ISO-8601 datetime string (aware); return None on failure."""
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_rss(xml_text):
    """Parse an Atom feed; return a list of {title, link, updated, updated_iso}."""
    root = ET.fromstring(xml_text)
    entries = []
    for e in root.findall("a:entry", ATOM_NS):
        title_el = e.find("a:title", ATOM_NS)
        link_el = e.find("a:link", ATOM_NS)
        upd_el = e.find("a:updated", ATOM_NS)
        title = (title_el.text or "") if title_el is not None else ""
        link = link_el.attrib.get("href", "") if link_el is not None else ""
        iso = (upd_el.text or "") if upd_el is not None else ""
        entries.append({
            "title": title,
            "link": link,
            "updated": parse_iso(iso),
            "updated_iso": iso,
        })
    return entries


def extract_price(title):
    """Return the LAST $-prefixed number in title as float, else None.

    Handles "($1599.99-$400 = $1199.99)" -> 1199.99, "[$280/FS]" -> 280.0,
    "$498.99 Costco" -> 498.99. A "$-after-number" (e.g. "1900$") -> None.
    """
    matches = PRICE_RE.findall(title)
    if not matches:
        return None
    try:
        return float(matches[-1].replace(",", ""))
    except ValueError:
        return None


def extract_retailer(title):
    """Return (retailer, in_store) from a title's trailing [retailer] tag.

    Retailer = the last bracketed tag (a trailing unclosed "[MemoryExpress"
    is handled gracefully). "IN-STORE ONLY" is stripped from the name and
    reported via the boolean flag.
    """
    in_store = "in-store only" in title.lower()
    name = None
    trailing = re.search(r"\[([^\]\[]*)$", title)
    if trailing and trailing.group(1).strip():
        name = trailing.group(1)
    else:
        closed = re.findall(r"\[([^\]]*)\]", title)
        if closed:
            name = closed[-1]
    name = (name or "").strip()
    name = re.sub(r"\s*in-store\s+only\s*", "", name, flags=re.IGNORECASE)
    name = name.strip()
    return (name or None, in_store)


def normalize_link(href):
    """Strip utm_* query params from a link (used for RSS dedupe)."""
    if not href or "?" not in href:
        return href
    base, _, query = href.partition("?")
    params = [p for p in query.split("&")
              if not p.lower().startswith("utm_")]
    return base if not params else base + "?" + "&".join(params)


def match_watch_classes(title):
    """Return the list of watch classes whose tokens match the title."""
    t = title.lower()
    hits = []
    for cname, cfg in WATCH_CLASSES.items():
        if all(tok in t for tok in cfg["primary"]):
            if not cfg["secondary"] or any(tok in t for tok in cfg["secondary"]):
                hits.append(cname)
    return hits


def dedupe_by_link(entries):
    """Drop entries whose normalized link was already seen (feed order kept)."""
    seen = set()
    out = []
    for e in entries:
        key = normalize_link(e.get("link", ""))
        if key in seen:
            continue
        seen.add(key)
        out.append(e)
    return out


def filter_by_age(entries, now, days):
    """Skip entries older than `days` from `now` (both timezone-aware)."""
    cutoff = now - timedelta(days=days)
    out = []
    for e in entries:
        upd = e.get("updated")
        if upd is None or upd >= cutoff:
            out.append(e)
    return out


def select_watchlist(entries):
    """Map deduped entries to watchlist matches, one per class (newest first)."""
    matches = []
    seen_class = set()
    for e in entries:
        classes = match_watch_classes(e["title"])
        if not classes:
            continue
        price = extract_price(e["title"])
        retailer, in_store = extract_retailer(e["title"])
        for c in classes:
            if c in seen_class:
                continue
            seen_class.add(c)
            matches.append({
                "class": c,
                "title": e["title"],
                "link": e["link"],
                "updated": e.get("updated_iso", ""),
                "price": price,
                "retailer": retailer,
                "in_store": in_store,
            })
    return matches


def run_rss(fetch_fn=None, now=None, days=2, use_browser=False):
    """Fetch + parse the Reddit feed; return (matches, notes, status)."""
    fetch = fetch_fn or fetch_curl
    now = now or datetime.now(timezone.utc)
    try:
        xml = fetch(RSS_URL)
    except Exception as e:
        xml = fetch_with_browser(RSS_URL) if use_browser else None
        if xml is None:
            return [], [f"Reddit fetch failed: {e}"], "failed"
    try:
        entries = parse_rss(xml)
    except Exception as e:
        return [], [f"Reddit parse failed: {e}"], "failed"
    total = len(entries)
    entries = filter_by_age(entries, now, days)
    entries = dedupe_by_link(entries)
    return select_watchlist(entries), [], f"ok ({total} entries)"


def run_cc(pw=None, fetch_fn=None, min_size=50000, use_browser=False):
    """Reuse price_watch: report cheapest product per watch item + breach.

    Returns (deals, notes, status). Sanity-checked page size; per-item
    failures are recorded in notes, never raised.
    """
    if pw is None:
        pw = load_price_watch()
    fetch = fetch_fn or pw.fetch
    extract = pw.extract
    deals, notes = [], []
    seen = set()
    any_ok = False
    for url, label, tokens, threshold in pw.WATCH:
        raw, err = None, None
        try:
            raw = fetch(url)
        except Exception as e:
            err = str(e)
        if raw is None and use_browser:
            raw = fetch_with_browser(url)
        if raw is None:
            notes.append(f"CC fetch failed for {label}: {err or 'no content'}")
            continue
        if len(raw) < min_size:
            notes.append(f"CC fetch failed for {label}: page suspiciously "
                         f"small ({len(raw)}B)")
            continue
        any_ok = True
        try:
            products = extract(raw)
        except Exception as e:
            notes.append(f"CC parse failed for {label}: {e}")
            continue
        matches = [p for p in products
                   if all(t in p[0].lower() for t in tokens)]
        if not matches:
            continue
        name, price, purl = min(matches, key=lambda p: p[1])
        if purl and purl in seen:
            continue
        if purl:
            seen.add(purl)
        deals.append({
            "label": label, "name": name, "price": price, "url": purl,
            "threshold": threshold, "breach": price <= threshold,
        })
    status = "ok" if any_ok else "failed"
    return deals, notes, status


def extract_ppp_name(html):
    """Product name from <title>, stripped of the " - PCPartPicker" suffix."""
    m = re.search(r"<title>(.*?)</title>", html, re.S)
    if not m:
        return None
    name = re.sub(r"\s+", " ", m.group(1)).strip()
    name = name.replace(" - PCPartPicker", "").strip()
    return name or None


def _to_price(text):
    """Coerce a "$N,NNN" string to float, else None."""
    if text is None:
        return None
    try:
        return float(text.replace(",", "").replace("$", "").strip())
    except (ValueError, AttributeError):
        return None


def extract_ppp_price(html):
    """Robust PPP price: itemprop="price", else inside #prices table, else None.

    Never falls back to the "Completed Builds" totals (class log__price), which
    are NOT the product price.
    """
    m = re.search(r'itemprop="price"', html)
    if m:
        near = html[max(0, m.start() - 250):m.end() + 250]
        cm = re.search(r'content="([^"]+)"', near)
        if cm:
            p = _to_price(cm.group(1))
            if p is not None:
                return p
        after = html[m.end():m.end() + 250]
        pm = PRICE_RE.search(after)
        if pm:
            return _to_price(pm.group(1))
    start = html.find('id="prices"')
    if start != -1:
        ts = html.find("<table", start)
        te = html.find("</table>", ts if ts != -1 else start)
        if ts != -1 and te != -1:
            pm = PRICE_RE.search(html[ts:te])
            if pm:
                return _to_price(pm.group(1))
    return None


def run_ppp(fetch_fn=None, anchors=None, use_browser=False):
    """Best-effort PCPartPicker product fetches; return (deals, notes, status).

    With no anchors configured the source counts as SKIPPED (not failed).
    """
    anchors = PPP_ANCHORS if anchors is None else anchors
    fetch = fetch_fn or fetch_curl
    if not anchors:
        return [], ["PCPartPicker: no anchors configured (slugs pending "
                    "browser approval)"], "skipped (no anchors)"
    deals, notes = [], []
    ok = False
    for label, url in anchors:
        html, err = None, None
        try:
            html = fetch(url)
        except Exception as e:
            err = str(e)
        if html is None and use_browser:
            html = fetch_with_browser(url)
        if html is None:
            notes.append(f"PPP fetch failed for {label}: {err or 'no content'}")
            continue
        ok = True
        deals.append({
            "label": label,
            "name": extract_ppp_name(html),
            "price": extract_ppp_price(html),
            "url": url,
        })
    status = "ok" if ok else "failed"
    return deals, notes, status


def build_report(date, sources, rss, cc, ppp, notes):
    """Assemble the JSON-ready report dict (all values JSON-serializable)."""
    return {
        "date": date,
        "sources": sources,
        "rss": rss,
        "cc": cc,
        "ppp": ppp,
        "notes": notes,
    }


def run_monitor(source="all", days=2, browser_fallback=False, now=None,
                pw=None, rss_fetch=None, cc_fetch=None, ppp_fetch=None):
    """Run all enabled sources; return (report, exit_code)."""
    now_utc = now or datetime.now(timezone.utc)
    now_local = datetime.now()
    enabled = {
        "rss": source in ("rss", "all"),
        "cc": source in ("cc", "all"),
        "ppp": source in ("ppp", "all"),
    }
    sources, notes = {}, []
    rss_matches, cc_deals, ppp_deals = [], [], []

    if enabled["rss"]:
        rss_matches, rss_notes, rss_status = run_rss(
            fetch_fn=rss_fetch, now=now_utc, days=days,
            use_browser=browser_fallback)
        sources["reddit"] = rss_status
        notes.extend(rss_notes)
    else:
        sources["reddit"] = "skipped"

    if enabled["cc"]:
        cc_deals, cc_notes, cc_status = run_cc(
            pw=pw, fetch_fn=cc_fetch, use_browser=browser_fallback)
        sources["cc"] = cc_status
        notes.extend(cc_notes)
    else:
        sources["cc"] = "skipped"

    if enabled["ppp"]:
        ppp_deals, ppp_notes, ppp_status = run_ppp(
            fetch_fn=ppp_fetch, use_browser=browser_fallback)
        sources["ppp"] = ppp_status
        notes.extend(ppp_notes)
    else:
        sources["ppp"] = "skipped"

    sources["craigslist"] = "deprecated (JSON API removed)"

    if browser_fallback:
        notes.append("Browser fallback enabled but unverified (manual Chrome "
                     "approval pending)")
    else:
        notes.append("Browser fallback not configured (manual Chrome approval "
                     "pending)")

    report = build_report(
        date=now_local.strftime("%a %b %d %Y"),
        sources=sources, rss=rss_matches, cc=cc_deals, ppp=ppp_deals,
        notes=notes,
    )

    src_key = {"rss": "reddit", "cc": "cc", "ppp": "ppp"}
    # "Attempted" excludes skipped sources (e.g. PPP with no anchors). Exit 1
    # only when every source we actually tried failed.
    attempted = [n for n in ("rss", "cc", "ppp")
                 if enabled[n] and sources[src_key[n]].split(" ", 1)[0]
                 in ("ok", "failed")]
    all_failed = bool(attempted) and all(
        sources[src_key[n]].startswith("failed") for n in attempted)
    return report, (1 if all_failed else 0)


def _source_symbol(status):
    """Map a source status string to its brief symbol."""
    token = status.split(" ", 1)[0]
    return {"ok": "✓", "failed": "✗", "skipped": "⏭",
            "deprecated": "✗"}.get(token, "?")


def _source_detail(status):
    """Return the human-readable detail suffix of a status string."""
    parts = status.split(" ", 1)
    return parts[1] if len(parts) > 1 else ""


def format_age(iso, now):
    """Render "Xh ago" from an ISO timestamp vs now (guards negative)."""
    dt = parse_iso(iso)
    if dt is None:
        return "?"
    seconds = int((now - dt).total_seconds())
    if seconds < 0:
        return "just now"
    if seconds < 60:
        return f"{seconds}s ago"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m ago"
    hours = minutes // 60
    if hours < 24:
        return f"{hours}h ago"
    return f"{hours // 24}d ago"


def format_brief(report, now=None):
    """Render the consolidated plain-text brief (Telegram-safe)."""
    now = now or datetime.now(timezone.utc)
    lines = [f"🛒 Deals brief — {report['date']}"]
    src_parts = []
    for name in ("reddit", "cc", "ppp", "craigslist"):
        status = report["sources"].get(name, "skipped")
        piece = f"{SOURCE_LABELS[name]} {_source_symbol(status)}"
        detail = _source_detail(status)
        if detail:
            piece += f" {detail}"
        src_parts.append(piece)
    lines.append("Sources: " + " · ".join(src_parts))
    lines.append("")

    lines.append("🔥 r/bapcsalescanada — watchlist matches")
    if not report["rss"]:
        lines.append("(no watchlist matches)")
    for m in report["rss"]:
        line = f"• {m['title']} — {m['link']} ({format_age(m['updated'], now)})"
        if m["price"] is None:
            line += " · price n/a"
        if m["in_store"]:
            line += " · IN-STORE ONLY"
        lines.append(line)
    lines.append("")

    lines.append("💲 Canada Computers street (cheapest per watch)")
    if not report["cc"]:
        lines.append("(no CC products under watch)")
    for d in report["cc"]:
        flag = "BREACH" if d["breach"] else "OK"
        lines.append(f"• {d['label']}: ${d['price']:,.2f} — {d['name']} "
                     f"({d['url']}) [{flag}]")
    lines.append("")

    lines.append("⚠️ Notes")
    if not report["notes"]:
        lines.append("- (none)")
    for n in report["notes"]:
        lines.append(f"- {n}")
    return "\n".join(lines)


def parse_args(argv=None):
    """Parse CLI args."""
    p = argparse.ArgumentParser(description="Daily PC deals monitor brief.")
    p.add_argument("--source", choices=["rss", "cc", "ppp", "all"],
                   default="all", help="which sources to run (default: all)")
    p.add_argument("--json", action="store_true",
                   help="print machine-readable JSON instead of the brief")
    p.add_argument("--browser-fallback", action="store_true",
                   help="use the browser hook when a curl fetch fails")
    p.add_argument("--days", type=int, default=2,
                   help="skip RSS entries older than N days (default: 2)")
    return p.parse_args(argv)


def main(argv=None):
    """CLI entry point; returns the process exit code."""
    args = parse_args(argv)
    report, exit_code = run_monitor(
        source=args.source, days=args.days,
        browser_fallback=args.browser_fallback)
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(format_brief(report))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
