# frozen_string_literal: true

require "spec_helper"

# Mock Rails for generator testing (must be defined before loading the generator)
# This needs to be set up before requiring the generator file
module Rails
  VERSION = Struct.new(:major, :minor).new(7, 0) unless defined?(VERSION)

  module Generators
    class Base
      def self.source_root(path = nil)
        @source_root = path if path
        @source_root
      end

      def self.class_option(*); end
      def self.desc(*); end

      attr_accessor :options, :destination_root

      def initialize(args = [], options = {}, config = {})
        @options = options
        @destination_root = config[:destination_root]
      end

      def template(source, destination); end
      def migration_template(source, destination, options = {}); end
      def generate(*args); end
      def say(message, color = nil); end
    end
  end

  def self.root
    Pathname.new(File.expand_path("../../..", __dir__))
  end
end

# Prevent the generator from trying to load the real Rails generators
$LOADED_FEATURES << "rails/generators/base.rb"

# Now require the generator after Rails mock is set up
require "generators/vectra/install_generator"

RSpec.describe Vectra::Generators::InstallGenerator, type: :generator do
  let(:destination_root) { File.expand_path("../../../tmp/generator_test", __dir__) }

  before do
    FileUtils.rm_rf(destination_root)
    FileUtils.mkdir_p(destination_root)
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  def run_generator(args = [], options = {})
    generator_class = Vectra::Generators::InstallGenerator
    generator = generator_class.new(args, options, destination_root: destination_root)

    # Mock template method to actually copy files
    allow(generator).to receive(:template) do |source, destination|
      source_path = File.join(generator_class.source_root, source)
      dest_path = File.join(destination_root, destination)

      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(dest_path))

      # For ERB templates, process them
      if File.exist?(source_path)
        content = File.read(source_path)
        # Simple ERB processing (for testing purposes)
        content.gsub!(/<%=\s*options\[:provider\]\s*%>/, options[:provider] || "pgvector")
        content.gsub!(/<%=\s*options\[:database_url\]\s*%>/, options[:database_url] || "")
        content.gsub!(/<%-\s*if.*?-%>.*?<%-\s*end\s*-%>/m, "")
        File.write(dest_path, content)
      end
    end

    # Mock migration_template
    allow(generator).to receive(:migration_template) do |source, destination|
      source_path = File.join(generator_class.source_root, source)
      dest_path = File.join(destination_root, destination)

      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.cp(source_path, dest_path) if File.exist?(source_path)
    end

    # Mock generate method
    allow(generator).to receive(:generate)

    # Mock say method for output
    allow(generator).to receive(:say)

    generator
  end

  describe "with default options (pgvector)" do
    it "generates initializer file" do
      generator = run_generator

      expect(generator).to receive(:template).with(
        "vectra.rb",
        "config/initializers/vectra.rb"
      )

      generator.create_initializer_file
    end

    it "generates migration for pgvector" do
      generator = run_generator

      expect(generator).to receive(:generate).with(:migration, "EnablePgvectorExtension")
      expect(generator).to receive(:migration_template).with(
        "enable_pgvector_extension.rb",
        "db/migrate/enable_pgvector_extension.rb",
        migration_version: "[7.0]"
      )

      generator.create_migration
    end

    it "shows pgvector instructions" do
      generator = run_generator

      expect(generator).to receive(:say).with("\n")
      expect(generator).to receive(:say).with("Vectra has been installed!", :green)
      expect(generator).to receive(:say).at_least(:once)

      generator.show_readme
    end
  end

  describe "with pinecone provider" do
    let(:options) { { provider: "pinecone" } }

    it "does not generate migration" do
      generator = run_generator([], options)

      expect(generator).not_to receive(:migration_template)

      generator.create_migration
    end

    it "shows pinecone instructions" do
      generator = run_generator([], options)

      expect(generator).to receive(:say).with("Vectra has been installed!", :green)
      expect(generator).to receive(:say).with(/pinecone/, any_args).at_least(:once)

      generator.show_readme
    end
  end

  describe "with qdrant provider" do
    let(:options) { { provider: "qdrant" } }

    it "does not generate migration" do
      generator = run_generator([], options)

      expect(generator).not_to receive(:migration_template)

      generator.create_migration
    end

    it "shows qdrant instructions" do
      generator = run_generator([], options)

      expect(generator).to receive(:say).with("Vectra has been installed!", :green)
      expect(generator).to receive(:say).with(/qdrant/, any_args).at_least(:once)

      generator.show_readme
    end
  end

  describe "with weaviate provider" do
    let(:options) { { provider: "weaviate" } }

    it "does not generate migration" do
      generator = run_generator([], options)

      expect(generator).not_to receive(:migration_template)

      generator.create_migration
    end

    it "shows weaviate instructions" do
      generator = run_generator([], options)

      expect(generator).to receive(:say).with("Vectra has been installed!", :green)
      expect(generator).to receive(:say).with(/weaviate/, any_args).at_least(:once)

      generator.show_readme
    end
  end

  describe "with instrumentation enabled" do
    let(:options) { { provider: "pgvector", instrumentation: true } }

    it "shows instrumentation message" do
      generator = run_generator([], options)

      expect(generator).to receive(:say).with("Vectra has been installed!", :green)
      expect(generator).to receive(:say).with(/Instrumentation is enabled/, any_args)

      generator.show_readme
    end
  end

  describe "with custom database URL" do
    let(:options) { { provider: "pgvector", database_url: "postgres://custom/db" } }

    it "passes database_url to template" do
      generator = run_generator([], options)

      expect(generator).to receive(:template).with(
        "vectra.rb",
        "config/initializers/vectra.rb"
      )

      generator.create_initializer_file
    end
  end

  describe "#migration_version" do
    it "returns Rails version format" do
      generator = run_generator

      expect(generator.send(:migration_version)).to eq("[7.0]")
    end

    it "handles different Rails versions" do
      stub_const("Rails::VERSION::MAJOR", 6)
      stub_const("Rails::VERSION::MINOR", 1)

      generator = run_generator

      expect(generator.send(:migration_version)).to eq("[6.1]")
    end
  end

  describe "instruction methods" do
    let(:generator) { run_generator }

    describe "#show_pinecone_instructions" do
      it "outputs pinecone-specific instructions" do
        expect(generator).to receive(:say).with(/credentials/, any_args)
        expect(generator).to receive(:say).with(/pinecone/, any_args)
        expect(generator).to receive(:say).with(/api_key/, any_args)
        expect(generator).to receive(:say).at_least(:once)

        generator.send(:show_pinecone_instructions)
      end
    end

    describe "#show_pgvector_instructions" do
      it "outputs pgvector-specific instructions" do
        expect(generator).to receive(:say).with(/migrations/, any_args)
        expect(generator).to receive(:say).with(/rails db:migrate/, any_args)
        expect(generator).to receive(:say).at_least(:once)

        generator.send(:show_pgvector_instructions)
      end
    end

    describe "#show_qdrant_instructions" do
      it "outputs qdrant-specific instructions" do
        expect(generator).to receive(:say).with(/credentials/, any_args)
        expect(generator).to receive(:say).with(/qdrant/, any_args)
        expect(generator).to receive(:say).at_least(:once)

        generator.send(:show_qdrant_instructions)
      end
    end

    describe "#show_weaviate_instructions" do
      it "outputs weaviate-specific instructions" do
        expect(generator).to receive(:say).with(/credentials/, any_args)
        expect(generator).to receive(:say).with(/weaviate/, any_args)
        expect(generator).to receive(:say).at_least(:once)

        generator.send(:show_weaviate_instructions)
      end
    end
  end

  describe "integration test" do
    it "runs full generator with all callbacks" do
      generator = run_generator([], { provider: "pgvector", instrumentation: true })

      expect do
        generator.create_initializer_file
        generator.create_migration
        generator.show_readme
      end.not_to raise_error
    end
  end
end
