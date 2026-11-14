"""Tests for the voucher economics. Run from the app folder:  ..\\.venv\\Scripts\\python.exe -m unittest discover -s tests

The key test rebuilds the low, base and high scenarios from the saved snapshot's inputs and compares them with the table in
analysis_answers.md, so the calculator in the app cannot drift from the numbers in the write-up.
"""
import json
import sys
import unittest
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP_DIR))

from olist_app import calculator  # noqa: E402

SNAPSHOT = json.loads((APP_DIR / "snapshot" / "snapshot.json").read_text(encoding="utf-8"))
CAMPAIGN = SNAPSHOT["campaign"]
CAP = 15  # the voucher cap in analysis_answers.md

# The scenario table in analysis_answers.md (section B3), in reais and counts.
DOCUMENTED = {
    0.0025: dict(extra_orders=30, extra_revenue=3703, voucher_cost=1480, net=2224, cost_per_extra=50, break_even=0.40, at_risk=740, needed=19294),
    0.0050: dict(extra_orders=60, extra_revenue=7407, voucher_cost=1891, net=5516, cost_per_extra=32, break_even=0.26, at_risk=945, needed=5593),
    0.0100: dict(extra_orders=119, extra_revenue=14814, voucher_cost=2714, net=12100, cost_per_extra=23, break_even=0.18, at_risk=1357, needed=1780),
}


class ScenarioTable(unittest.TestCase):
    def setUp(self):
        self.avg_voucher = calculator.voucher_cost(SNAPSHOT["freights"], CAP)

    def test_inputs_are_the_documented_ones(self):
        self.assertEqual(CAMPAIGN["segment_per_year"], 11937)
        self.assertAlmostEqual(CAMPAIGN["baseline_56d"] * 100, 0.65, places=2)
        self.assertAlmostEqual(CAMPAIGN["avg_items_price"], 124.10, places=2)
        self.assertAlmostEqual(self.avg_voucher, 13.78, places=2)
        self.assertEqual(len(SNAPSHOT["freights"]), 3264)

    def test_reproduces_the_scenarios_in_the_write_up(self):
        for uplift, expected in DOCUMENTED.items():
            with self.subTest(uplift=uplift):
                got = calculator.outcome(
                    CAMPAIGN["segment_per_year"], CAMPAIGN["baseline_56d"], uplift, CAMPAIGN["avg_items_price"], self.avg_voucher
                )
                self.assertAlmostEqual(got.extra_orders, expected["extra_orders"], delta=1)
                self.assertAlmostEqual(got.extra_revenue, expected["extra_revenue"], delta=2)
                self.assertAlmostEqual(got.voucher_cost, expected["voucher_cost"], delta=2)
                self.assertAlmostEqual(got.revenue_less_voucher_cost, expected["net"], delta=3)
                self.assertAlmostEqual(got.cost_per_extra_order, expected["cost_per_extra"], delta=1)
                self.assertAlmostEqual(got.break_even_margin, expected["break_even"], delta=0.01)
                self.assertAlmostEqual(got.test_spend_at_risk, expected["at_risk"], delta=2)
                self.assertEqual(got.people_per_group_needed, expected["needed"])

    def test_smallest_detectable_uplift_matches_the_write_up(self):
        for months, people, expected_points in ((3, 1492, 1.12), (6, 2984, 0.73), (12, 5969, 0.49)):
            with self.subTest(months=months):
                available = calculator.people_per_group_available(CAMPAIGN["segment_per_year"], months)
                self.assertAlmostEqual(available, people, delta=1)
                got = calculator.smallest_detectable_uplift(CAMPAIGN["baseline_56d"], available)
                self.assertAlmostEqual(got * 100, expected_points, delta=0.011)


class Behaviour(unittest.TestCase):
    def test_a_lower_cap_costs_less(self):
        freights = [5.0, 10.0, 20.0, 40.0]
        self.assertLess(calculator.voucher_cost(freights, 10), calculator.voucher_cost(freights, 30))
        self.assertEqual(calculator.voucher_cost(freights, 10), (5 + 10 + 10 + 10) / 4)

    def test_a_bigger_effect_needs_fewer_people(self):
        self.assertGreater(calculator.people_per_group_needed(0.0065, 0.0025), calculator.people_per_group_needed(0.0065, 0.01))

    def test_profit_rises_with_margin_and_break_even_is_where_it_crosses_zero(self):
        got = calculator.outcome(10000, 0.0065, 0.005, 124.10, 13.78)
        self.assertLess(got.profit_at(0.10), got.profit_at(0.40))
        self.assertAlmostEqual(got.profit_at(got.break_even_margin), 0.0, places=6)

    def test_too_small_a_group_detects_nothing(self):
        self.assertIsNone(calculator.smallest_detectable_uplift(0.0065, 50))

    def test_bad_inputs_are_refused(self):
        with self.assertRaises(ValueError):
            calculator.people_per_group_needed(0.0065, 0)
        with self.assertRaises(ValueError):
            calculator.voucher_cost([], 15)


if __name__ == "__main__":
    unittest.main()
