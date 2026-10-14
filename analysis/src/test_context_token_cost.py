"""Request-context pricing, including the strict threshold and derived outputs."""

from copy import deepcopy
import unittest

import pandas as pd

import all_models_score_vs_cost as combined
from context_token_cost import context_run_cost


class ContextTokenCostTest(unittest.TestCase):
    def setUp(self):
        model = "claude-haiku-5.5-cc-medium"
        self.profile = combined.MODELS[model]
        self.row = dict(model=model, benchmark="qtclustering", par_type="mpi", run=1,
                        overall_score=8, input_tokens=200001, cached_tokens=180000,
                        output_tokens=50, total_tokens=200051)
        self.record = dict(schema_version=1, id=f"qtclustering_{model}_mpi_r1",
                           pricing_as_of="2026-10-14", request_input_threshold_tokens=100000,
                           source_commit=self.profile["context_source_commit"], requests=2,
                           per_request_output_available=False,
                           output_band_evidence="derived_from_reported_list_cost_and_native_output_total",
                           comparison_cost_nanodollars=11485500, cache_write_surcharge_nanodollars=102500,
                           native_list_cost_nanodollars=11588000,
                           bands={
                               "short": dict(input_tokens=9900, cache_read_input_tokens=90000,
                                             cache_creation_5m_tokens=100, cache_creation_1h_tokens=0,
                                             output_tokens=20, inclusive_input_tokens=100000,
                                             requests=1, max_request_input_tokens=100000, streamed_output_lower_bound=1),
                               "long": dict(input_tokens=9801, cache_read_input_tokens=90000,
                                            cache_creation_5m_tokens=0, cache_creation_1h_tokens=200,
                                            output_tokens=30, inclusive_input_tokens=100001,
                                            requests=1, max_request_input_tokens=100001, streamed_output_lower_bound=1),
                           })

    def test_mixed_context_prices_each_band_and_excludes_cache_write_surcharge(self):
        self.assertEqual(0.0114855, context_run_cost(self.row, self.profile, self.record))
        result = combined.aggregate(pd.DataFrame([self.row]), {self.record["id"]: self.record}).iloc[0]
        self.assertEqual(0.0114855, result.estimated_cost_usd_per_run)
        self.assertEqual(100000, result.request_input_threshold_tokens)
        self.assertEqual(2.5, result.long_output_price_usd_per_million)
        self.assertIn("derived", result.cost_method)

    def test_exact_threshold_is_short_but_one_more_is_long(self):
        record = deepcopy(self.record)
        record["bands"]["long"]["max_request_input_tokens"] = 100000
        with self.assertRaisesRegex(ValueError, "wrong context band"):
            context_run_cost(self.row, self.profile, record)

    def test_rejects_missing_usage_and_token_or_provenance_disagreement(self):
        with self.assertRaisesRegex(ValueError, "missing request-context"):
            combined.aggregate(pd.DataFrame([self.row]), {})
        for field, value, message in (
            ("source_commit", "0" * 40, "revision"),
            ("comparison_cost_nanodollars", 11485501, "cost mismatch"),
            ("output_band_evidence", "direct_per_request", "provenance"),
            ("request_input_threshold_tokens", 200000, "threshold"),
        ):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, message):
                context_run_cost(self.row, self.profile, {**self.record, field: value})
        with self.assertRaisesRegex(ValueError, "scored tokens"):
            context_run_cost({**self.row, "cached_tokens": 170000}, self.profile, self.record)


if __name__ == "__main__":
    unittest.main()
