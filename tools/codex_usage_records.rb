# frozen_string_literal: true
require_relative '../method/codex-usage/codex_usage'
require_relative '../method/codex-usage/codex_tree_usage'

# Current release loader. The historical single-session method is immutable and
# is also referenced by old validation snapshots; do not extend it in place.
module CodexUsageRecords
  module_function

  def load_records(path)
    records = {}
    File.foreach(path) do |line|
      record = JSON.parse(line)
      if record.is_a?(Hash) && record['schema_version'] == 2
        CodexTreeUsage.validate_record!(record)
      else
        CodexUsage.validate_record!(record)
      end
      id = record.fetch('run_id')
      raise CodexUsage::Invalid, "duplicate usage ID #{id}" if records.key?(id)
      records[id] = record
    end
    raise CodexUsage::Invalid, 'empty usage evidence' if records.empty?
    records
  end
end
