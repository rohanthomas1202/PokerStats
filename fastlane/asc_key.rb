# App Store Connect API key for fastlane's uploads and for xcodebuild's
# cloud-managed signing. Plain Ruby, no fastlane DSL, so
# .github/scripts/ios-release-test.sh can run it. Never prints the key.
require "shellwords"
require "tmpdir"

module AscKey
  # Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH or ASC_PRIVATE_KEY.
  # xcodebuild needs a file, so a key given only as ASC_PRIVATE_KEY is
  # written to a 0600 .p8 under RUNNER_TEMP (or the system temp folder) and
  # deleted when the process exits.
  def self.load(env = ENV)
    id = env["ASC_KEY_ID"].to_s
    issuer = env["ASC_ISSUER_ID"].to_s
    path = env["ASC_KEY_PATH"].to_s
    content = env["ASC_PRIVATE_KEY"].to_s
    have_file = !path.empty? && File.file?(path)
    if id.empty? || issuer.empty? || (!have_file && content.empty?)
      raise ArgumentError, "ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY (or ASC_KEY_PATH) are required for signing/upload."
    end

    unless have_file
      dir = env["RUNNER_TEMP"].to_s.empty? ? Dir.tmpdir : env["RUNNER_TEMP"]
      path = File.join(dir, "AuthKey_fastlane_#{Process.pid}.p8")
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(content) }
      File.chmod(0o600, path)
      at_exit { File.delete(path) if File.exist?(path) }
    end
    { id: id, issuer: issuer, path: path }
  end

  # Passed to both archive (xcargs) and export (export_xcargs).
  def self.xcodebuild_flags(key)
    [
      "-allowProvisioningUpdates",
      "-authenticationKeyPath", key[:path],
      "-authenticationKeyID", key[:id],
      "-authenticationKeyIssuerID", key[:issuer]
    ].shelljoin
  end
end
