# frozen_string_literal: true

require 'httparty'
require 'json'
require_relative 'logger_singleton'
require_relative 'errors/transaction_error'
require_relative 'errors/gateway_timeout_error'
require_relative 'errors/service_unavailable_error'

class BlockstreamClient
  def initialize
    @network = ENV.fetch('BITCOIN_NETWORK', 'mainnet').to_sym
  end

  def get_utxos(address)
    @path = "address/#{address}/utxo"
    handle_http_request do
      @response = HTTParty.get(url)
      JSON.parse(@response.body, symbolize_names: true)
    end
  end

  def get_balance(address)
    handle_http_request do
      utxos = get_utxos(address)
      utxos.sum { |utxo| utxo[:value].to_i }
    end
  end

  def broadcast_transaction(tx_hex)
    @path = 'tx'
    handle_http_request do
      @response = HTTParty.post(
        url,
        body:    tx_hex,
        headers: {
          'Content-Type' => 'text/plain',
          'Accept' => 'text/plain'
        }
      )

      raise TransactionError, "Ошибка отправки транзакции: #{@response.body}" unless @response.success?

      @response.body.strip
    end
  end

  def get_raw_transaction(tx_id)
    @path = "tx/#{tx_id}/raw"
    handle_http_request do
      @response = HTTParty.get(url)
      @response.body
    end
  end

  private

  def handle_http_request
    yield
  rescue Net::OpenTimeout, Socket::ResolutionError => e
    raise ServiceUnavailableError.new(e.message)
  rescue Net::ReadTimeout, Net::WriteTimeout => e
    raise GatewayTimeoutError.new(e.message)
  rescue StandardError => e
    LoggerSingleton.error({ event: __method__.to_s, error: e.message })
    raise
  ensure
    LoggerSingleton.debug({
                            event:    caller_locations(1, 1)[0].label,
                            status:   @response&.code,
                            request:  @response&.request&.inspect,
                            response: @response&.inspect
                          })
  end

  def url
    File.join(base_url, @path).strip
  end

  def base_url
    api_url = ENV.fetch('BLOCKSTREAM_API_URL', nil)
    @base_url ||= api_url unless api_url.nil?

    @base_url ||= case @network
                  when :testnet3
                    'https://blockstream.info/testnet/api'
                  when :testnet4
                    'https://mempool.space/testnet4/api'
                  when :signet
                    'https://mempool.space/signet/api'
                  else
                    'https://blockstream.info/api'
                  end
  end
end
