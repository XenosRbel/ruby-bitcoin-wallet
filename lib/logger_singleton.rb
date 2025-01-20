# frozen_string_literal: true

require 'logger'
require 'singleton'

class LoggerSingleton
  include Singleton

  attr_reader :logger

  def initialize
    @logger = Logger.new(STDOUT)

    log_level = ENV.fetch('LOG_LEVEL', 'info').upcase
    @logger.level = Logger.const_get(log_level)
  end

  class << self
    def method_missing(method, *args, &block)
      instance.logger.__send__(method, *args)
    end

    def respond_to_missing?(method_name, include_private = false)
      instance.logger.respond_to?(method_name) || super
    end
  end
end
