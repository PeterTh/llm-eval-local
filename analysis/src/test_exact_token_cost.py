"""Regression checks for recovered Codex usage pricing (no API calls)."""
import unittest
import pandas as pd
import gpt56_score_vs_cost as focused
import all_models_score_vs_cost as combined


class ExactTokenCostTest(unittest.TestCase):
    def setUp(self):
        self.frame = pd.DataFrame([dict(model="gpt-5.6-sol-xhigh", overall_score=7,
            input_tokens=100, cached_tokens=80, output_tokens=10, total_tokens=110)])

    def test_focused_cost_prices_cache_and_output_without_double_counting(self):
        row = focused.aggregate(self.frame).iloc[0]
        self.assertAlmostEqual((20 * 4 + 80 * 0.4 + 10 * 20) / 1_000_000,
                               row.estimated_cost_usd_per_run)
        self.assertEqual(110, row.mean_total_tokens)
        self.assertEqual(7, row.mean_overall_score)

    def test_combined_cost_uses_exact_split_with_frozen_rates(self):
        row = combined.aggregate(self.frame).iloc[0]
        prices = combined.MODELS["gpt-5.6-sol-xhigh"]
        expected = (20 * prices["input_price"] + 80 * prices["cached_input_price"]
                    + 10 * prices["output_price"]) / 1_000_000
        self.assertAlmostEqual(expected, row.estimated_cost_usd_per_run)
        self.assertTrue(pd.isna(row.effective_price_usd_per_million))
        self.assertEqual(100, row.mean_input_tokens)
        self.assertEqual(80, row.mean_cached_input_tokens)

    def test_gpt6_flex_profiles_price_all_three_token_classes(self):
        rates = {"sol": (1.0, 0.1, 5.0), "luna": (0.05, 0.005, 0.25),
                 "astra": (5.0, 0.5, 25.0)}
        for variant, (uncached, cached, output) in rates.items():
            with self.subTest(variant=variant):
                model = f"gpt-6-{variant}-medium"
                frame = self.frame.assign(model=model)
                row = combined.aggregate(frame).iloc[0]
                self.assertAlmostEqual((20 * uncached + 80 * cached + 10 * output) / 1_000_000,
                                       row.estimated_cost_usd_per_run)
                self.assertEqual("2026-10-02", row.pricing_as_of)
                self.assertEqual(110, row.mean_total_tokens)
                self.assertEqual(f"https://developers.openai.com/api/docs/models/gpt-6-{variant}",
                                 row.pricing_source_url)

    def test_subcent_cost_ticks_remain_distinct(self):
        self.assertEqual("$0.002", combined._format_cost(0.002, 0))
        self.assertEqual("$0.005", combined._format_cost(0.005, 1))
        self.assertEqual("$0.01", combined._format_cost(0.01, 2))


if __name__ == "__main__":
    unittest.main()
