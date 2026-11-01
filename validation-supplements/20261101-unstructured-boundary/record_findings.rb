# frozen_string_literal: true

require_relative "boundary_check"
B = UnstructuredBoundaryCheck

FINDINGS = {
  "unstructured_beam-1.0-oc-medium_mpi_r2" => {
    "category" => "incomplete_aos_halo_transfer",
    "explanation" => "ElementDynamic contains two doubles, but each halo Sendrecv transfers only n contiguous MPI_DOUBLE values. This updates only the first n/2 ElementDynamic entries in each ghost row, leaving its latter half stale.",
    "source_lines" => [[32, 35], [180, 192]],
    "prior_confirmation" => "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation/scientific-followup-hold.json"
  },
  "unstructured_deepseek-v4-flash_hybrid_r5" => {
    "category" => "reversed_halo_destinations",
    "explanation" => "The first vertical Sendrecv receives from down_rank into h_recv_up, which is copied to the top ghost row; the second receives from up_rank into h_recv_down, copied to the bottom ghost row. The left/right exchanges have the same reversal. Thus the received neighbor data is installed on the opposite side. Receives from MPI_PROC_NULL also leave host buffers unchanged, while those buffers are copied without a neighbor guard.",
    "source_lines" => [[366, 392], [409, 424]]
  },
  "unstructured_gpt-5.6-luna-low_mpi_r3" => {
    "category" => "aos_halo_sent_as_scalar_energies",
    "explanation" => "cur holds ElementDynamic pairs (current_energy,total_flux), but sends use n MPI_DOUBLE from cur.data(). Receivers store these n alternating energy/flux scalars in flat energy arrays and index them as one energy per column. Only half the source row is transmitted and accumulated flux is consumed as neighbor energy.",
    "source_lines" => [[13, 17], [47, 62]]
  },
  "unstructured_gpt-5.6-luna-xhigh_hybrid_r1" => {
    "category" => "incomplete_aos_halo_transfer",
    "explanation" => "Device state is an array of two-double ElementDynamic structs, explicitly size-asserted as such. Boundary copies nevertheless copy n_root*sizeof(val_t), then MPI transfers n_root doubles and the receive copies write the same half-row extent back into struct arrays. Only the first half of each ghost row is refreshed.",
    "source_lines" => [[38, 46], [343, 407]],
    "timing_correction_provenance" => "Inspected the e8d10c43d7fcdca42862537b0eb7d0d5fab6da66..e897bbe48e877ecbd8873ee1c666b6f394c0344b diff for this file: only the timing synchronization/reduction block changes; the defective halo-transfer code is identical to the original."
  },
  "unstructured_gpt-5.6-terra-medium_hybrid_r5" => {
    "category" => "wrong_device_row_staged_for_halo",
    "explanation" => "Owned device rows are 1 through localRows, but the second device-to-host copy in exchangeHalos stages row localRows+1 (the bottom ghost row) instead of row localRows (the last owned row). The following downward MPI_Sendrecv sends host row localRows, which is never refreshed after zero initialization for this decomposition. Thus ranks receive stale zero data from the neighbor above.",
    "source_lines" => [[37, 50], [77, 106]]
  },
  "unstructured_gpt-6-luna-medium_mpi_r5" => {
    "category" => "element_count_used_as_byte_count",
    "explanation" => "Each halo row contains n two-double ElementDynamic structs, but MPI_Sendrecv uses MPI_BYTE with count n, not n*sizeof(ElementDynamic). Only one sixteenth of the row's bytes is transferred. The remaining halo entries stay at their initial values and are nevertheless read as neighbors.",
    "source_lines" => [[35, 39], [148, 183]]
  },
  "unstructured_qwen3.7-plus_mpi_r1" => {
    "category" => "incomplete_aos_halo_transfer",
    "explanation" => "The state is an array of two-double ElementDynamic structs. Both nonblocking sends and receives start at current_energy but transfer only n_elems_root MPI_DOUBLE values, refreshing only the first half of each ghost row instead of the full row.",
    "source_lines" => [[35, 39], [189, 224]]
  },
  "unstructured_qwen3.7-plus_hybrid_r4" => {
    "category" => "stale_and_wrong_device_buffer_halos",
    "explanation" => "exchangeGhostCells unpacks recv_* into host ghost cells before issuing this iteration's MPI receives, so the subsequently uploaded ghosts are one exchange old. In addition, the upload always targets world.d_elements_dynamic, while the simulation reads a d_current pointer that swaps with d_swap each iteration. Thus every other iteration reads ghosts from the other device allocation, which is not initialized or refreshed by that upload. The world pointers are only rebound after the entire loop.",
    "source_lines" => [[266, 304], [312, 328], [339, 399]],
    "timing_correction_provenance" => "Inspected the e8d10c43d7fcdca42862537b0eb7d0d5fab6da66..e897bbe48e877ecbd8873ee1c666b6f394c0344b diff for this file: only the local-duration/MPI_MAX timing reduction changes; the faulty ghost exchange and device-buffer handling are unchanged."
  }
}.freeze

if $PROGRAM_NAME == __FILE__
  verification = B.read_json(File.join(B::EVIDENCE, "verification.json"))
  failed = verification.fetch("failures").to_h { |row| [row.fetch("id"), row] }
  raise "Failure set needs further source inspection" unless failed.keys.sort == FINDINGS.keys.sort
  csv = CSV.read(File.join(B::RELEASE, "release/scored_results.csv"), headers: true)
  findings = failed.map do |id, row|
    source_path = File.join(row.fetch("source_path"), "unstructured/unstructured.cpp")
    source = B.capture("git", "-C", B::SOURCE, "show", "#{row.fetch('source_commit')}:#{source_path}")
    group = csv.select { |r| r["benchmark"] == "unstructured" && r["par_type"] == row.fetch("backend") && r["benchmark_success"] == "true" }.sort_by { |r| Float(r["benchmark_median_time"]) }
    previous = group.find { |r| [r["benchmark"], r["model"], r["par_type"], "r#{r['run']}"].join('_') == id }
    FINDINGS.fetch(id).merge("id" => id, "source_commit" => row.fetch("source_commit"),
      "source_path" => source_path, "source_file_sha256" => Digest::SHA256.hexdigest(source),
      "result_sha256" => row.fetch("result_sha256"), "observed_comparison_failure" => row.fetch("comparison"),
      "prior_backend_rank" => previous && group.index(previous) + 1,
      "prior_backend_successes" => group.size, "prior_median_ms" => previous && Float(previous["benchmark_median_time"]),
      "disposition" => "fail_validation; preserve original source and all measurements; no algorithm repair")
  end
  B.write_json(File.join(B::EVIDENCE, "static-findings.json"), {
    "recorded_at" => Time.now.utc.iso8601, "review_type" => "operator targeted static inspection of only the failed cases",
    "verification_sha256" => B.sha(File.join(B::EVIDENCE, "verification.json")),
    "scope" => "Explain observed numerical failures, not a general correctness proof for passing programs.",
    "original_case_blind_spot" => "Corner-only forcing with nearest-neighbor propagation: the original 256x256,20-iteration test on four ranks cannot carry nonzero state to the nearest subdomain boundary in either a four-way row split or a 2x2 split. The fixed supplemental 32x32,512-iteration case exercises those boundaries.",
    "records" => findings, "model_requests" => 0, "extra_program_executions" => 0,
    "source_changes" => 0, "performance_reruns" => 0
  })
  FileUtils.cp(__FILE__, B::EVIDENCE)
  puts JSON.pretty_generate(findings)
end
