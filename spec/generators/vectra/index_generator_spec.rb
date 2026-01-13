# frozen_string_literal: true

require "spec_helper"

# Mock Rails for generator testing (must be defined before loading the generator)
module Rails
  unless defined?(VERSION)
    module VERSION
      MAJOR = 7
      MINOR = 0
    end
  end

  module Generators
    class Base
      def self.source_root(path = nil)
        @source_root = path if path
        @source_root
      end

      def self.argument(*); end
      def self.class_option(*); end
      def self.desc(*); end

      attr_accessor :options, :destination_root

      def initialize(_args = [], options = {}, config = {})
        @options = options
        @destination_root = config[:destination_root] || Dir.pwd
      end

      def template(_source, _destination); end
      def migration_template(_source, _destination, _options = {}); end
      def generate(*_args); end
      def say(_message, _color = nil); end

      def create_file(path, content)
        absolute = File.join(destination_root, path)
        FileUtils.mkdir_p(File.dirname(absolute))
        File.write(absolute, content)
      end
    end
  end

  def self.root
    Pathname.new(File.expand_path("../../..", __dir__))
  end
end

# Prevent the generator from trying to load the real Rails generators
$LOADED_FEATURES << "rails/generators/base.rb"

require "generators/vectra/index_generator"

# rubocop:disable RSpec/FilePath, RSpec/SpecFilePathFormat
RSpec.describe Vectra::Generators::IndexGenerator, type: :generator do
  let(:destination_root) { File.expand_path("../../../tmp/index_generator_test", __dir__) }

  before do
    FileUtils.rm_rf(destination_root)
    FileUtils.mkdir_p(destination_root)
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  def run_generator(args = [], options = {})
    options = { provider: "qdrant", dimension: 1536 }.merge(options)
    Vectra::Generators::IndexGenerator.new(
      args,
      options,
      destination_root: destination_root
    )
  end

  def read_relative(path)
    File.read(File.join(destination_root, path))
  end

  describe "with qdrant provider" do
    let(:generator) { run_generator(%w[Product embedding], provider: "qdrant", dimension: 1536) }

    it "does not create pgvector migration" do
      generator.create_migration_for_pgvector

      files = Dir[File.join(destination_root, "db/migrate/*.rb")]
      expect(files).to be_empty
    end

    it "creates a model concern with has_vector" do
      generator.create_model_concern

      concern_path = "app/models/concerns/product_vector.rb"
      expect(File.exist?(File.join(destination_root, concern_path))).to be true

      content = read_relative(concern_path)
      expect(content).to include("module ProductVector")
      expect(content).to include("has_vector :embedding")
      expect(content).to include("provider: :qdrant")
      expect(content).to include('index: "products"')
      expect(content).to include("dimension: 1536")
    end

    it "updates existing model to include concern" do
      model_path = File.join(destination_root, "app/models/product.rb")
      FileUtils.mkdir_p(File.dirname(model_path))
      File.write(model_path, <<~RUBY)
        class Product < ApplicationRecord
        end
      RUBY

      generator.update_model_file

      content = File.read(model_path)
      expect(content).to include("include ProductVector")
    end

    it "creates model file when missing" do
      generator.update_model_file

      model_path = File.join(destination_root, "app/models/product.rb")
      expect(File.exist?(model_path)).to be true

      content = File.read(model_path)
      expect(content).to include("class Product < ApplicationRecord")
      expect(content).to include("include ProductVector")
    end

    it "updates vectra.yml without secrets" do
      generator.update_vectra_config

      config_path = File.join(destination_root, "config/vectra.yml")
      expect(File.exist?(config_path)).to be true

      content = File.read(config_path)
      expect(content).to include("products:")
      expect(content).to include("provider: qdrant")
      expect(content).to include("index: products")
      expect(content).to include("dimension: 1536")
      expect(content).to include("do NOT store API keys here")
    end
  end

  describe "with pgvector provider" do
    let(:generator) { run_generator(%w[Product embedding], provider: "pgvector", dimension: 384) }

    it "creates a pgvector migration with correct dimension" do
      generator.create_migration_for_pgvector

      files = Dir[File.join(destination_root, "db/migrate/*add_embedding_to_products.rb")]
      expect(files.size).to eq(1)

      content = File.read(files.first)
      expect(content).to include("add_column :products, :embedding, :vector, limit: 384")
      expect(content).to include("ActiveRecord::Migration[7.0]")
    end
  end
end
# rubocop:enable RSpec/FilePath, RSpec/SpecFilePathFormat

