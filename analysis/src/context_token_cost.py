"""Price retained request-context bands without changing aggregate token counts."""

import json
import re
from pathlib import Path


def load_context_usage(path: Path) -> dict:
    records = {}
    for line in path.read_text().splitlines():
        record = json.loads(line)
        if record["id"] in records:
            raise ValueError(f"duplicate context usage: {record['id']}")
        records[record["id"]] = record
    return records


def context_run_cost(row, profile: dict, record: dict) -> float:
    def require(condition, message):
        if not condition:
            raise ValueError(f"{record.get('id', 'context usage')}: {message}")

    def count(value):
        require(type(value) is int and value >= 0, "invalid context token count")
        return value

    expected_id = f"{row['benchmark']}_{row['model']}_{row['par_type']}_r{int(row['run'])}"
    require(record["id"] == expected_id, "context identity mismatch")
    require(record["schema_version"] in (1, 2), "unsupported context schema")
    direct = record["schema_version"] == 2
    require(record["pricing_as_of"] == profile["pricing_as_of"], "context pricing date mismatch")
    require(record["request_input_threshold_tokens"] == profile["context_threshold_tokens"], "context threshold mismatch")
    require(record["per_request_output_available"] is direct, "unexpected output evidence")
    if direct:
        require(record["usage_complete"] is True, "incomplete native usage")
        require(re.fullmatch(r"[0-9a-f]{64}", record["native_session_sha256"]) is not None,
                "missing native session binding")
    require(record["source_commit"] == profile["context_source_commit"], "context source revision mismatch")
    require(set(record["bands"]) == {"short", "long"}, "missing context bands")
    input_total = cached_total = output_total = request_total = cost_nanos = 0
    write_total = reasoning_total = 0
    for name, band in record["bands"].items():
        write_keys = ("cache_write_input_tokens",) if direct else ("cache_creation_5m_tokens", "cache_creation_1h_tokens")
        written = sum(count(band[key]) for key in write_keys)
        uncached = count(band["input_tokens"]) + written
        cached = count(band["cache_read_input_tokens"])
        output = count(band["output_tokens"])
        requests = count(band["requests"])
        maximum = count(band["max_request_input_tokens"])
        require(count(band["inclusive_input_tokens"]) == uncached + cached, "band input total mismatch")
        if direct:
            reasoning = count(band["reasoning_output_tokens"])
            require(reasoning <= output, "reasoning exceeds inclusive output")
            write_total += written
            reasoning_total += reasoning
        else:
            require(output >= count(band["streamed_output_lower_bound"]), "output below retained lower bound")
        if requests == 0:
            require(uncached + cached + output + maximum == 0, "tokens assigned to an unused band")
        else:
            require((maximum > profile["context_threshold_tokens"]) == (name == "long"), "request in wrong context band")
            require(maximum <= uncached + cached <= maximum * requests, "request lengths disagree with band total")
            if direct and name == "long":
                require(uncached + cached >= (profile["context_threshold_tokens"] + 1) * requests,
                        "long-band requests below threshold")
        prefix = "long_" if name == "long" else ""
        prices = [profile[prefix + key] for key in ("input_price", "cached_input_price", "output_price")]
        nanos = [round(price * 1000) for price in prices]
        require(all(abs(price * 1000 - value) < 1e-8 for price, value in zip(prices, nanos)), "off-grid context rate")
        cost_nanos += sum(tokens * price for tokens, price in zip((uncached, cached, output), nanos))
        input_total += uncached + cached
        cached_total += cached
        output_total += output
        request_total += requests
    require((input_total, cached_total, output_total) ==
            (row["input_tokens"], row["cached_tokens"], row["output_tokens"]), "context totals disagree with scored tokens")
    require(input_total + output_total == row["total_tokens"], "context total tokens disagree")
    require(request_total == count(record["requests"]), "request count mismatch")
    mixed = all(band["requests"] > 0 for band in record["bands"].values())
    expected_evidence = ("native_step_finish_per_request" if direct else
                         "derived_from_reported_list_cost_and_native_output_total" if mixed
                         else "native_total_in_single_observed_band")
    require(record["output_band_evidence"] == expected_evidence, "output provenance mismatch")
    require(cost_nanos == count(record["comparison_cost_nanodollars"]), "recomputed context cost mismatch")
    if direct:
        expected = dict(input_tokens=input_total, cached_input_tokens=cached_total,
                        cache_write_input_tokens=write_total, output_tokens=output_total,
                        reasoning_output_tokens=reasoning_total, total_tokens=input_total + output_total)
        require({key: count(record["token_counts"][key]) for key in expected} == expected,
                "native token totals disagree with bands")
    else:
        require(cost_nanos + count(record["cache_write_surcharge_nanodollars"]) ==
                count(record["native_list_cost_nanodollars"]), "native list cost does not reconcile")
    return cost_nanos / 1_000_000_000
