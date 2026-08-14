# Deals Monitor — source matrix & status

`scripts/deals_monitor.py` is the daily deals brief for the PC builder
(agent-lab issue #6). It pulls from verified curl-accessible sources, filters
to a GPU/RAM/SSD watchlist, dedupes, ranks, and prints ONE consolidated
plain-text brief to stdout for a no_agent cron → Telegram.

Run: `python3 scripts/deals_monitor.py [--source rss|cc|ppp|all] [--json]
[--browser-fallback] [--days N]`

## Source matrix (verified 2026-08-14)

| Source | Status | Transport | Notes |
| --- | --- | --- | --- |
| Reddit r/bapcsalescanada RSS | ✅ VERIFIED | subprocess curl, Chrome UA (Atom XML) | Primary deal feed. Retailer-filtered titles. |
| Canada Computers | ✅ VERIFIED | reuses `scripts/price_watch.py` (`fetch`/`extract`/`WATCH`) | PrestaShop `product-miniature` blocks, `data-price`. |
| PCPartPicker (product pages) | ✅ VERIFIED | subprocess curl + regex | Single-product pages only; category/search are JS-only. Anchors empty (slugs pending). |
| Memory Express | ⛔ BLOCKED | — | Cloudflare. Covered indirectly via RSS posts. |
| Best Buy CA | ⛔ BLOCKED | — | Akamai. Covered indirectly via RSS posts. |
| Craigslist | ⛔ DEPRECATED | — | `format=json` removed; returns HTML. Skipped, reported in brief. |

## Watch classes (RSS matcher, case-insensitive)

| Class | Primary (all) | Secondary (any) |
| --- | --- | --- |
| `gpu_5070ti` | `5070 ti` | — |
| `gpu_5060ti16` | `5060 ti`, `16gb` | — |
| `gpu_3060` | `3060`, `12gb` | — |
| `ram_ddr5` | `ddr5` | — |
| `ssd_1tb` | `1tb` | `nvme`, `ssd`, `m.2`, `pcie`, `samsung`, `corsair`, `crucial`, `kingston`, `western`, `wd`, `seagate`, `adata`, `sabrent`, `lexar`, `klevv` |

## Rules

- **Price**: last `$`-prefixed number in a title (`($1599.99-$400 = $1199.99)` →
  `1199.99`); no `$`-prefix → `price n/a`.
- **Retailer**: last bracketed tag; `IN-STORE ONLY` stripped to a flag.
- **Dedupe**: RSS by normalized link (strip `utm_*`); CC by product URL;
  each watch class listed at most once per day.
- **Age**: RSS entries older than `--days` (default 2) are skipped.
- **Exit code**: 0 on success (even with zero deals); 1 only if every
  attempted source failed. Per-source failures go in the Notes section.

## Browser fallback (unverified)

`fetch_with_browser()` shells out to a documented `browser-use` snippet that
prints rendered HTML. It is OFF by default and only invoked when
`--browser-fallback` is passed **and** a source failed curl. It requires a
one-time manual approval (`chrome://inspect` → enable remote debugging) that is
pending for this environment, so its status is reported honestly in the
Notes section rather than asserted in code.

## Tests

`python3 -m unittest discover -s tests -v` — 43 tests, stdlib `unittest`,
no network (fixtures only).
