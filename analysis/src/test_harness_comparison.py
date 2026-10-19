"""Runtime conditioning must not hide failed programs in all-run outcomes."""

import unittest
from unittest.mock import patch

import pandas as pd

from harness_comparison import COMPARISONS, MODELS, NATIVE, OPENCODE, compare
from success_rate_tiers import MODEL_LABELS


class HarnessComparisonTest(unittest.TestCase):
    def test_all_cost_profiles_have_tier_display_names(self):
        self.assertEqual(set(MODELS) - set(MODEL_LABELS), set())

    def fixture(self):
        rows = []
        for model in (NATIVE, OPENCODE):
            for benchmark in ("one", "two"):
                for run in (1, 2):
                    rows.append({
                        "benchmark": benchmark, "par_type": "omp", "run": run, "model": model,
                        "total_time": 60, "total_tokens": 120, "input_tokens": 100,
                        "output_tokens": 20, "cached_tokens": 80, "overall_score": 8,
                        "validation_status": 5, "benchmark_success": True, "timing_fixed": False,
                        "benchmark_median_time": 100 if model == NATIVE else (50 if benchmark == "one" else 200),
                    })
        return pd.DataFrame(rows)

    def test_equal_cell_weight_and_ratio_direction(self):
        summary, cells, runtime = compare(self.fixture())
        self.assertEqual(list(cells.opencode_over_codex_runtime), [0.5, 2.0])
        self.assertEqual(runtime["all"]["both_have_success"]["geometric_mean_opencode_over_codex_runtime"], 1)
        self.assertEqual(runtime["all"]["all_programs_successful"]["cells"], 2)
        self.assertEqual(list(summary[summary.backend == "all"].programs), [4, 4])

    def test_failed_programs_remain_in_outcomes_not_runtime(self):
        frame = self.fixture()
        affected = (frame.model == OPENCODE) & (frame.benchmark == "two")
        frame.loc[affected, ["benchmark_success", "validation_status", "overall_score", "benchmark_median_time"]] = [False, 0, 0, None]
        summary, cells, runtime = compare(frame)
        result = summary[(summary.model == OPENCODE) & (summary.backend == "all")].iloc[0]
        self.assertEqual(result.programs, 4)
        self.assertEqual(result.benchmark_successful, 2)
        self.assertEqual(result.mean_overall_score, 4)
        self.assertEqual(runtime["all"]["both_have_success"]["cells"], 1)
        self.assertEqual(runtime["all"]["both_have_success"]["geometric_mean_opencode_over_codex_runtime"], 0.5)
        self.assertTrue(pd.isna(cells.iloc[1].opencode_over_codex_runtime))

    def test_partial_cell_has_separate_sensitivity_view(self):
        frame = self.fixture()
        frame.loc[7, ["benchmark_success", "benchmark_median_time"]] = [False, None]
        _, _, runtime = compare(frame)
        self.assertEqual(runtime["all"]["both_have_success"]["cells"], 2)
        self.assertEqual(runtime["all"]["all_programs_successful"]["cells"], 1)

    def test_scope_and_positive_time_guards(self):
        with self.assertRaisesRegex(ValueError, "scopes differ"):
            compare(self.fixture().iloc[:-1])
        frame = self.fixture()
        frame.loc[0, "benchmark_median_time"] = 0
        with self.assertRaisesRegex(ValueError, "positive finite"):
            compare(frame)

    def test_luna_pair_excludes_other_model_profiles(self):
        native, opencode = COMPARISONS["luna6"]["profiles"]
        original = self.fixture()
        luna = original.replace({"model": {NATIVE: native, OPENCODE: opencode}})
        summary, cells, runtime = compare(pd.concat([original, luna]), comparison="luna6")
        self.assertEqual(set(summary.model), {native, opencode})
        self.assertEqual(list(cells.opencode_over_codex_runtime), [0.5, 2.0])
        self.assertEqual(runtime["all"]["both_have_success"]["cells"], 2)
        self.assertEqual(list(summary[summary.backend == "all"].programs), [4, 4])

    def test_luna_common_price_guard(self):
        native, opencode = COMPARISONS["luna6"]["profiles"]
        luna = self.fixture().replace({"model": {NATIVE: native, OPENCODE: opencode}})
        with patch.dict(MODELS[opencode], input_price=99):
            with self.assertRaisesRegex(ValueError, "common frozen rates"):
                compare(luna, comparison="luna6")

    def test_no_successful_cell_has_no_runtime_estimate(self):
        frame = self.fixture()
        frame[["benchmark_success", "benchmark_median_time"]] = [False, None]
        summary, _, runtime = compare(frame)
        self.assertEqual(list(summary[summary.backend == "all"].programs), [4, 4])
        self.assertEqual(runtime["all"]["both_have_success"]["cells"], 0)
        self.assertIsNone(runtime["all"]["both_have_success"]["geometric_mean_opencode_over_codex_runtime"])

    def test_original_entry_point_preserves_default(self):
        from sol61_harness_comparison import compare as original_compare
        expected = compare(self.fixture())
        actual = original_compare(self.fixture())
        pd.testing.assert_frame_equal(expected[0], actual[0])
        pd.testing.assert_frame_equal(expected[1], actual[1])
        self.assertEqual(expected[2], actual[2])


if __name__ == "__main__":
    unittest.main()
