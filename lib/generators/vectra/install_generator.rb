# frozen_string_literal: true

require 'rails/generators/base'

module Vectra
  module Generators
    # Rails generator for installing Vectra
    #
    # @example
    #   rails generate vectra:install
    #   rails generate vectra:install --provider=pinecone
    #   rails generate vectra:install --provider=pgvector --database-url=postgres://localhost/mydb
    #
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      class_option :provider, type: :string, default: 'pgvector',
                              desc: 'Vector database provider (pinecone, pgvector, qdrant, weaviate)'
      class_option :database_url, type: :string, default: nil,
                                  desc: 'PostgreSQL connection URL (for pgvector)'
      class_option :api_key, type: :string, default: nil,
                             desc: 'API key for the provider'
      class_option :instrumentation, type: :boolean, default: false,
                                     desc: 'Enable instrumentation'

      def create_initializer_file
        template 'vectra.rb', 'config/initializers/vectra.rb'
      end

      def create_migration
        return unless options[:provider] == 'pgvector'

        generate "migration", "EnablePgvectorExtension"

        migration_template(
          'enable_pgvector_extension.rb',
          'db/migrate/enable_pgvector_extension.rb',
          migration_version: migration_version
        )
      end

      def show_readme
        say "\n"
        say "Vectra has been installed!", :green
        say "\n"
        say "Next steps:", :yellow
        say "  1. Add your #{options[:provider]} credentials to Rails credentials:"
        say "     $ rails credentials:edit", :cyan
        say "\n"

        case options[:provider]
        when 'pinecone'
          show_pinecone_instructions
        when 'pgvector'
          show_pgvector_instructions
        when 'qdrant'
          show_qdrant_instructions
        when 'weaviate'
          show_weaviate_instructions
        end

        if options[:instrumentation]
          say "\n"
          say "  📊 Instrumentation is enabled!", :green
          say "     Add New Relic or Datadog setup to config/initializers/vectra.rb"
        end
      end

      private

      def show_pinecone_instructions
        say "  2. Add to credentials:", :yellow
        say "     pinecone:", :cyan
        say "       api_key: your_api_key_here", :cyan
        say "       environment: us-east-1", :cyan
        say "\n"
        say "  3. Create an index in Pinecone dashboard"
        say "\n"
        say "  4. Use in your app:", :yellow
        say "     @client = Vectra::Client.new", :cyan
        say "     @client.upsert(index: 'my-index', vectors: [...])", :cyan
      end

      def show_pgvector_instructions
        say "  2. Run migrations:", :yellow
        say "     $ rails db:migrate", :cyan
        say "\n"
        say "  3. Create a vector index:", :yellow
        say "     $ rails runner 'Vectra::Client.new.provider.create_index(name: \"documents\", dimension: 384)'", :cyan
        say "\n"
        say "  4. Use in your app:", :yellow
        say "     @client = Vectra::Client.new", :cyan
        say "     @client.upsert(index: 'documents', vectors: [...])", :cyan
      end

      def show_qdrant_instructions
        say "  2. Add to credentials:", :yellow
        say "     qdrant:", :cyan
        say "       api_key: your_api_key_here", :cyan
        say "       host: https://your-cluster.qdrant.io", :cyan
      end

      def show_weaviate_instructions
        say "  2. Add to credentials:", :yellow
        say "     weaviate:", :cyan
        say "       api_key: your_api_key_here", :cyan
        say "       host: https://your-cluster.weaviate.io", :cyan
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
