# frozen_string_literal: true

require_relative 'errors'

class MoneyConversion
  @precisions = { 'BTC' => 8, 'tBTC' => 8 }
  @mutex = Mutex.new

  class << self
    def register_currency(code, precision:)
      @mutex.synchronize { @precisions = @precisions.merge(code.to_s => precision.to_i) }
    end

    def precision_for(currency)
      precision = @mutex.synchronize { @precisions[currency.to_s] }
      raise PrecisionNotFoundError, "Precision doesn't found for currency #{currency}" if precision.nil?

      precision
    end

    def from_minimal_to_float(amount, currency)
      precision = precision_for(currency)
      (amount.to_i / (10.0**precision)).to_f
    end

    def from_float_to_minimal(amount, currency)
      precision = precision_for(currency)
      (amount.to_f * (10**precision)).to_i
    end
  end
end
