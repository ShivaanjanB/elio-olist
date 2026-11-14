"""Tests of the Streamlit app itself, run in-process on the saved snapshot (no browser, no Snowflake).

Run from the app folder:  ..\\.venv\\Scripts\\python.exe -m unittest discover -s tests -v

Each test follows one charter from the exploratory session: drive a page the way a reader would, then check the result. Bugs
found by exploring were turned into the regression tests marked BUG below.
"""
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

APP_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP_DIR))
os.environ["OLIST_APP_SOURCE"] = "snapshot"  # never reach for Snowflake in tests

from streamlit.proto.Metric_pb2 import Metric as MetricProto  # noqa: E402
from streamlit.testing.v1 import AppTest  # noqa: E402

from olist_app import calculator, data  # noqa: E402

SNAPSHOT = json.loads((APP_DIR / "snapshot" / "snapshot.json").read_text(encoding="utf-8"))
ENTRY = str(APP_DIR / "streamlit_app.py")


def open_page(page: str | None = None) -> AppTest:
    at = AppTest.from_file(ENTRY, default_timeout=60).run()
    if page:
        at.switch_page(f"app_pages/{page}.py").run()
    return at


def metric_values(at: AppTest) -> dict:
    return {m.label: m.value for m in at.metric}


class Snapshot(unittest.TestCase):
    """The saved numbers must still be the documented ones."""

    def test_shapes(self):
        tables = SNAPSHOT["tables"]
        self.assertEqual({k: len(v) for k, v in tables.items()},
                         {"arrival_bands": 6, "arrival_summary": 2, "review_by_state": 14, "states": 27,
                          "repeat_by_experience": 5, "repeat_by_quarter": 7})
        self.assertEqual(len(SNAPSHOT["freights"]), 3264)

    def test_headline_numbers(self):
        summary = {row["arrival"]: row for row in SNAPSHOT["tables"]["arrival_summary"]}
        self.assertEqual(summary["late"]["avg_score"], 2.27)
        self.assertEqual(summary["on time or early"]["avg_score"], 4.29)
        experience = {row["grp"]: row for row in SNAPSHOT["tables"]["repeat_by_experience"]}
        self.assertEqual(experience["Late"]["repeat_180d_pct"], 1.21)
        self.assertEqual(experience["All first-time buyers"]["people"], 63874)

    def test_text_in_it_cannot_carry_markup(self):
        # The pages print a few of these strings through st.markdown, so keep markup characters out of them.
        def strings(node):
            if isinstance(node, str):
                yield node
            elif isinstance(node, dict):
                for value in node.values():  # the column names are fixed by the queries; the values are data
                    yield from strings(value)
            elif isinstance(node, list):
                for value in node:
                    yield from strings(value)

        for text in strings(SNAPSHOT):
            for bad in ("[", "]", "<", ">", "`", "|", "*", chr(92), chr(10)):
                self.assertNotIn(bad, text, text)

    def test_holds_no_identifiers(self):
        text = json.dumps(SNAPSHOT).lower()
        for forbidden in ("customer_id", "order_id", "customer_unique_id", "seller_id", "email", "zip_code"):
            self.assertNotIn(forbidden, text)


class DeliveryPage(unittest.TestCase):
    def test_loads_and_states_the_finding(self):
        at = open_page()
        self.assertFalse(at.exception, [e.value for e in at.exception])
        self.assertIn("2.27", at.title[0].value)
        self.assertIn("4.29", at.title[0].value)

    def test_every_review_measure_and_state_measure_draws(self):
        at = open_page()
        for label in ("Average score", "Share giving 1–2 stars", "Share giving 5 stars"):
            at.get("segmented_control")[0].set_value(label).run()  # the review measure
            self.assertFalse(at.exception, label)
        for label in ("Late deliveries", "Days to deliver", "Review score", "Freight ratio"):
            at.get("segmented_control")[1].set_value(label).run()  # the state measure
            self.assertFalse(at.exception, label)

    def test_showing_every_state_includes_the_thin_ones(self):
        at = open_page()
        at.toggle(key="hide_small").set_value(False).run()
        self.assertFalse(at.exception)
        at.toggle(key="hide_small").set_value(True).run()
        self.assertFalse(at.exception)

    def test_a_cleared_measure_falls_back_instead_of_crashing(self):
        # BUG found by exploring: deselecting a segmented control returns None, which must not break the page.
        at = open_page()
        at.get("segmented_control")[0].set_value(None).run()
        self.assertFalse(at.exception)
        at.get("segmented_control")[1].set_value(None).run()
        self.assertFalse(at.exception)


class ComingBackPage(unittest.TestCase):
    def test_loads_and_every_window_draws(self):
        at = open_page("coming_back")
        self.assertFalse(at.exception, [e.value for e in at.exception])
        self.assertIn("come back less often", at.title[0].value)
        for window in ("8 weeks", "90 days", "6 months"):
            at.get("segmented_control")[0].set_value(window).run()
            self.assertFalse(at.exception, window)

    def test_cleared_window_falls_back(self):
        at = open_page("coming_back")
        at.get("segmented_control")[0].set_value(None).run()
        self.assertFalse(at.exception)


