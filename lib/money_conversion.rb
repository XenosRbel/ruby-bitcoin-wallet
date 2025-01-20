class MoneyConversion
  class << self
    def from_minimal_to_float(amount, currency)
      precision = find_precision(currency)
      (amount.to_i / (10.0**precision)).to_f
    end

    def from_float_to_minimal(amount, currency)
      precision = find_precision(currency)
      (amount.to_f * (10**precision)).to_i
    end

    private

    def find_precision(currency)
      precision = case currency
      when 'BTC'
        8
      when 'tBTC'
        8
      else
        raise PrecisionNotFoundError.new("Precision doesn't found for currency #{currency}")
      end

      precision
    end
  end
end
