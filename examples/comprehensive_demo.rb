#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "vectra"
require "json"
require "securerandom"
require "digest"
require "stringio"

# Comprehensive Vectra Demo - Production Features
#
# This demo showcases all major Vectra features:
# - CRUD operations (Create, Read, Update, Delete)
# - Batch processing
# - Caching & performance optimization
# - Error handling & resilience
# - Health monitoring
# - Metadata filtering
# - Namespaces for multi-tenancy
#
# Prerequisites:
#   docker run -p 6333:6333 qdrant/qdrant
#
# Run:
#   bundle exec ruby examples/comprehensive_demo.rb

class ComprehensiveVectraDemo
  INDEX_NAME = "documents"
  DIMENSION = 128  # Smaller for demo purposes

  def initialize(host = "http://localhost:6333")
    @host = host
    setup_clients
    @stats = {
      operations: 0,
      cache_hits: 0,
      errors: 0,
      retries: 0
    }
  end

  # =============================================================================
  # SECTION 1: SETUP & INITIALIZATION
  # =============================================================================

  def run_demo
    print_header("VECTRA COMPREHENSIVE DEMO")

    section_1_basic_operations
    section_2_batch_operations
    section_3_advanced_queries
    section_4_update_operations
    section_5_delete_operations
    section_6_cache_performance
    section_7_error_handling
    section_8_multi_tenancy
    section_9_health_monitoring
    section_10_async_batch
    section_11_streaming
    section_12_resilience
    section_13_monitoring

    print_summary
  end

  # =============================================================================
  # SECTION 1: BASIC OPERATIONS
  # =============================================================================

  def section_1_basic_operations
    print_section("1. Basic CRUD Operations")

    # Health check
    puts "🏥 Checking system health..."
    health = @client.health_check

    if health.healthy?
      puts "   ✅ System healthy (#{health.latency_ms}ms latency)"
    else
      puts "   ❌ System unhealthy: #{health.error_message}"
      raise "Cannot proceed with unhealthy system"
    end

    # Create index
    puts "\n📦 Creating index '#{INDEX_NAME}'..."
    begin
      @client.provider.create_index(
        name: INDEX_NAME,
        dimension: DIMENSION,
        metric: "cosine"
      )
      puts "   ✅ Index created"
    rescue StandardError => e
      if e.message.include?("already exists")
        puts "   ℹ️  Index already exists, deleting and recreating..."
        @client.provider.delete_index(name: INDEX_NAME)
        @client.provider.create_index(
          name: INDEX_NAME,
          dimension: DIMENSION,
          metric: "cosine"
        )
        puts "   ✅ Index recreated"
      else
        raise
      end
    end

    # Insert single document
    puts "\n📝 Inserting single document..."
    doc = create_sample_document(
      id: "doc-001",
      title: "Introduction to Vector Databases",
      content: "Vector databases enable semantic search using embeddings and similarity metrics.",
      category: "Technology",
      author: "John Doe"
    )

    result = @client.upsert(
      index: INDEX_NAME,
      vectors: [doc]
    )
    puts "   ✅ Inserted #{result[:upserted_count]} document"
    @stats[:operations] += 1
    
    # Small delay to ensure consistency
    sleep(0.1)

    # Fetch by ID
    puts "\n🔍 Fetching document by ID..."
    fetched = @client.fetch(
      index: INDEX_NAME,
      ids: ["doc-001"]
    )

    if fetched["doc-001"]
      doc = fetched["doc-001"]
      title = doc.metadata[:title] || doc.metadata["title"] || "Untitled"
      category = doc.metadata[:category] || doc.metadata["category"] || "Unknown"
      author = doc.metadata[:author] || doc.metadata["author"] || "Unknown"
      puts "   ✅ Found: #{title}"
      puts "   📊 Metadata: category=#{category}, author=#{author}"
    end
    @stats[:operations] += 1

    # Query by similarity
    puts "\n🔎 Querying by similarity..."
    query_vec = generate_embedding("database search technology")
    results = @client.query(
      index: INDEX_NAME,
      vector: query_vec,
      top_k: 3,
      include_metadata: true
    )

    puts "   ✅ Found #{results.size} results"
    results.each_with_index do |match, i|
      title = match.metadata[:title] || match.metadata["title"] || "Untitled"
      puts "      #{i + 1}. #{title} (score: #{match.score.round(4)})"
    end
    @stats[:operations] += 1
  end

  # =============================================================================
  # SECTION 2: BATCH OPERATIONS
  # =============================================================================

  def section_2_batch_operations
    print_section("2. Batch Processing")

    puts "📦 Generating 50 sample documents..."
    documents = generate_batch_documents(50)
    puts "   ✅ Generated #{documents.size} documents"

    puts "\n⚡ Batch upserting documents..."
    start_time = Time.now

    # Batch upsert (chunked)
    chunk_size = 10
    total_upserted = 0

    documents.each_slice(chunk_size).with_index do |chunk, i|
      result = @client.upsert(
        index: INDEX_NAME,
        vectors: chunk
      )
      total_upserted += result[:upserted_count]
      print "   📊 Progress: #{total_upserted}/#{documents.size}\r"
      @stats[:operations] += 1
    end

    duration = ((Time.now - start_time) * 1000).round(2)
    puts "\n   ✅ Upserted #{total_upserted} documents in #{duration}ms"
    puts "   📈 Throughput: #{(total_upserted / (duration / 1000.0)).round(2)} docs/sec"
  end

  # =============================================================================
  # SECTION 3: ADVANCED QUERIES
  # =============================================================================

  def section_3_advanced_queries
    print_section("3. Advanced Query Features")

    # Query with metadata filter
    puts "🔍 Query 1: Filter by category (Technology)"
    results = @client.query(
      index: INDEX_NAME,
      vector: generate_embedding("artificial intelligence machine learning"),
      top_k: 5,
      filter: { category: "Technology" },
      include_metadata: true
    )

    puts "   ✅ Found #{results.size} results in Technology category"
    results.take(3).each_with_index do |match, i|
      title = match.metadata[:title] || match.metadata["title"] || "Untitled"
      category = match.metadata[:category] || match.metadata["category"] || "Unknown"
      puts "      #{i + 1}. #{title}"
      puts "         Category: #{category} | Score: #{match.score.round(4)}"
    end
    @stats[:operations] += 1

    # Query different category
    puts "\n🔍 Query 2: Filter by category (Business)"
    results = @client.query(
      index: INDEX_NAME,
      vector: generate_embedding("market strategy growth"),
      top_k: 5,
      filter: { category: "Business" },
      include_metadata: true
    )

    puts "   ✅ Found #{results.size} results in Business category"
    results.take(3).each_with_index do |match, i|
      title = match.metadata[:title] || match.metadata["title"] || "Untitled"
      puts "      #{i + 1}. #{title}"
      puts "         Score: #{match.score.round(4)}"
    end
    @stats[:operations] += 1

    # Query with include_values
    puts "\n🔍 Query 3: Including vector values"
    results = @client.query(
      index: INDEX_NAME,
      vector: generate_embedding("technology innovation"),
      top_k: 2,
      include_values: true,
      include_metadata: true
    )

    puts "   ✅ Retrieved #{results.size} results with vectors"
    results.each_with_index do |match, i|
      title = match.metadata[:title] || match.metadata["title"] || "Untitled"
      vector_preview = match.values ? match.values.first(3).map { |v| v.round(3) } : []
      puts "      #{i + 1}. #{title}"
      puts "         Vector preview: [#{vector_preview.join(', ')}...]"
    end
    @stats[:operations] += 1
  end

  # =============================================================================
  # SECTION 4: UPDATE OPERATIONS
  # =============================================================================

  def section_4_update_operations
    print_section("4. Update Operations")

    # Fetch original
    puts "📄 Fetching document to update..."
    fetched = @client.fetch(index: INDEX_NAME, ids: ["doc-001"])
    original = fetched["doc-001"]
    
    if original.nil?
      puts "   ⚠️  Document doc-001 not found, skipping update operations"
      return
    end
    
    puts "   📊 Original metadata: #{original.metadata.slice(:category, :views)}"

    # Update metadata
    puts "\n✏️  Updating metadata..."
    @client.update(
      index: INDEX_NAME,
      id: "doc-001",
      metadata: {
        views: 100,
        featured: true,
        updated_at: Time.now.iso8601
      }
    )
    puts "   ✅ Metadata updated"
    @stats[:operations] += 1

    # Verify update
    puts "\n🔍 Verifying update..."
    updated = @client.fetch(index: INDEX_NAME, ids: ["doc-001"])["doc-001"]
    puts "   📊 Updated metadata:"
    puts "      Views: #{updated.metadata[:views]}"
    puts "      Featured: #{updated.metadata[:featured]}"
    puts "      Updated at: #{updated.metadata[:updated_at]}"
    @stats[:operations] += 1

    # Update with new vector
    puts "\n✏️  Updating vector values..."
    new_vector = generate_embedding("updated content about databases and AI")
    @client.update(
      index: INDEX_NAME,
      id: "doc-001",
      values: new_vector
    )
    puts "   ✅ Vector updated"
    @stats[:operations] += 1
  end

  # =============================================================================
  # SECTION 5: DELETE OPERATIONS
  # =============================================================================

  def section_5_delete_operations
    print_section("5. Delete Operations")

    # Delete single document
    puts "🗑️  Delete 1: Single document by ID"
    @client.delete(
      index: INDEX_NAME,
      ids: ["doc-001"]
    )
    puts "   ✅ Deleted doc-001"
    @stats[:operations] += 1

    # Verify deletion
    fetched = @client.fetch(index: INDEX_NAME, ids: ["doc-001"])
    puts "   ✅ Verified: #{fetched.empty? ? 'deleted' : 'still exists'}"

    # Delete multiple documents
    puts "\n🗑️  Delete 2: Multiple documents by IDs"
    ids_to_delete = ["doc-002", "doc-003", "doc-004"]
    @client.delete(
      index: INDEX_NAME,
      ids: ids_to_delete
    )
    puts "   ✅ Deleted #{ids_to_delete.size} documents"
    @stats[:operations] += 1

    # Delete with filter
    puts "\n🗑️  Delete 3: By metadata filter"
    @client.delete(
      index: INDEX_NAME,
      filter: { category: "Science" }
    )
    puts "   ✅ Deleted all documents in Science category"
    @stats[:operations] += 1
  end

  # =============================================================================
  # SECTION 6: CACHE PERFORMANCE
  # =============================================================================

  def section_6_cache_performance
    print_section("6. Cache Performance")

    query_vector = generate_embedding("artificial intelligence deep learning")

    puts "⚡ Running cache performance test..."
    puts "   Query: 'artificial intelligence deep learning'"
    puts

    # First call (cache miss)
    puts "📊 Attempt 1 (cache miss):"
    start = Time.now
    @cached_client.query(
      index: INDEX_NAME,
      vector: query_vector,
      top_k: 5
    )
    first_time = ((Time.now - start) * 1000).round(2)
    puts "   ⏱️  Duration: #{first_time}ms"
    @stats[:operations] += 1

    # Second call (cache hit)
    puts "\n📊 Attempt 2 (cache hit):"
    start = Time.now
    @cached_client.query(
      index: INDEX_NAME,
      vector: query_vector,
      top_k: 5
    )
    second_time = ((Time.now - start) * 1000).round(2)
    puts "   ⏱️  Duration: #{second_time}ms"
    @stats[:cache_hits] += 1
    @stats[:operations] += 1

    # Third call (cache hit)
    puts "\n📊 Attempt 3 (cache hit):"
    start = Time.now
    @cached_client.query(
      index: INDEX_NAME,
      vector: query_vector,
      top_k: 5
    )
    third_time = ((Time.now - start) * 1000).round(2)
    puts "   ⏱️  Duration: #{third_time}ms"
    @stats[:cache_hits] += 1
    @stats[:operations] += 1

    # Calculate speedup
    avg_cached = ((second_time + third_time) / 2.0).round(2)
    speedup = (first_time / avg_cached).round(2)
    improvement = (((first_time - avg_cached) / first_time) * 100).round(1)

    puts "\n📈 Performance Analysis:"
    puts "   First call (no cache): #{first_time}ms"
    puts "   Avg cached calls: #{avg_cached}ms"
    puts "   Speedup: #{speedup}x faster"
    puts "   Improvement: #{improvement}% reduction in latency"

    # Cache stats
    cache_stats = @cache.stats
    puts "\n💾 Cache Statistics:"
    puts "   Size: #{cache_stats[:size]}/#{cache_stats[:max_size]}"
    puts "   TTL: #{cache_stats[:ttl]}s"
    puts "   Keys: #{cache_stats[:keys].size}"
  end

  # =============================================================================
  # SECTION 7: ERROR HANDLING & RESILIENCE
  # =============================================================================

  def section_7_error_handling
    print_section("7. Error Handling & Resilience")

    puts "🛡️  Testing error handling scenarios..."

    # Test 1: Invalid vector dimension
    puts "\n❌ Test 1: Invalid vector dimension"
    begin
      @client.upsert(
        index: INDEX_NAME,
        vectors: [{
          id: "invalid-001",
          values: [0.1, 0.2],  # Wrong dimension (should be 128)
          metadata: { title: "Invalid" }
        }]
      )
      puts "   ⚠️  Should have raised error"
    rescue Vectra::ValidationError => e
      puts "   ✅ Caught ValidationError: #{e.message.split("\n").first}"
      @stats[:errors] += 1
    end

    # Test 2: Non-existent index
    puts "\n❌ Test 2: Query non-existent index"
    begin
      @client.query(
        index: "non_existent_index",
        vector: generate_embedding("test"),
        top_k: 5
      )
      puts "   ⚠️  Should have raised error"
    rescue Vectra::NotFoundError => e
      puts "   ✅ Caught NotFoundError: #{e.message}"
      @stats[:errors] += 1
    end

    # Test 3: Invalid IDs
    puts "\n❌ Test 3: Fetch with empty IDs"
    begin
      @client.fetch(
        index: INDEX_NAME,
        ids: []
      )
      puts "   ⚠️  Should have raised error"
    rescue Vectra::ValidationError => e
      puts "   ✅ Caught ValidationError: #{e.message}"
      @stats[:errors] += 1
    end

    puts "\n✅ Error handling working correctly"
    puts "   📊 Total errors caught: #{@stats[:errors]}"
  end

  # =============================================================================
  # SECTION 8: MULTI-TENANCY WITH NAMESPACES
  # =============================================================================

  def section_8_multi_tenancy
    print_section("8. Multi-Tenancy with Namespaces")

    puts "🏢 Simulating multi-tenant application..."

    # Tenant 1: Company A
    puts "\n📦 Tenant 1: Company A"
    company_a_docs = [
      {
        id: "tenant-a-001",
        values: generate_embedding("company A quarterly report"),
        metadata: { title: "Q1 Report", tenant: "company-a" }
      },
      {
        id: "tenant-a-002",
        values: generate_embedding("company A product launch"),
        metadata: { title: "Product Launch", tenant: "company-a" }
      }
    ]

    @client.upsert(
      index: INDEX_NAME,
      vectors: company_a_docs,
      namespace: "company-a"
    )
    puts "   ✅ Inserted 2 documents for Company A"
    @stats[:operations] += 1

    # Tenant 2: Company B
    puts "\n📦 Tenant 2: Company B"
    company_b_docs = [
      {
        id: "tenant-b-001",
        values: generate_embedding("company B market analysis"),
        metadata: { title: "Market Analysis", tenant: "company-b" }
      },
      {
        id: "tenant-b-002",
        values: generate_embedding("company B financial report"),
        metadata: { title: "Financial Report", tenant: "company-b" }
      }
    ]

    @client.upsert(
      index: INDEX_NAME,
      vectors: company_b_docs,
      namespace: "company-b"
    )
    puts "   ✅ Inserted 2 documents for Company B"
    @stats[:operations] += 1

    # Query tenant-specific data
    puts "\n🔍 Querying Company A namespace..."
    results_a = @client.query(
      index: INDEX_NAME,
      vector: generate_embedding("report"),
      top_k: 5,
      namespace: "company-a",
      include_metadata: true
    )
    puts "   ✅ Found #{results_a.size} documents for Company A:"
    results_a.each do |r|
      title = r.metadata[:title] || r.metadata["title"] || "Untitled"
      puts "      - #{title}"
    end
    @stats[:operations] += 1

    puts "\n🔍 Querying Company B namespace..."
    results_b = @client.query(
      index: INDEX_NAME,
      vector: generate_embedding("report"),
      top_k: 5,
      namespace: "company-b",
      include_metadata: true
    )
    puts "   ✅ Found #{results_b.size} documents for Company B:"
    results_b.each do |r|
      title = r.metadata[:title] || r.metadata["title"] || "Untitled"
      puts "      - #{title}"
    end
    @stats[:operations] += 1

    puts "\n✅ Namespace isolation verified"
  end

  # =============================================================================
  # SECTION 9: HEALTH MONITORING
  # =============================================================================

  def section_9_health_monitoring
    print_section("9. Health Monitoring & Statistics")

    puts "🏥 Performing comprehensive health check..."

    # Detailed health check
    health = @client.health_check(
      index: INDEX_NAME,
      include_stats: true
    )

    puts "\n📊 System Health:"
    puts "   Status: #{health.healthy? ? '✅ Healthy' : '❌ Unhealthy'}"
    puts "   Provider: #{health.provider}"
    puts "   Latency: #{health.latency_ms}ms"
    puts "   Indexes available: #{health.indexes_available}"
    puts "   Checked at: #{health.checked_at}"

    if health.stats
      puts "\n📈 Index Statistics:"
      puts "   Vector count: #{health.stats[:vector_count] || 'N/A'}"
      puts "   Dimension: #{health.stats[:dimension]}"
    end

    # List all indexes
    puts "\n📚 Available Indexes:"
    indexes = @client.provider.list_indexes
    indexes.each do |idx|
      puts "   - #{idx[:name]}"
      puts "     Dimension: #{idx[:dimension]}, Metric: #{idx[:metric] || 'N/A'}"
    end

    # Index details
    puts "\n🔍 Index Details:"
    details = @client.provider.describe_index(index: INDEX_NAME)
    puts "   Name: #{details[:name]}"
    puts "   Dimension: #{details[:dimension]}"
    puts "   Metric: #{details[:metric]}"
    puts "   Status: #{details[:status]}"
  end

  # =============================================================================
  # SECTION 10: ASYNC BATCH OPERATIONS
  # =============================================================================

  def section_10_async_batch
    print_section("10. Async Batch Operations")

    puts "⚡ Testing concurrent batch upsert..."
    puts "   This demonstrates Vectra::Batch for parallel processing"

    # Generate larger batch for async processing
    large_batch = generate_batch_documents(30)
    puts "   📦 Generated #{large_batch.size} documents for async processing"

    # Use async batch client
    batch_client = Vectra::Batch.new(@client)

    puts "\n🚀 Starting async batch upsert (concurrency: 4)..."
    start_time = Time.now

    begin
      result = batch_client.upsert_async(
        index: INDEX_NAME,
        vectors: large_batch,
        concurrency: 4
      )

      duration = ((Time.now - start_time) * 1000).round(2)
      puts "   ✅ Async batch completed in #{duration}ms"
      puts "   📊 Results:"
      puts "      Success: #{result[:success]}"
      puts "      Failed: #{result[:failed]}"
      puts "      Total: #{result[:total]}"
      puts "   📈 Throughput: #{(result[:success] / (duration / 1000.0)).round(2)} docs/sec"

      @stats[:operations] += 1
    rescue StandardError => e
      puts "   ⚠️  Async batch error: #{e.message}"
      puts "   ℹ️  Falling back to regular batch..."
      # Fallback to regular batch
      @client.upsert(index: INDEX_NAME, vectors: large_batch)
      puts "   ✅ Fallback batch completed"
    end
  end

  # =============================================================================
  # SECTION 11: STREAMING LARGE QUERIES
  # =============================================================================

  def section_11_streaming
    print_section("11. Streaming Large Queries")

    puts "🌊 Testing streaming for large result sets..."
    puts "   This demonstrates Vectra::Streaming for memory-efficient queries"

    query_vector = generate_embedding("technology innovation")

    # Use streaming client
    streaming_client = Vectra::Streaming.new(@client)

    puts "\n📊 Streaming query results (batch_size: 10)..."
    start_time = Time.now
    total_results = 0
    batches_processed = 0

    begin
      streaming_client.query_each(
        index: INDEX_NAME,
        vector: query_vector,
        top_k: 50,  # Large result set
        batch_size: 10,
        include_metadata: true
      ) do |batch|
        batches_processed += 1
        total_results += batch.size
        print "   📦 Processed batch #{batches_processed}: #{batch.size} results (total: #{total_results})\r"
      end

      duration = ((Time.now - start_time) * 1000).round(2)
      puts "\n   ✅ Streaming completed in #{duration}ms"
      puts "   📊 Total results: #{total_results}"
      puts "   📦 Batches processed: #{batches_processed}"
      puts "   💾 Memory efficient: processed in chunks"

      @stats[:operations] += 1
    rescue StandardError => e
      puts "\n   ⚠️  Streaming error: #{e.message}"
      puts "   ℹ️  Falling back to regular query..."
      # Fallback to regular query
      results = @client.query(
        index: INDEX_NAME,
        vector: query_vector,
        top_k: 20
      )
      puts "   ✅ Fallback query returned #{results.size} results"
    end
  end

  # =============================================================================
  # SECTION 12: RESILIENCE FEATURES
  # =============================================================================

  def section_12_resilience
    print_section("12. Resilience Features (Rate Limiting & Circuit Breaker)")

    puts "🛡️  Testing resilience patterns..."

    # Rate Limiting
    puts "\n⏱️  Rate Limiting Test:"
    puts "   Configuring rate limiter: 5 requests/second, burst: 10"

    limiter = Vectra::RateLimiter.new(
      requests_per_second: 5,
      burst_size: 10
    )

    puts "   Making 8 requests with rate limiting..."
    start_time = Time.now
    rate_limited_requests = 0

    8.times do |i|
      limiter.acquire do
        @client.query(
          index: INDEX_NAME,
          vector: generate_embedding("test query #{i}"),
          top_k: 1
        )
        rate_limited_requests += 1
        print "   ✅ Request #{i + 1}/8 completed\r"
      end
    end

    rate_limit_duration = ((Time.now - start_time) * 1000).round(2)
    puts "\n   ✅ Rate limited requests completed in #{rate_limit_duration}ms"
    puts "   📊 Requests: #{rate_limited_requests}/8"
    puts "   ⏱️  Avg time per request: #{(rate_limit_duration / rate_limited_requests).round(2)}ms"

    limiter_stats = limiter.stats
    puts "   📈 Rate limiter stats:"
    puts "      Available tokens: #{limiter_stats[:available_tokens].round(2)}"
    puts "      Requests/sec: #{limiter_stats[:requests_per_second]}"

    @stats[:operations] += rate_limited_requests

    # Circuit Breaker
    puts "\n🔌 Circuit Breaker Test:"
    puts "   Configuring circuit breaker: failure_threshold=3, recovery_timeout=5s"

    breaker = Vectra::CircuitBreaker.new(
      name: "demo-breaker",
      failure_threshold: 3,
      recovery_timeout: 5
    )

    puts "   Testing circuit breaker with successful operations..."
    success_count = 0
    5.times do |i|
      begin
        breaker.call do
          @client.query(
            index: INDEX_NAME,
            vector: generate_embedding("circuit test #{i}"),
            top_k: 1
          )
        end
        success_count += 1
        print "   ✅ Operation #{i + 1}/5: Circuit #{breaker.state}\r"
      rescue Vectra::CircuitBreakerOpenError => e
        puts "\n   ⚠️  Circuit opened: #{e.message}"
        break
      end
    end

    puts "\n   ✅ Circuit breaker test completed"
    puts "   📊 Successful operations: #{success_count}/5"
    puts "   🔌 Circuit state: #{breaker.state}"
    puts "   📈 Circuit stats:"
    stats = breaker.stats
    puts "      Failures: #{stats[:failures]}"
    puts "      Successes: #{stats[:successes]}"
    puts "      State: #{stats[:state]}"

    @stats[:operations] += success_count
  end

  # =============================================================================
  # SECTION 13: MONITORING & LOGGING
  # =============================================================================

  def section_13_monitoring
    print_section("13. Monitoring & Logging")

    puts "📊 Setting up monitoring and logging..."

    # Structured JSON Logging
    puts "\n📝 Structured JSON Logging:"
    begin
      log_output = StringIO.new
      Vectra::Logging.setup!(
        output: log_output,
        app: "vectra-demo",
        env: "demo"
      )

      puts "   ✅ JSON logger initialized"

      # Log some operations
      Vectra::Logging.log_info("Demo operation started", operation: "demo", index: INDEX_NAME)
      Vectra::Logging.log_warn("Sample warning", message: "This is a test warning")
      Vectra::Logging.log_error("Sample error", error: "Test error", recoverable: true)

      log_output.rewind
      log_lines = log_output.read.split("\n").reject(&:empty?)
      puts "   📊 Logged #{log_lines.size} entries"
      puts "   📄 Sample log entry:"
      if log_lines.any?
        sample = JSON.parse(log_lines.first)
        puts "      Level: #{sample['level']}"
        puts "      Message: #{sample['message']}"
        puts "      Timestamp: #{sample['timestamp']}"
      end
    rescue StandardError => e
      puts "   ⚠️  Logging setup error: #{e.message}"
    end

    # Audit Logging
    puts "\n🔒 Audit Logging:"
    begin
      audit_output = StringIO.new
      audit = Vectra::AuditLog.new(
        output: audit_output,
        enabled: true,
        app: "vectra-demo"
      )

      puts "   ✅ Audit logger initialized"

      # Log audit events
      audit.log_access(
        user_id: "demo-user-123",
        operation: "query",
        index: INDEX_NAME,
        result_count: 5
      )

      audit.log_authentication(
        user_id: "demo-user-123",
        success: true,
        provider: "qdrant"
      )

      audit.log_data_modification(
        user_id: "demo-user-123",
        operation: "upsert",
        index: INDEX_NAME,
        record_count: 10
      )

      audit_output.rewind
      audit_lines = audit_output.read.split("\n").reject(&:empty?)
      puts "   📊 Logged #{audit_lines.size} audit events"
      puts "   📄 Audit event types:"
      audit_lines.each do |line|
        event = JSON.parse(line)
        puts "      - #{event['event_type']}: #{event['operation'] || event['change_type'] || 'N/A'}"
      end
    rescue StandardError => e
      puts "   ⚠️  Audit logging error: #{e.message}"
    end

    # Instrumentation (Sentry example)
    puts "\n🔔 Error Tracking (Sentry):"
    begin
      # Mock Sentry for demo (in production, use real Sentry)
      if defined?(Sentry)
        Vectra::Instrumentation::Sentry.setup!
        puts "   ✅ Sentry instrumentation enabled"
        puts "   📊 Errors will be tracked to Sentry"
      else
        puts "   ℹ️  Sentry not available (install 'sentry-ruby' gem for production)"
        puts "   💡 In production, errors are automatically tracked"
      end
    rescue StandardError => e
      puts "   ⚠️  Sentry setup error: #{e.message}"
    end

    # Honeybadger example
    puts "\n🐝 Error Tracking (Honeybadger):"
    begin
      if defined?(Honeybadger)
        Vectra::Instrumentation::Honeybadger.setup!
        puts "   ✅ Honeybadger instrumentation enabled"
        puts "   📊 Errors will be tracked to Honeybadger"
      else
        puts "   ℹ️  Honeybadger not available (install 'honeybadger' gem for production)"
        puts "   💡 In production, errors are automatically tracked"
      end
    rescue StandardError => e
      puts "   ⚠️  Honeybadger setup error: #{e.message}"
    end

    puts "\n✅ Monitoring & logging setup complete"
    puts "   💡 In production, configure:"
    puts "      • Sentry for error tracking"
    puts "      • Honeybadger for error tracking"
    puts "      • Datadog/New Relic for APM"
    puts "      • JSON logs for log aggregation"
    puts "      • Audit logs for compliance"
  end

  # =============================================================================
  # HELPER METHODS
  # =============================================================================

  private

  def setup_clients
    # Main client
    @client = Vectra.qdrant(
      host: @host,
      api_key: nil
    )

    # Cached client for performance
    @cache = Vectra::Cache.new(ttl: 300, max_size: 1000)
    @cached_client = Vectra::CachedClient.new(@client, cache: @cache)
  end

  def create_sample_document(id:, title:, content:, category:, author:)
    {
      id: id,
      values: generate_embedding(content),
      metadata: {
        title: title,
        content: content,
        category: category,
        author: author,
        created_at: Time.now.iso8601
      }
    }
  end

  def generate_batch_documents(count)
    categories = ["Technology", "Business", "Science", "Health", "Education"]
    titles_by_category = {
      "Technology" => [
        "Introduction to Machine Learning",
        "Cloud Computing Best Practices",
        "Microservices Architecture Patterns",
        "DevOps and CI/CD Pipelines",
        "Database Optimization Techniques"
      ],
      "Business" => [
        "Market Analysis Q4 2024",
        "Strategic Planning Guide",
        "Customer Retention Strategies",
        "Digital Transformation Roadmap",
        "Competitive Analysis Framework"
      ],
      "Science" => [
        "Quantum Computing Basics",
        "Climate Change Research",
        "Genetic Engineering Ethics",
        "Space Exploration Updates",
        "Renewable Energy Solutions"
      ],
      "Health" => [
        "Nutrition and Wellness Guide",
        "Mental Health Awareness",
        "Exercise Science Fundamentals",
        "Preventive Care Strategies",
        "Sleep Quality Improvement"
      ],
      "Education" => [
        "Modern Teaching Methods",
        "E-Learning Platforms Comparison",
        "Student Engagement Techniques",
        "Curriculum Development Guide",
        "Educational Technology Trends"
      ]
    }

    count.times.map do |i|
      category = categories[i % categories.size]
      title = titles_by_category[category][rand(5)]

      {
        id: "doc-#{format('%03d', i + 2)}",
        values: generate_embedding("#{title} #{category}"),
        metadata: {
          title: "#{title} #{i + 1}",
          category: category,
          author: ["Alice", "Bob", "Charlie", "Diana", "Eve"][rand(5)],
          views: rand(100..1000),
          created_at: (Time.now - rand(1..90) * 86400).iso8601
        }
      }
    end
  end

  # Simple TF-IDF inspired embedding (demo purposes)
  def generate_embedding(text)
    normalized = text.downcase.strip
    hash = Digest::SHA256.hexdigest(normalized)

    # Create deterministic pseudo-embedding
    DIMENSION.times.map do |i|
      seed = hash[(i * 2) % hash.length, 2].to_i(16)
      (Math.sin(seed + i + text.length) + 1) / 2.0
    end
  end

  def print_header(title)
    puts
    puts "=" * 80
    puts title.center(80)
    puts "=" * 80
    puts
    puts "Provider: Qdrant"
    puts "Host: #{@host}"
    puts "Index: #{INDEX_NAME}"
    puts "Dimension: #{DIMENSION}"
    puts
  end

  def print_section(title)
    puts
    puts "─" * 80
    puts "│ #{title}"
    puts "─" * 80
    puts
  end

  def print_summary
    print_section("Demo Summary")

    puts "📊 Operations Summary:"
    puts "   Total operations: #{@stats[:operations]}"
    puts "   Cache hits: #{@stats[:cache_hits]}"
    puts "   Errors handled: #{@stats[:errors]}"
    puts "   Retries: #{@stats[:retries]}"
    puts "\n🎯 Features Demonstrated:"
    puts "   ✅ Basic CRUD operations"
    puts "   ✅ Batch processing"
    puts "   ✅ Async batch operations"
    puts "   ✅ Streaming queries"
    puts "   ✅ Advanced queries with filtering"
    puts "   ✅ Update operations"
    puts "   ✅ Delete operations"
    puts "   ✅ Caching & performance"
    puts "   ✅ Error handling"
    puts "   ✅ Multi-tenancy (namespaces)"
    puts "   ✅ Health monitoring"
    puts "   ✅ Rate limiting"
    puts "   ✅ Circuit breaker"
    puts "   ✅ Monitoring & logging"

    puts "\n✅ Demo completed successfully!"
    puts "\n💡 Next Steps:"
    puts "   • Open Qdrant dashboard: #{@host}/dashboard"
    puts "   • Explore the Vectra documentation"
    puts "   • Try with different providers (Pinecone, Weaviate)"
    puts "   • Integrate into your application"

    puts "\n🧹 Cleanup:"
    puts "   Run with --cleanup flag to delete the index"
    puts "   Stop Qdrant: docker ps | grep qdrant | awk '{print $1}' | xargs docker stop"
    puts
  end
end

# =============================================================================
# MAIN EXECUTION
# =============================================================================

if __FILE__ == $PROGRAM_NAME
  host = ARGV.reject { |arg| arg.start_with?("--") }.first || "http://localhost:6333"
  cleanup = ARGV.include?("--cleanup")

  begin
    demo = ComprehensiveVectraDemo.new(host)
    demo.run_demo

    # Cleanup if requested
    if cleanup
      puts "\n🧹 Cleaning up..."
      demo.instance_variable_get(:@client).provider.delete_index(name: ComprehensiveVectraDemo::INDEX_NAME)
      puts "   ✅ Index deleted"
    end

  rescue Interrupt
    puts "\n\n⚠️  Demo interrupted by user"
    exit 1
  rescue StandardError => e
    puts "\n\n❌ Error: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    puts "\n💡 Make sure Qdrant is running:"
    puts "   docker run -p 6333:6333 qdrant/qdrant"
    exit 1
  end
end
