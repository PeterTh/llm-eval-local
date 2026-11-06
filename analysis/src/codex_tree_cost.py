"""Keep recorded whole-tree usage distinct from complete billing coverage."""
import json
import math


SOURCE = "codex_rollout_unique_thread_requests"
FIELDS = {
    "input_tokens": "input_tokens", "cached_input_tokens": "cached_tokens",
    "cache_write_input_tokens": "cache_write_input_tokens", "output_tokens": "output_tokens",
    "reasoning_output_tokens": "reasoning_output_tokens", "total_tokens": "total_tokens",
}


def present(value):
    return value is not None and not (isinstance(value, float) and math.isnan(value)) and str(value) != ""


def verify_recorded_tree_row(row) -> bool:
    """Validate CSV semantics; retained tree provenance is checked by the exporter.

    Return whether an interrupted request may be missing usage. Never synthesize
    missing counters and never reinterpret a terminated generation as complete.
    """
    if row.get("token_usage_source") != SOURCE:
        raise ValueError("recorded tree cost requires native whole-tree evidence")
    flag = str(row.get("token_usage_complete", "")).lower()
    if flag not in ("true", "false"):
        raise ValueError("missing native tree completeness flag")
    outcome = row.get("generation_outcome")
    if outcome != "completed" or any(
        present(row.get(key)) for key in ("generation_failure_reason", "termination_record_sha256")
    ):
        raise ValueError("recorded tree cost cannot substitute for a terminated generation")
    counts = {}
    for native, column in FIELDS.items():
        value = row.get(column)
        if not present(value):
            raise ValueError("missing recorded native tree counter")
        number = float(value)
        if not math.isfinite(number) or number < 0 or not number.is_integer():
            raise ValueError("invalid recorded native tree counter")
        counts[native] = int(number)
    if (counts["input_tokens"] < counts["cached_input_tokens"] + counts["cache_write_input_tokens"]
        or counts["output_tokens"] < counts["reasoning_output_tokens"]
        or counts["total_tokens"] != counts["input_tokens"] + counts["output_tokens"]):
        raise ValueError("inconsistent recorded native tree counters")
    partial = row.get("partial_token_counts")
    if flag == "false":
        if not present(partial) or json.loads(partial) != counts:
            raise ValueError("recorded tree lower-bound counters differ")
        return True
    if present(partial):
        raise ValueError("complete native tree has unexpected partial counters")
    return False
