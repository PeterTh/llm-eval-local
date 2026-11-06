import json
import unittest
from codex_tree_cost import SOURCE, FIELDS, verify_recorded_tree_row


class RecordedTreeCostTest(unittest.TestCase):
    def setUp(self):
        self.counts = dict(input_tokens=100, cached_input_tokens=80, cache_write_input_tokens=0,
                           output_tokens=10, reasoning_output_tokens=7, total_tokens=110)
        self.row = {column: value for native, column in FIELDS.items() for value in [self.counts[native]]}
        self.row.update(token_usage_source=SOURCE, token_usage_complete="false", generation_outcome="completed",
                        partial_token_counts=json.dumps(self.counts))

    def test_recorded_counters_remain_marked_incomplete(self):
        self.assertTrue(verify_recorded_tree_row(self.row))
        self.row.update(token_usage_complete="true", partial_token_counts="")
        self.assertFalse(verify_recorded_tree_row(self.row))

    def test_cannot_hide_a_cancelled_request_or_change_counters(self):
        for key, value in (("token_usage_complete", "true"), ("partial_token_counts", "{}"),
                           ("cached_tokens", 79), ("cache_write_input_tokens", None),
                           ("output_tokens", -1), ("total_tokens", float("nan"))):
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify_recorded_tree_row({**self.row, key: value})

    def test_cannot_bypass_terminated_or_other_provider_usage_rules(self):
        for key, value in (("token_usage_source", "opencode_native_step_finish"),
                           ("generation_outcome", ""), ("generation_outcome", None),
                           ("generation_outcome", "generation_model_terminated"),
                           ("generation_failure_reason", "model_caused_termination")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify_recorded_tree_row({**self.row, key: value})

    def test_cost_aggregation_retains_recorded_volume_and_uncertainty(self):
        import pandas as pd
        from all_models_score_vs_cost import aggregate
        row = {**self.row, "model": "gpt-6.1-terra-ultra", "overall_score": 9}
        complete = {**row, "token_usage_complete": "true", "partial_token_counts": "", "overall_score": 5}
        result = aggregate(pd.DataFrame([row, complete])).iloc[0]
        self.assertEqual(result["score_run_count"], 2)
        self.assertEqual(result["cost_run_count"], 2)
        self.assertEqual(result["uncertain_usage_run_count"], 1)
        self.assertEqual(result["mean_overall_score"], 7)
        self.assertAlmostEqual(result["estimated_cost_usd_per_run"], (20 * .5 + 80 * .025 + 10 * 2.5) / 1_000_000)
        with self.assertRaises(ValueError):
            aggregate(pd.DataFrame([{**row, "model": "gpt-6.1-terra-xhigh"}]))


if __name__ == "__main__":
    unittest.main()
