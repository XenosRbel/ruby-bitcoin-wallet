# frozen_string_literal: true

class BaseError < StandardError
  class << self
    def code(val = nil)
      @code = val if val
      @code
    end
  end

  def code
    self.class.code
  end
end

{ InsufficientFundsError: 402,
  InvalidTransactionError: 422,
  PrecisionNotFoundError: 500,
  ServiceUnavailableError: 503,
  GatewayTimeoutError: 504,
  SignatureError: 422,
  TransactionError: 502 }.each do |name, code|
  klass = Class.new(BaseError)
  klass.code(code)
  Object.const_set(name, klass) unless Object.const_defined?(name)
end
