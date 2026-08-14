#!/usr/bin/env python3
"""PC parts price watchdog — Canada Computers.

Silent unless a watched part drops at/below its target price; then prints a
Telegram-ready alert. Exit 0 always (unless a fetch fails -> non-zero exit so
the scheduler raises an error alert and the watchdog can't fail silently).

Watchlist (targets = alert thresholds):
  - RTX 5070 Ti 16GB            <= $1,499.99   (CC street floor ~$1,670)
  - RTX 5060 Ti 16GB            <= $1,099.99   (CC floor $1,119.99 ASUS Dual OC)
  - 32GB DDR5-6000+ kit         <= $549.99     (street ~$570-690, DRAM supercycle)
  - 1TB NVMe Gen4               <= $199.99     (Kingston NV3 at $229.99)

Recipe: sitemap-derived CC category IDs + PrestaShop product-miniature blocks
+ data-price="$X.XX" attribute. See web-price-research skill.
"""
import re
import subprocess
import sys
from datetime import date

CHROME_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
             "Chrome/126.0 Safari/537.36")

# (url, title, match-tokens, price-threshold)
# match-tokens: ALL must appear (case-insensitive) in the product name.
WATCH = [
    ("https://www.canadacomputers.com/en/914/graphics-cards",
     "RTX 5070 Ti", ("5070 ti",), 1499.99),
    ("https://www.canadacomputers.com/en/914/graphics-cards",
     "RTX 5060 Ti 16GB", ("5060 ti", "16gb"), 1099.99),
    ("https://www.canadacomputers.com/en/1022/desktop-memory",
     "32GB DDR5 6000+", ("2x16gb", "ddr5"), 549.99),
    ("https://www.canadacomputers.com/en/1291/desktop-laptop-internal-ssds",
     "1TB NVMe", ("1tb", "nvme"), 199.99),
]


def fetch(url):
    """curl a page; return (status, html) or raise."""
    r = subprocess.run(
        ["curl", "-sL", "--max-time", "25", "-A", CHROME_UA, url],
        capture_output=True, text=True, timeout=40)
    if r.returncode != 0:
        raise RuntimeError(f"curl exit {r.returncode}: {r.stderr[:200]}")
    return r.stdout


def extract(raw):
    """Split PrestaShop product-miniature blocks; return [(name, price, url)]."""
    out = []
    # CC renders class="product-miniature js-product-miniature" (extra class)
    # and the tag spans multiple lines — use a tolerant lookahead.
    for b in re.split(r'(?=<article class="product-miniature\b)', raw)[1:]:
        tm = re.search(
            r'<h2 class="h3 product-title[^"]*"[^>]*><a[^>]*>(.*?)</a>', b, re.S)
        pm = re.search(r'data-price="\$([\d,]+\.?\d*)"', b)
        um = re.search(r'href="(https://www.canadacomputers.com/en/[^"]+)"', b)
        if not (tm and pm):
            continue
        name = re.sub(r"\s+", " ", tm.group(1)).strip()
        try:
            price = float(pm.group(1).replace(",", ""))
        except ValueError:
            continue
        out.append((name, price, um.group(1) if um else ""))
    return out


def main():
    alerts = []
    for url, label, tokens, threshold in WATCH:
        try:
            raw = fetch(url)
        except Exception as e:
            # Non-zero exit -> scheduler sends an error alert. Never silent-fail.
            print(f"⚠️ Price watchdog fetch FAILED for {label}: {e}", file=sys.stderr)
            sys.exit(1)
        if len(raw) < 50_000:
            # 200-but-wrong-content trap: CC serves junk for bad URLs. Flag it.
            print(f"⚠️ Price watchdog: {label} page suspiciously small "
                  f"({len(raw)}B) — check category ID.", file=sys.stderr)
            sys.exit(1)
        seen = set()
        for name, price, purl in extract(raw):
            nl = name.lower()
            if not all(t in nl for t in tokens):
                continue
            if purl in seen:  # dedupe variant repeats
                continue
            seen.add(purl)
            if price <= threshold:
                alerts.append((name, price, purl, label, threshold))

    if not alerts:
        return  # silent — nothing under target

    print(f"💲 Price alert — {date.today().isoformat()} (Canada Computers, verified today)")
    for name, price, purl, label, threshold in alerts:
        print(f"\n{name}\n  ${price:,.2f}  (target ≤ ${threshold:,.2f})\n  {purl}")


if __name__ == "__main__":
    main()
