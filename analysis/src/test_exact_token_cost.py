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

    def test_every_priced_profile_has_an_explicit_figure_label_position(self):
        self.assertEqual(set(combined.MODELS), set(combined.LABEL_OFFSETS))

    def test_sol61_profiles_share_rates_but_retain_both_efforts(self):
        for effort in ("medium", "xhigh"):
            with self.subTest(effort=effort):
                row = combined.aggregate(self.frame.assign(model=f"gpt-6.1-sol-{effort}")).iloc[0]
                self.assertAlmostEqual((20 * 1 + 80 * 0.05 + 10 * 5) / 1_000_000,
                                       row.estimated_cost_usd_per_run)
                self.assertEqual("2026-10-11", row.pricing_as_of)
                self.assertEqual(0.05, row.cached_input_price_usd_per_million)
                self.assertEqual("https://developers.openai.com/api/docs/models/gpt-6.1-sol", row.pricing_source_url)

    def test_terra61_uses_its_own_frozen_flex_rates(self):
        row = combined.aggregate(self.frame.assign(model="gpt-6.1-terra-medium")).iloc[0]
        self.assertAlmostEqual((20 * 0.5 + 80 * 0.025 + 10 * 2.5) / 1_000_000,
                               row.estimated_cost_usd_per_run)
        self.assertEqual("2026-10-28", row.pricing_as_of)
        self.assertEqual("openai/flex", row.pricing_provider_tag)
        self.assertEqual("https://developers.openai.com/api/docs/models/gpt-6.1-terra", row.pricing_source_url)
        self.assertIn("2,583 requests", row.cost_method)

    def test_terra61_campaign_cost_matches_independent_per_request_audit(self):
        totals = self.frame.assign(model="gpt-6.1-terra-medium",
            input_tokens=42_257_780, cached_tokens=38_479_232,
            output_tokens=769_669, total_tokens=43_027_449)
        row = combined.aggregate(totals).iloc[0]
        self.assertAlmostEqual(4.7754273, row.estimated_cost_usd_per_run, places=10)
        self.assertAlmostEqual(0.021706487727272727, row.estimated_cost_usd_per_run / 220,
                               places=12)
        self.assertEqual(43_027_449, row.mean_total_tokens)

    def test_terra61_xhigh_shares_model_rates_with_distinct_accounting(self):
        medium = combined.MODELS["gpt-6.1-terra-medium"]
        xhigh = combined.MODELS["gpt-6.1-terra-xhigh"]
        for field in ("pricing_as_of", "input_price", "cached_input_price", "output_price",
                      "pricing_model_id", "pricing_provider_tag", "pricing_source_url"):
            self.assertEqual(medium[field], xhigh[field], field)
        totals = self.frame.assign(model="gpt-6.1-terra-xhigh",
            input_tokens=97_261_512, cached_tokens=92_136_704,
            output_tokens=1_708_412, total_tokens=98_969_924,
            reasoning_output_tokens=423_784)
        row = combined.aggregate(totals).iloc[0]
        self.assertAlmostEqual(9.1368516, row.estimated_cost_usd_per_run, places=10)
        self.assertAlmostEqual(0.041531143636363636, row.estimated_cost_usd_per_run / 220,
                               places=12)
        self.assertEqual(98_969_924, row.mean_total_tokens)
        self.assertIn("4,382 requests", row.cost_method)

    def test_opus55_exact_tokens_use_dated_cache_discount(self):
        frame = self.frame.assign(model="claude-opus-5.5-cc-medium")
        row = combined.aggregate(frame).iloc[0]
        self.assertAlmostEqual((20 * 4 + 80 * 0.2 + 10 * 20) / 1_000_000,
                               row.estimated_cost_usd_per_run)
        self.assertEqual("2026-10-06", row.pricing_as_of)
        self.assertEqual(110, row.mean_total_tokens)
        self.assertEqual(0.2, row.cached_input_price_usd_per_million)

    def test_opencode_sol61_uses_same_model_rates_with_distinct_harness_label(self):
        native = combined.aggregate(self.frame.assign(model="gpt-6.1-sol-medium")).iloc[0]
        alternate = combined.aggregate(self.frame.assign(model="gpt-6.1-sol-oc-medium")).iloc[0]
        self.assertEqual(native.estimated_cost_usd_per_run, alternate.estimated_cost_usd_per_run)
        self.assertEqual(110, alternate.mean_total_tokens)
        self.assertEqual("2026-10-18", alternate.pricing_as_of)
        self.assertIn("OpenCode", alternate.model_label)
        self.assertIn("OpenCode", alternate.cost_method)

    def test_opencode_luna6_uses_same_model_rates_with_distinct_harness_label(self):
        native = combined.aggregate(self.frame.assign(model="gpt-6-luna-medium")).iloc[0]
        alternate = combined.aggregate(self.frame.assign(model="gpt-6-luna-oc-medium")).iloc[0]
        self.assertEqual(native.estimated_cost_usd_per_run, alternate.estimated_cost_usd_per_run)
        self.assertEqual(110, alternate.mean_total_tokens)
        self.assertEqual("2026-10-19", alternate.pricing_as_of)
        self.assertIn("OpenCode", alternate.model_label)
        self.assertIn("OpenCode", alternate.cost_method)

    def test_deepseek_partial_usage_is_not_a_complete_cost_observation(self):
        model = "deepseek-v4.1-flash-oc-high"
        complete = self.frame.assign(model=model, token_usage_complete=True)
        incomplete = self.frame.assign(model=model, overall_score=0, token_usage_complete=False,
            input_tokens=float("nan"), cached_tokens=float("nan"), output_tokens=float("nan"), total_tokens=float("nan"),
            partial_token_counts='{"total_tokens":110}')
        row = combined.aggregate(pd.concat([complete, incomplete], ignore_index=True)).iloc[0]
        self.assertEqual(2, row.score_run_count)
        self.assertEqual(1, row.cost_run_count)
        self.assertEqual(3.5, row.mean_overall_score)
        self.assertAlmostEqual((20 * 0.0537 + 80 * 0.001074 + 10 * 0.2148) / 1_000_000,
                               row.estimated_cost_usd_per_run)
        self.assertEqual("2026-10-24", row.pricing_as_of)
        self.assertEqual("baidu/fp8", row.pricing_provider_tag)
        with self.assertRaisesRegex(ValueError, "Incomplete usage"):
            combined.aggregate(complete.assign(token_usage_complete=False))

    def test_beam_uses_frozen_comparison_rates_not_the_free_promotion(self):
        totals = self.frame.assign(model="beam-1.0-oc-medium",
            input_tokens=39_500_880, cached_tokens=29_452_416,
            output_tokens=883_833, total_tokens=40_384_713)
        row = combined.aggregate(totals).iloc[0]
        self.assertAlmostEqual(4.8685698, row.estimated_cost_usd_per_run, places=10)
        self.assertAlmostEqual(0.022230912328767123, row.estimated_cost_usd_per_run / 219,
                               places=12)
        self.assertEqual("2026-10-30", row.pricing_as_of)
        self.assertEqual("nebius/fp4", row.pricing_provider_tag)
        self.assertTrue(pd.isna(row.request_input_threshold_tokens))

    def test_beam_protocol_failure_keeps_its_score_but_not_a_partial_cost(self):
        complete = self.frame.assign(model="beam-1.0-oc-medium", token_usage_complete=True)
        incomplete = self.frame.assign(model="beam-1.0-oc-medium", overall_score=1,
            token_usage_complete=False, input_tokens=float("nan"), cached_tokens=float("nan"),
            output_tokens=float("nan"), total_tokens=float("nan"),
            partial_token_counts='{"total_tokens":72920}', generation_failure_reason="model_protocol_failure")
        row = combined.aggregate(pd.concat([complete, incomplete], ignore_index=True)).iloc[0]
        self.assertEqual(2, row.score_run_count)
        self.assertEqual(1, row.cost_run_count)
        self.assertEqual(4, row.mean_overall_score)
        self.assertAlmostEqual((20 * 0.25 + 80 * 0.05 + 10 * 1) / 1_000_000,
                               row.estimated_cost_usd_per_run)
        with self.assertRaisesRegex(ValueError, "Incomplete usage"):
            combined.aggregate(complete.assign(token_usage_complete=False))


if __name__ == "__main__":
    unittest.main()
