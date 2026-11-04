require 'csv'
require 'json'
require 'digest'
require 'open3'
require 'fileutils'

root = ENV.fetch('WINNER_AUDIT_RELEASE', '/home/petert/llm-eval-local')
generated = '/home/petert/llm_para_experiments'
dest = __dir__
raise 'Copy these scripts to a fresh local /tmp workspace first' unless File.realpath(dest).start_with?('/tmp/')
raise 'Existing inventory: use a fresh workspace' if File.exist?("#{dest}/inventory.json")
def git(repo, *args)
  out, err, status = Open3.capture3('git', '-C', repo, *args)
  raise err unless status.success?
  out
end
raise 'Use the audited release checkout (WINNER_AUDIT_RELEASE)' unless git(root, 'rev-parse', 'HEAD').strip == 'c75207d5608801d820eceffe4ffeae6576e4be51'
catalog = JSON.parse(File.read("#{root}/release/catalog.json"))
winners = JSON.parse(File.read("#{root}/release/winners.json"))
ids = winners.map { |w| w.fetch('id') }
rows = CSV.read("#{root}/release/scored_results.csv", headers: true).to_h do |r|
  ["#{r['benchmark']}_#{r['model']}_#{r['par_type']}_r#{r['run']}", r.to_h]
end
validations = {}
campaigns = {}
catalog.fetch('campaigns').each do |c|
  %w[validation_records corrected_validation_records].each do |field|
    next unless c[field]
    Dir.glob("#{root}/#{c[field]}").sort.each do |f|
      File.foreach(f) do |line|
        rec = JSON.parse(line)
        next unless ids.include?(rec['id'])
        validations[rec['id']] = rec.merge('evidence_file' => f.delete_prefix(root + '/'))
        campaigns[rec['id']] = c
      end
    end
  end
end
inventory = winners.map do |w|
  id = w.fetch('id')
  row = rows.fetch(id)
  v = validations.fetch(id)
  c = campaigns.fetch(id)
  commit = row['timing_fixed'] == 'true' ? row.fetch('corrected_source_commit') :
    (v['source_commit'] || v.dig('source', 'commit') || c.fetch('source_commit'))
  raise 'missing commit' if commit.to_s.empty?
  prefix = row.fetch('source_path') + '/'
  tree = git(generated, 'ls-tree', '-r', '--name-only', commit, '--', row.fetch('source_path')).lines.map(&:strip)
  files = tree.select { |f| f.match?(/\.(?:cpp|cu|h|hpp)$/) || File.basename(f) == 'CMakeLists.txt' }
  raise "empty #{id}" if files.empty?
  pinned = files.to_h do |f|
    relative = f.delete_prefix(prefix)
    bytes = git(generated, 'show', "#{commit}:#{f}")
    target = "#{dest}/sources/#{id}/#{relative}"
    FileUtils.mkdir_p(File.dirname(target))
    File.binwrite(target, bytes)
    [relative, { 'sha256' => Digest::SHA256.hexdigest(bytes), 'lines' => bytes.lines.size }]
  end
  record = w.merge('source_commit' => commit, 'source_path' => row.fetch('source_path'),
    'files' => pinned, 'validation_evidence' => v.fetch('evidence_file'))
  FileUtils.mkdir_p("#{dest}/validation")
  File.write("#{dest}/validation/#{id}.json", JSON.pretty_generate(v) + "\n")
  puts [w['cell'], id, commit[0,8], pinned.map { |p,m| "#{p}:#{m['lines']}" }.join(' ')].join("\t")
  record
end
input_repo = '/home/petert/llm_eval/benchmarks'
input_commit = '2bc11aeac658a87b5cae25d03e0669f65d32922e'
git(input_repo, 'ls-tree', '-r', '--name-only', input_commit).lines.map(&:strip).each do |f|
  next unless f.match?(/\.(?:cpp|cu|h|hpp)$/) || File.basename(f) == 'CMakeLists.txt'
  target = "#{dest}/reference/#{f.delete_prefix('benchmarks/')}"
  FileUtils.mkdir_p(File.dirname(target))
  File.binwrite(target, git(input_repo, 'show', "#{input_commit}:#{f}"))
end
File.write("#{dest}/inventory.json", JSON.pretty_generate({
  'release_commit' => git(root, 'rev-parse', 'HEAD').strip,
  'release_winners_sha256' => Digest::SHA256.file("#{root}/release/winners.json").hexdigest,
  'input_commit' => input_commit, 'winners' => inventory
}) + "\n")
