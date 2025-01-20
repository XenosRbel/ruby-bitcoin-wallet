# frozen_string_literal: true

require 'bitcoin'
require_relative 'blockstream_client'
require_relative 'transaction_builder'
require_relative 'logger_singleton'
require_relative 'errors/signature_error'

class Wallet
  STORAGE_PATH = '/app/data'
  WALLET_FILE = STORAGE_PATH + "/wallet.key"

  def initialize(network)
    @network = network
    Bitcoin.network = @network
    @client = BlockstreamClient.new
    load_or_create_wallet
  end

  def address
    @key.addr
  end

  def balance
    @client.get_balance(address)
  end

  def send(recipient_address, amount_satoshis)
    utxos = @client.get_utxos(address)
    tx_builder = TransactionBuilder.new(@key, utxos, @client)

    builder = tx_builder.build(
      recipient_address,
      amount_satoshis
    )

    raise SignatureError unless builder.sign

    @client.broadcast_transaction(builder.payload)
  end

  def private_key
    @key.to_base58
  end

  private

  def load_or_create_wallet
    if File.exist?(WALLET_FILE)
      key_wif = File.read(WALLET_FILE).strip
      begin
        @key = Bitcoin::Key.from_base58(key_wif)
      rescue => e
        LoggerSingleton.error({event: 'key_load_error', error: e.message})
        return false
      end
    else
      priv_key = Bitcoin::Key.generate.priv
      @key = Bitcoin::Key.new(priv_key)
      wif = @key.to_base58
      File.write(WALLET_FILE, wif)

      LoggerSingleton.info({
        event: 'wallet_created',
        address: @key.addr,
        wif: wif
      })
    end
  end
end
