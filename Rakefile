# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :spec do
  desc "Run unit tests only"
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = "spec/vectra/**/*_spec.rb"
  end

  desc "Run integration tests only"
  RSpec::Core::RakeTask.new(:integration) do |t|
    t.pattern = "spec/integration/**/*_spec.rb"
  end
end

desc "Generate documentation"
task :docs do
  require "yard"
  YARD::CLI::Yardoc.run("--output-dir", "doc", "lib/**/*.rb", "-", "README.md", "CHANGELOG.md")
end

desc "Generate CHANGELOG.md"
task :changelog do
  puts "Generating CHANGELOG.md..."
  system("github_changelog_generator") || puts("Install with: gem install github_changelog_generator")
end

desc "Bump version to VERSION"
task :bump_version, [:version] do |t, args|
  version = args[:version]
  raise "Version required: rake bump_version[1.2.3]" unless version

  version_file = "lib/vectra/version.rb"
  content = File.read(version_file)
  new_content = content.gsub(/VERSION = "[^"]+"/, "VERSION = \"#{version}\"")
  File.write(version_file, new_content)
  puts "Version bumped to #{version}"
end
