# frozen_string_literal: true
require_relative "artifact_common"

module BatchChecksums
  def self.run(root, check: false)
    # Children first: each parent includes its child manifests but not itself.
    Dir.glob(File.join(root, "batches", "**", "checksums.sha256"))
       .sort_by { |file| [-file.count("/"), file] }.each do |manifest|
      directory = File.dirname(manifest)
      content = LocalEvalArtifact.regular_files(directory).reject { |file| file == manifest }.map do |file|
        "#{LocalEvalArtifact.sha256(file)}  #{LocalEvalArtifact.relative_path(directory, file)}\n"
      end.join
      if check
        raise "stale batch checksum manifest #{LocalEvalArtifact.relative_path(root, manifest)}" unless File.binread(manifest) == content
      else
        File.binwrite(manifest, content)
      end
    end
  end
end
