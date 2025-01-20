# frozen_string_literal: true

module Utils
  module Threadable
    DEFAULT_MAX_THREADS = 5

    def threaded_map(collection, max_threads: DEFAULT_MAX_THREADS, &block)
      raise ArgumentError, 'block required' unless block_given?

      items = collection.each_with_index.to_a
      return [] if items.empty?

      worker_count = [[max_threads.to_i, 1].max, items.size].min
      queue = Queue.new
      items.each { |pair| queue << pair }
      worker_count.times { queue << nil } # sentinel для каждой воркер-нити

      results = Array.new(items.size)
      failures = []
      failures_mutex = Mutex.new

      workers = worker_count.times.map do |w|
        Thread.new do
          Thread.current.name = begin
            "threadable-#{w}"
          rescue StandardError
            nil
          end
          Thread.current.report_on_exception = false
          while (job = queue.pop)
            item, idx = job
            begin
              results[idx] = yield(item, idx)
            rescue StandardError => e
              failures_mutex.synchronize { failures << e }
            end
          end
        end
      end
      workers.each(&:join)
      raise failures.first unless failures.empty?

      results
    end
  end
end
