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


if __name__ == "__main__":
    unittest.main()
