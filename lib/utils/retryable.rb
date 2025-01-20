# frozen_string_literal: true

require_relative '../errors'

module Utils
  module Retryable
    def retryable(*names, times: 3, on: [StandardError], sleep_sec: 0.2)
      names.each do |name|
        original = instance_method(name)
        define_method(name) do |*args, **kwargs, &blk|
          attempts = 0
          begin
            original.bind_call(self, *args, **kwargs, &blk)
          rescue *on => e
            attempts += 1
            raise e if attempts >= times

            sleep(sleep_sec * attempts)
            retry
          end
        end
      end
    end
  end
end
