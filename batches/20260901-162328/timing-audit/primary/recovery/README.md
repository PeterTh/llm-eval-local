# Initial pilot response recovery

The initial event checker incorrectly rejected Codex diagnostic items saying
code mode was disabled. These were not tool calls; the model turns completed.
The coordinator was stopped after its in-flight workers completed. The original
audit is preserved at `/home/petert/llm_timing_audit/20260928-claude5-initial-pilot`. No validation was repeated.

The corrected checker accepts diagnostic items, still rejects every tool item,
and still requires a completed turn and schema-valid, source-matched response.
Source inventory, prompt, schema, trial selection, and CLI restrictions are unchanged.
8 earliest completed responses were recovered without another model
call. All 21 original attempt logs were copied unchanged;
4 final in-flight
attempts lack coordinator metadata and were not selected. Malformed responses
are listed separately and were not accepted or edited.
Recovered attempts retain their actual original runner hash and metadata.
The initial manifest, initial runner, recovery procedure, chosen response hashes,
and compact attempt diagnostics/usage are retained here. Raw logs remain at home,
not in the compact Git artifact.