class VoucherPage(unittest.TestCase):
    def test_base_scenario_matches_the_write_up(self):
        at = open_page("voucher_test")
        self.assertFalse(at.exception, [e.value for e in at.exception])
        at.slider(key="uplift").set_value(0.5).run()
        at.slider(key="cap").set_value(15).run()
        values = metric_values(at)
        self.assertEqual(values["Revenue less voucher cost"], "R$5,516")
        self.assertEqual(values["Break-even margin"], "26%")

    def test_low_and_high_scenarios_match_the_write_up(self):
        at = open_page("voucher_test")
        at.slider(key="cap").set_value(15).run()
        for uplift, expected in ((0.25, "R$2,224"), (1.0, "R$12,100")):
            at.slider(key="uplift").set_value(uplift).run()
            self.assertEqual(metric_values(at)["Revenue less voucher cost"], expected)

    def test_the_scenario_buttons_move_the_slider(self):
        at = open_page("voucher_test")
        at.get("segmented_control")[0].set_value("High").run()
        self.assertEqual(at.slider(key="uplift").value, 1.0)
        at.get("segmented_control")[0].set_value("Low").run()
        self.assertEqual(at.slider(key="uplift").value, 0.25)

    def test_the_whole_input_range_stays_finite(self):
        at = open_page("voucher_test")
        for uplift in (0.10, 2.0):
            for cap in (5, 30):
                for margin in (0, 60):
                    at.slider(key="uplift").set_value(uplift)
                    at.slider(key="cap").set_value(cap)
                    at.slider(key="margin").set_value(margin)
                    at.run()
                    self.assertFalse(at.exception, (uplift, cap, margin))
                    for label, value in metric_values(at).items():
                        self.assertNotIn("nan", value.lower(), label)
                        self.assertNotIn("inf", value.lower(), label)

    def test_a_margin_below_break_even_reads_as_bad_and_above_as_good(self):
        # BUG found by exploring: the break-even card showed a green down arrow while the profit card said "loses money".
        at = open_page("voucher_test")
        at.slider(key="uplift").set_value(0.5).run()  # break-even is 26%
        at.slider(key="margin").set_value(10).run()
        below = {m.label: m for m in at.metric}
        self.assertEqual(below["Profit at your margin"].proto.color, MetricProto.RED)
        self.assertEqual(below["Break-even margin"].proto.color, MetricProto.RED)
        self.assertIn("below", below["Break-even margin"].delta)
        at.slider(key="margin").set_value(40).run()
        above = {m.label: m for m in at.metric}
        self.assertEqual(above["Profit at your margin"].proto.color, MetricProto.GREEN)
        self.assertEqual(above["Break-even margin"].proto.color, MetricProto.GREEN)
        self.assertIn("above", above["Break-even margin"].delta)

    def test_segment_extremes(self):
        at = open_page("voucher_test")
        for people in (1000, 100000):
            at.number_input(key="segment").set_value(people).run()
            self.assertFalse(at.exception, people)

    def test_a_larger_effect_is_easier_to_see(self):
        # At +0.25 points the default year of enrolment cannot see the effect; at +1.00 it can.
        at = open_page("voucher_test")
        at.slider(key="uplift").set_value(0.25).run()
        low = " ".join(m.value for m in at.markdown)
        at.slider(key="uplift").set_value(1.0).run()
        high = " ".join(m.value for m in at.markdown)
        self.assertIn("That is not enough", low)
        self.assertIn("That is enough.", high)

    def test_bad_values_in_the_url_are_ignored(self):
        for bad in ("abc", "99", "-1", ""):
            with self.subTest(bad=bad):
                at = AppTest.from_file(ENTRY, default_timeout=60)
                at.query_params["uplift"] = bad
                at.query_params["cap"] = bad
                at.query_params["margin"] = bad
                at.run()
                at.switch_page("app_pages/voucher_test.py").run()
                self.assertFalse(at.exception, bad)

    def test_a_good_value_in_the_url_is_used(self):
        at = AppTest.from_file(ENTRY, default_timeout=60)
        at.query_params["uplift"] = "1.0"
        at.run()
        at.switch_page("app_pages/voucher_test.py").run()
        self.assertFalse(at.exception)
        self.assertEqual(at.slider(key="uplift").value, 1.0)


class DataSourceFallback(unittest.TestCase):
    def test_unreachable_snowflake_falls_back_to_the_snapshot_and_says_so(self):
        env = {name: "x" for name in data.REQUIRED_VARIABLES}
        with mock.patch.dict(os.environ, {**env, "OLIST_APP_SOURCE": ""}), mock.patch.object(
            data, "fetch_live", side_effect=RuntimeError("password is hunter2 for host example.invalid")
        ):
            data.load.clear()
            bundle = data.load()
        data.load.clear()
        self.assertEqual(bundle["source"], "snapshot")
        note = data.source_note(bundle)
        self.assertIn("RuntimeError", note)
        self.assertNotIn("hunter2", note)  # the message of the error must never reach the page
        self.assertNotIn("example.invalid", note)

    def test_live_is_off_without_settings(self):
        with mock.patch.dict(os.environ, {"OLIST_APP_SOURCE": ""}, clear=False):
            for name in data.REQUIRED_VARIABLES:
                os.environ.pop(name, None)
            self.assertFalse(data.live_configured())

    def test_forced_snapshot_wins_over_settings(self):
        env = {name: "x" for name in data.REQUIRED_VARIABLES}
        with mock.patch.dict(os.environ, {**env, "OLIST_APP_SOURCE": "snapshot"}):
            self.assertFalse(data.live_configured())


if __name__ == "__main__":
    unittest.main()
