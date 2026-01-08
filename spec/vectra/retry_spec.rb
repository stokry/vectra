# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vectra::Retry do
  let(:config) { double(max_retries: 3, retry_delay: 0.01, logger: nil) }
  let(:test_class) do
    Class.new do
      include Vectra::Retry
      attr_accessor :config

      def initialize(config)
        @config = config
      end
    end
  end

  subject { test_class.new(config) }

  before do
    # Stub sleep to speed up tests
    allow(subject).to receive(:sleep)
  end

  describe '#with_retry' do
    context 'when operation succeeds' do
      it 'returns the result' do
        result = subject.with_retry { 'success' }
        expect(result).to eq('success')
      end

      it 'does not retry' do
        attempts = 0
        subject.with_retry { attempts += 1; 'success' }
        expect(attempts).to eq(1)
      end
    end

    context 'when operation fails with retryable error' do
      it 'retries on PG::ConnectionBad' do
        attempts = 0

        result = subject.with_retry do
          attempts += 1
          raise PG::ConnectionBad, 'Connection failed' if attempts < 3
          'success'
        end

        expect(attempts).to eq(3)
        expect(result).to eq('success')
      end

      it 'retries on ConnectionPool::TimeoutError' do
        attempts = 0

        result = subject.with_retry do
          attempts += 1
          raise ConnectionPool::TimeoutError, 'Pool timeout' if attempts < 2
          'success'
        end

        expect(attempts).to eq(2)
        expect(result).to eq('success')
      end

      it 'uses exponential backoff' do
        attempts = 0
        delays = []

        allow(subject).to receive(:sleep) do |delay|
          delays << delay
        end

        subject.with_retry do
          attempts += 1
          raise PG::ConnectionBad if attempts < 3
          'success'
        end

        # First retry: 0.01s, second: 0.02s (2^1 * 0.01)
        expect(delays.size).to eq(2)
        expect(delays[0]).to be_within(0.005).of(0.01)
        expect(delays[1]).to be >= 0.01  # With jitter
      end

      it 'stops after max_attempts' do
        attempts = 0

        expect {
          subject.with_retry(max_attempts: 3) do
            attempts += 1
            raise PG::ConnectionBad, 'Always fails'
          end
        }.to raise_error(PG::ConnectionBad)

        expect(attempts).to eq(3)
      end

      it 'respects custom max_attempts' do
        attempts = 0

        expect {
          subject.with_retry(max_attempts: 5) do
            attempts += 1
            raise PG::ConnectionBad
          end
        }.to raise_error(PG::ConnectionBad)

        expect(attempts).to eq(5)
      end

      it 'caps delay at max_delay' do
        delays = []
        allow(subject).to receive(:sleep) { |delay| delays << delay }

        expect {
          subject.with_retry(
            max_attempts: 5,
            base_delay: 10,
            max_delay: 15,
            backoff_factor: 2,
            jitter: false
          ) do
            raise PG::ConnectionBad
          end
        }.to raise_error(PG::ConnectionBad)

        # Delays: 10, 15, 15, 15 (capped at max_delay)
        expect(delays[0]).to eq(10)
        expect(delays[1]).to eq(15)
        expect(delays[2]).to eq(15)
        expect(delays[3]).to eq(15)
      end
    end

    context 'when operation fails with non-retryable error' do
      it 'does not retry ArgumentError' do
        attempts = 0

        expect {
          subject.with_retry do
            attempts += 1
            raise ArgumentError, 'Invalid argument'
          end
        }.to raise_error(ArgumentError)

        expect(attempts).to eq(1)
      end

      it 'does not retry ValidationError' do
        attempts = 0

        expect {
          subject.with_retry do
            attempts += 1
            raise Vectra::ValidationError, 'Invalid'
          end
        }.to raise_error(Vectra::ValidationError)

        expect(attempts).to eq(1)
      end
    end

    context 'with jitter' do
      it 'adds randomness to delay' do
        delays = []
        allow(subject).to receive(:sleep) { |delay| delays << delay }

        expect {
          subject.with_retry(max_attempts: 3, base_delay: 1.0, jitter: true) do
            raise PG::ConnectionBad
          end
        }.to raise_error(PG::ConnectionBad)

        # Each delay should be different due to jitter
        expect(delays.uniq.size).to eq(delays.size)
      end

      it 'can be disabled' do
        delays = []
        allow(subject).to receive(:sleep) { |delay| delays << delay }

        expect {
          subject.with_retry(
            max_attempts: 3,
            base_delay: 1.0,
            backoff_factor: 2,
            jitter: false
          ) do
            raise PG::ConnectionBad
          end
        }.to raise_error(PG::ConnectionBad)

        # Delays should be exact: 1.0, 2.0
        expect(delays[0]).to eq(1.0)
        expect(delays[1]).to eq(2.0)
      end
    end

    context 'with logging' do
      let(:logger) { instance_double(Logger) }
      let(:config) { double(max_retries: 3, retry_delay: 0.01, logger: logger) }

      it 'logs retry attempts' do
        attempts = 0

        expect(logger).to receive(:warn).twice

        subject.with_retry do
          attempts += 1
          raise PG::ConnectionBad if attempts < 3
          'success'
        end
      end

      it 'logs final error' do
        expect(logger).to receive(:warn).twice
        expect(logger).to receive(:error)

        expect {
          subject.with_retry(max_attempts: 3) do
            raise PG::ConnectionBad, 'Failed'
          end
        }.to raise_error(PG::ConnectionBad)
      end
    end
  end

  describe '#retryable_error?' do
    it 'returns true for PG::ConnectionBad' do
      error = PG::ConnectionBad.new('test')
      expect(subject.send(:retryable_error?, error)).to be true
    end

    it 'returns true for PG::UnableToSend' do
      error = PG::UnableToSend.new('test')
      expect(subject.send(:retryable_error?, error)).to be true
    end

    it 'returns true for ConnectionPool::TimeoutError' do
      error = ConnectionPool::TimeoutError.new('test')
      expect(subject.send(:retryable_error?, error)).to be true
    end

    it 'returns true for errors with "timeout" in message' do
      error = StandardError.new('Operation timeout occurred')
      expect(subject.send(:retryable_error?, error)).to be true
    end

    it 'returns true for errors with "connection" in message' do
      error = StandardError.new('Connection reset by peer')
      expect(subject.send(:retryable_error?, error)).to be true
    end

    it 'returns false for ArgumentError' do
      error = ArgumentError.new('test')
      expect(subject.send(:retryable_error?, error)).to be false
    end
  end

  describe '#calculate_delay' do
    it 'calculates exponential backoff' do
      # Attempt 1: 1 * (2^0) = 1
      delay = subject.send(:calculate_delay,
                           attempt: 1,
                           base_delay: 1.0,
                           max_delay: 30.0,
                           backoff_factor: 2,
                           jitter: false)
      expect(delay).to eq(1.0)

      # Attempt 2: 1 * (2^1) = 2
      delay = subject.send(:calculate_delay,
                           attempt: 2,
                           base_delay: 1.0,
                           max_delay: 30.0,
                           backoff_factor: 2,
                           jitter: false)
      expect(delay).to eq(2.0)

      # Attempt 3: 1 * (2^2) = 4
      delay = subject.send(:calculate_delay,
                           attempt: 3,
                           base_delay: 1.0,
                           max_delay: 30.0,
                           backoff_factor: 2,
                           jitter: false)
      expect(delay).to eq(4.0)
    end

    it 'respects max_delay' do
      # Would be 16, but capped at 10
      delay = subject.send(:calculate_delay,
                           attempt: 5,
                           base_delay: 1.0,
                           max_delay: 10.0,
                           backoff_factor: 2,
                           jitter: false)
      expect(delay).to eq(10.0)
    end
  end
end
