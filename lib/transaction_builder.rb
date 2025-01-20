require 'stringio'
require 'bitcoin'

require_relative 'utils/threadable'
require_relative 'errors/invalid_transaction_error'
require_relative 'errors/insufficient_funds_error'
require_relative 'errors/signature_error'
require_relative 'logger_singleton'
require_relative 'money_conversion'

class TransactionBuilder
  include Utils::Threadable
  include Bitcoin::Builder

  SATOSHIS_PER_BYTE = 10
  HASH_TYPE = Bitcoin::Script::SIGHASH_TYPE[:all]
  MIN_CHANGE = 546        # Минимальный размер сдачи в сатоши
  FIXED_FEE = 10_000      # Фиксированная комиссия 0.0001 tBTC в сатоши

  attr_reader :amount,
              :to,
              :from,
              :tx,
              :net_client

  def initialize(key, utxos, net_client)
    @key = key
    @from = @key

    @utxos = utxos
    @net_client = net_client
    @tx = nil
  end

  def build(recipient_address, amount_satoshis)
    @amount = amount_satoshis
    @to = recipient_address

    build_raw_tx
    check_balance!
    add_change_or_adjust_fee

    self
  end

  def sign
    check_tx!

    threaded_job(tx.in) do |input, i|
      prev_tx = @utxos[i][:tx]
      input.script_sig = script_signature(@key,
        tx.signature_hash_for_input(i, prev_tx, HASH_TYPE)
      )

      tx.verify_input_signature(i, prev_tx)
    end.map(&:value).all?
  rescue StandardError => e
    raise InvalidTransactionError, e.message
  end

  def payload
    tx.to_payload.bth
  end

  private

  def build_raw_tx
    @tx ||= ::Bitcoin::Protocol::Tx.new.tap do |tx|
      add_inputs(tx)
      tx.add_out(output(amount, to))
    end
    self
  end

  def add_inputs(tx)
    threaded_job(@utxos) do |utxo|
      utxo[:tx] = prev_tx(utxo)
      raise InvalidTransactionError, "Invalid UTXO: #{utxo.inspect}" unless utxo[:tx]

      tx.add_in(input(utxo))
    end
  end

  def prev_tx(utxo)
    raw_tx = @net_client.get_raw_transaction(utxo[:txid])
    raise InvalidTransactionError, "Failed to fetch previous transaction for UTXO: #{utxo[:txid]}" unless raw_tx

    ::Bitcoin::Protocol::Tx.new(raw_tx)
  end

  def input(utxo)
    ::Bitcoin::Protocol::TxIn.new(utxo[:tx].binary_hash, utxo[:vout])
  end

  def output(amount, to)
    to = to.is_a?(String) ? to : to.addr
    ::Bitcoin::Protocol::TxOut.value_to_address(amount, to)
  end

  def check_balance!
    required = amount + estimated_fee
    current_balance = balance
    formated_current_balance = sprintf("%.10f", MoneyConversion.from_minimal_to_float(current_balance, 'BTC'))
    formated_required = sprintf("%.10f", MoneyConversion.from_minimal_to_float(required, 'BTC'))

    raise InsufficientFundsError, "Insufficient funds: balance #{formated_current_balance} < #{formated_required}" if current_balance < required
  end

  def balance
    @utxos.reduce(0) { |sum, utxo| sum + utxo[:value] }
  end

  def add_change_or_adjust_fee
    total_needed = amount + estimated_fee
    change = balance - total_needed

    if change >= MIN_CHANGE
      # Добавляем сдачу как выход
      tx.add_out(output(change, from))
    else
      LoggerSingleton.warn("Сдача (#{change} сатоши) меньше минимального порога и будет добавлена к комиссии")
    end
  end

  def estimated_fee
    tx_size = estimate_tx_size(tx&.in&.size.to_i, tx&.out&.size.to_i + 1) # Учитываем возможную сдачу
    fee = tx_size * SATOSHIS_PER_BYTE
    [fee, FIXED_FEE].max # Минимальная комиссия 0.0001 BTC
  end

  def estimate_tx_size(num_inputs, num_outputs)
    tx_overhead = 10
    input_size = 148
    output_size = 34

    tx_overhead + (num_inputs * input_size) + (num_outputs * output_size)
  end

  def script_signature(key, signature)
    Bitcoin::Script.to_signature_pubkey_script(
      key.sign(signature),
      key.pub.htb,
      HASH_TYPE
    )
  end

  def check_tx!
    raise InvalidTransactionError, 'Transaction not built' unless tx
  end
end
