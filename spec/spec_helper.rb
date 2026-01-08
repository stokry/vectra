# frozen_string_literal: true

require "bundler/setup"
require "simplecov"

# Start SimpleCov for coverage reporting
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"

  track_files "lib/**/*.rb"

  add_group "Core", "lib/vectra"
  add_group "Providers", "lib/vectra/providers"

  # Lower coverage thresholds when integration tests are skipped (no API credentials)
  if ENV["PINECONE_API_KEY"]
    minimum_coverage 90
    minimum_coverage_by_file 80
  else
    # Without integration tests and without ActiveRecord/Generator tests, lower threshold
    minimum_coverage 60
  end
end

require "vectra"

# Require support files
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Clean up configuration after each example
  config.after do
    Vectra.reset_configuration!
  end

  # Configure RSpec to be more strict
  config.raise_errors_for_deprecations!
  config.warnings = true

  # Show the slowest examples
  config.profile_examples = 10 if ENV["PROFILE"]
end
