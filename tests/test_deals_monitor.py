"""Unit tests for scripts/deals_monitor.py.

Stdlib unittest only. No network access — every source is stubbed or backed by
the checked-in fixtures under tests/fixtures/.
"""
import json
import os
import sys
import types
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "scripts"))

import deals_monitor

HERE = os.path.dirname(os.path.abspath(__file__))
RSS_FIXTURE = os.path.join(HERE, "fixtures", "rss_sample.xml")
PPP_FIXTURE = os.path.join(HERE, "fixtures", "ppp_product_sample.html")

AWARE_NOW = datetime(2026, 8, 14, 16, 0, 0, tzinfo=timezone.utc)


def read_fixture(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class RssParseTest(unittest.TestCase):
    def setUp(self):
        self.entries = deals_monitor.parse_rss(read_fixture(RSS_FIXTURE))

    def test_parses_25_entries(self):
        self.assertEqual(len(self.entries), 25)

    def test_entry_shape(self):
        e = self.entries[0]
        for key in ("title", "link", "updated", "updated_iso"):
            self.assertIn(key, e)
        self.assertIsInstance(e["updated"], datetime)
        self.assertIsNotNone(e["updated"].tzinfo)

    def test_updated_is_aware_datetime(self):
        self.assertIsNotNone(self.entries[2]["updated"].tzinfo)


class WatchClassTest(unittest.TestCase):
    def test_msi_laptop_matches_gpu_and_ram(self):
        title = ("[Laptop] MSI Vector A16 HX 16GB DDR5 GeForce RTX 5070 Ti "
                 "8840HX 16in 240Hz ($3000-900=$2100) [MemoryExpress")
        self.assertEqual(set(deals_monitor.match_watch_classes(title)),
                         {"gpu_5070ti", "ram_ddr5"})

    def test_samsung_ssd_matches(self):
        title = ("[NVMe] SAMSUNG SSD 9100 PRO 1TB - PCIe 5.0 14,800MB/s "
                 "($465 - $190 = $275) [Newegg.ca]")
        self.assertEqual(deals_monitor.match_watch_classes(title), ["ssd_1tb"])

    def test_ibuypower_prebuild_matches_ssd(self):
        title = ("[Prebuild] IBUYPOWER EBI7N5703 GAMING DESKTOP5i Intel Core "
                 "Ultra 7-265F, 32GB RAM, 1TB SSD RTX 5070 1900$ OPEN BOX "
                 "GRADE A [SURPLUS BY DESIGN].")
        self.assertEqual(deals_monitor.match_watch_classes(title), ["ssd_1tb"])

    def test_rx9070_negative(self):
        title = ("[GPU] - ASUS Prime Radeon RX 9070 OC IN-STORE ONLY "
                 "($849.99) [Canada Computers]")
        self.assertEqual(deals_monitor.match_watch_classes(title), [])

    def test_general_discussion_negative(self):
        title = ("/r/BuildAPCSalesCanada General Discussion - Daily Thread "
                 "for Fri Aug 14")
        self.assertEqual(deals_monitor.match_watch_classes(title), [])

    def test_case_insensitive(self):
        title = "RTX 5070 TI and DDR5 kit"
        self.assertEqual(set(deals_monitor.match_watch_classes(title)),
                         {"gpu_5070ti", "ram_ddr5"})


class PriceExtractTest(unittest.TestCase):
    def test_last_dollar_prefixed_wins(self):
        self.assertEqual(
            deals_monitor.extract_price("($1599.99-$400 = $1199.99)"), 1199.99)

    def test_bracketed_price(self):
        self.assertEqual(deals_monitor.extract_price("[$280/FS]"), 280.0)

    def test_trailing_price(self):
        self.assertEqual(deals_monitor.extract_price("$498.99 Costco"), 498.99)

    def test_no_comma_separator(self):
        self.assertEqual(deals_monitor.extract_price("$3000-900=$2100"), 2100.0)

    def test_dollar_after_number_is_none(self):
        self.assertIsNone(deals_monitor.extract_price("1900$"))

    def test_no_price_is_none(self):
        self.assertIsNone(deals_monitor.extract_price("no price here"))

    def test_samsung_275(self):
        self.assertEqual(
            deals_monitor.extract_price("($465 - $190 = $275)"), 275.0)


class RetailerExtractTest(unittest.TestCase):
    def test_memory_express(self):
        self.assertEqual(
            deals_monitor.extract_retailer("[GPU] X [Memory Express]"),
            ("Memory Express", False))

    def test_canada_computers(self):
        self.assertEqual(
            deals_monitor.extract_retailer("[GPU] X ($849.99) "
                                           "[Canada Computers]"),
            ("Canada Computers", False))

    def test_in_store_flag(self):
        self.assertEqual(
            deals_monitor.extract_retailer("[GPU] X IN-STORE ONLY ($849.99) "
                                           "[Canada Computers]"),
            ("Canada Computers", True))

    def test_in_store_inside_bracket_stripped(self):
        self.assertEqual(
            deals_monitor.extract_retailer("[GPU] X [Canada Computers "
                                           "IN-STORE ONLY]"),
            ("Canada Computers", True))

    def test_unclosed_bracket_does_not_crash(self):
        title = ("[Laptop] MSI Vector A16 HX 16GB DDR5 GeForce RTX 5070 Ti "
                 "8840HX 16in 240Hz ($3000-900=$2100) [MemoryExpress")
        name, in_store = deals_monitor.extract_retailer(title)
        self.assertEqual(name, "MemoryExpress")
        self.assertFalse(in_store)

    def test_no_bracket(self):
        self.assertEqual(
            deals_monitor.extract_retailer("No brackets here"), (None, False))


class LinkNormalizeTest(unittest.TestCase):
    def test_utm_stripped(self):
        self.assertEqual(
            deals_monitor.normalize_link("https://x/y?utm_source=a&utm_medium=b"),
            "https://x/y")

    def test_mixed_params(self):
        self.assertEqual(
            deals_monitor.normalize_link("https://x/y?id=3&utm_source=a"),
            "https://x/y?id=3")

    def test_no_query(self):
        self.assertEqual(deals_monitor.normalize_link("https://x/y"),
                         "https://x/y")


class DedupeTest(unittest.TestCase):
    def test_dedupe_by_link(self):
        entries = [
            {"title": "a", "link": "https://x/1", "updated": None,
             "updated_iso": ""},
            {"title": "b", "link": "https://x/1", "updated": None,
             "updated_iso": ""},
            {"title": "c", "link": "https://x/2", "updated": None,
             "updated_iso": ""},
        ]
        self.assertEqual(len(deals_monitor.dedupe_by_link(entries)), 2)

    def test_dedupe_normalizes_utm(self):
        entries = [
            {"title": "a", "link": "https://x/1?utm_source=s", "updated": None,
             "updated_iso": ""},
            {"title": "b", "link": "https://x/1?utm_medium=m", "updated": None,
             "updated_iso": ""},
        ]
        self.assertEqual(len(deals_monitor.dedupe_by_link(entries)), 1)


class AgeFilterTest(unittest.TestCase):
    def test_older_than_days_skipped(self):
        entries = deals_monitor.parse_rss(read_fixture(RSS_FIXTURE))
        filtered = deals_monitor.filter_by_age(entries, AWARE_NOW, days=2)
        # 9 of 25 fixture entries are older than 2026-08-12T16:00Z.
        self.assertEqual(len(filtered), 16)
        self.assertTrue(any("SAMSUNG" in e["title"] for e in filtered))
        self.assertFalse(any("MSI Vector" in e["title"] for e in filtered))


class SelectWatchlistTest(unittest.TestCase):
    def test_once_per_class_per_day(self):
        entries = deals_monitor.parse_rss(read_fixture(RSS_FIXTURE))
        matches = deals_monitor.select_watchlist(entries)
        classes = [m["class"] for m in matches]
        self.assertEqual(set(classes),
                         {"gpu_5070ti", "ram_ddr5", "ssd_1tb"})
        self.assertEqual(len(matches), 3)  # ssd_1tb deduped to one entry
        by_class = {m["class"]: m for m in matches}
        # Newest ssd_1tb match is the Samsung 9100 PRO (not the IBUYPOWER).
        self.assertIn("SAMSUNG", by_class["ssd_1tb"]["title"])
        self.assertEqual(by_class["ssd_1tb"]["price"], 275.0)
        # MSI laptop is the gpu_5070ti / ram_ddr5 match, price from last $.
        self.assertEqual(by_class["gpu_5070ti"]["price"], 2100.0)
        self.assertEqual(by_class["ram_ddr5"]["title"],
                         by_class["gpu_5070ti"]["title"])
        self.assertEqual(by_class["gpu_5070ti"]["retailer"], "MemoryExpress")


class PriceWatchImportTest(unittest.TestCase):
    def test_imports_and_caches(self):
        pw = deals_monitor.load_price_watch()
        self.assertEqual(len(pw.WATCH), 4)
        self.assertTrue(callable(pw.fetch))
        self.assertTrue(callable(pw.extract))
        self.assertIs(deals_monitor.load_price_watch(), pw)


def _fake_pw(watch, products):
    return types.SimpleNamespace(
        WATCH=watch,
        fetch=lambda url: "x",
        extract=lambda raw: products,
    )


class CanadaComputersTest(unittest.TestCase):
    def test_cheapest_per_watch_and_breach(self):
        products = [
            ("GIGABYTE RTX 5070 Ti Gaming OC 16GB", 1499.99,
             "https://cc/p1"),
            ("MSI RTX 5070 Ti Ventus 3X", 1550.00, "https://cc/p2"),
            ("ASUS Dual RTX 5060 Ti 16GB OC", 1119.99, "https://cc/p3"),
            ("ASUS Dual RTX 5060 Ti 8GB", 999.99, "https://cc/p4"),
        ]
        pw = _fake_pw([
            ("u1", "RTX 5070 Ti", ("5070 ti",), 1499.99),
            ("u1", "RTX 5060 Ti 16GB", ("5060 ti", "16gb"), 1099.99),
            ("u2", "32GB DDR5 6000+", ("2x16gb", "ddr5"), 549.99),
            ("u3", "1TB NVMe", ("1tb", "nvme"), 199.99),
        ], products)
        deals, notes, status = deals_monitor.run_cc(pw=pw, min_size=0)
        self.assertEqual(status, "ok")
        self.assertEqual(notes, [])
        self.assertEqual(len(deals), 2)
        self.assertEqual(deals[0]["label"], "RTX 5070 Ti")
        self.assertEqual(deals[0]["price"], 1499.99)
        self.assertTrue(deals[0]["breach"])  # 1499.99 <= 1499.99
        self.assertEqual(deals[1]["label"], "RTX 5060 Ti 16GB")
        self.assertEqual(deals[1]["price"], 1119.99)
        self.assertFalse(deals[1]["breach"])  # 1119.99 > 1099.99
        self.assertEqual(deals[1]["url"], "https://cc/p3")

    def test_dedupe_by_url(self):
        pw = _fake_pw([
            ("u", "Label A", ("5070 ti",), 1500.00),
            ("u", "Label B", ("5070 ti",), 1499.00),
        ], [("RTX 5070 Ti OC", 1499.99, "https://cc/same")])
        deals, _, _ = deals_monitor.run_cc(pw=pw, min_size=0)
        self.assertEqual(len(deals), 1)

    def test_fetch_failure_reported_not_raised(self):
        def boom(url):
            raise RuntimeError("boom")

        pw = types.SimpleNamespace(
            WATCH=[("u", "Label", ("5070 ti",), 1.0)],
            fetch=boom,
            extract=lambda raw: [],
        )
        deals, notes, status = deals_monitor.run_cc(pw=pw, min_size=0)
        self.assertEqual(status, "failed")
        self.assertEqual(deals, [])
        self.assertTrue(any("boom" in n for n in notes))


class PppExtractTest(unittest.TestCase):
    def setUp(self):
        self.html = read_fixture(PPP_FIXTURE)

    def test_name_stripped(self):
        self.assertEqual(
            deals_monitor.extract_ppp_name(self.html),
            "Noctua NH-L9a-AM4 33.84 CFM CPU Cooler (NH-L9a-AM4)")

    def test_price_none_for_empty_prices_table(self):
        self.assertIsNone(deals_monitor.extract_ppp_price(self.html))


class ReportTest(unittest.TestCase):
    def test_json_keys(self):
        report = deals_monitor.build_report(
            date="Fri Aug 14 2026",
            sources={"reddit": "ok (25 entries)", "cc": "ok",
                     "ppp": "skipped (no anchors)", "craigslist": "deprecated"},
            rss=[], cc=[], ppp=[], notes=[])
        data = json.loads(json.dumps(report))
        self.assertEqual(set(data),
                         {"date", "sources", "rss", "cc", "ppp", "notes"})

    def test_json_rss_serializable(self):
        report = deals_monitor.build_report(
            date="Fri Aug 14 2026",
            sources={"reddit": "ok"},
            rss=[{"class": "gpu_5070ti", "title": "t", "link": "l",
                  "updated": "2026-08-12T02:43:41+00:00", "price": 2100.0,
                  "retailer": "ME", "in_store": False}],
            cc=[], ppp=[], notes=[])
        data = json.loads(json.dumps(report))
        self.assertEqual(data["rss"][0]["price"], 2100.0)

    def test_format_brief_smoke(self):
        report = deals_monitor.build_report(
            date="Fri Aug 14 2026",
            sources={"reddit": "ok (25 entries)", "cc": "ok",
                     "ppp": "skipped (no anchors)", "craigslist": "deprecated"},
            rss=[], cc=[], ppp=[], notes=["x"])
        out = deals_monitor.format_brief(report, now=AWARE_NOW)
        self.assertIn("🛒 Deals brief", out)
        self.assertIn("Sources:", out)
        self.assertIn("⚠️ Notes", out)


class AgeFormatTest(unittest.TestCase):
    def test_negative_guard(self):
        self.assertEqual(
            deals_monitor.format_age("2026-08-14T18:00:00+00:00", AWARE_NOW),
            "just now")

    def test_hours(self):
        self.assertEqual(
            deals_monitor.format_age("2026-08-14T14:00:00+00:00", AWARE_NOW),
            "2h ago")


class RunMonitorTest(unittest.TestCase):
    def test_rss_only_exit_0(self):
        xml = read_fixture(RSS_FIXTURE)
        report, code = deals_monitor.run_monitor(
            source="rss", now=AWARE_NOW, rss_fetch=lambda url: xml)
        self.assertEqual(code, 0)
        self.assertTrue(report["sources"]["reddit"].startswith("ok"))
        self.assertEqual(report["sources"]["cc"], "skipped")

    def test_all_failed_exit_1(self):
        def boom(url):
            raise RuntimeError("down")

        pw = types.SimpleNamespace(
            WATCH=[("u", "Label", ("5070 ti",), 1.0)],
            fetch=boom, extract=lambda raw: [])
        report, code = deals_monitor.run_monitor(
            source="all", now=AWARE_NOW, pw=pw,
            rss_fetch=boom, cc_fetch=boom, ppp_fetch=boom)
        self.assertEqual(code, 1)
        self.assertTrue(report["sources"]["reddit"].startswith("failed"))
        self.assertTrue(report["sources"]["cc"].startswith("failed"))

    def test_partial_failure_exit_0(self):
        xml = read_fixture(RSS_FIXTURE)

        def boom(url):
            raise RuntimeError("down")

        pw = types.SimpleNamespace(
            WATCH=[("u", "Label", ("5070 ti",), 1.0)],
            fetch=boom, extract=lambda raw: [])
        report, code = deals_monitor.run_monitor(
            source="all", now=AWARE_NOW, pw=pw,
            rss_fetch=lambda url: xml, cc_fetch=boom, ppp_fetch=boom)
        self.assertEqual(code, 0)  # RSS succeeded, so not everything failed
        self.assertTrue(report["sources"]["reddit"].startswith("ok"))


if __name__ == "__main__":
    unittest.main()
