# frozen_string_literal: true

require 'httparty'
require 'json'
require_relative 'logger_singleton'
require_relative 'errors'
require_relative 'utils/retryable'

class BlockstreamClient
  extend Utils::Retryable

  def initialize(network = nil, timeout: 10)
    @network = network || ENV.fetch('BITCOIN_NETWORK', 'mainnet').to_sym
    @timeout = timeout
    freeze
  end

  def get_utxos(address)
    request(:get, "address/#{address}/utxo") do |response|
      JSON.parse(response.body, symbolize_names: true)
    end
  end

  def get_balance(address)
    get_utxos(address).sum { |utxo| utxo[:value].to_i }
  end

  def broadcast_transaction(tx_hex)
    request(:post, 'tx', body: tx_hex,
                         headers: { 'Content-Type' => 'text/plain', 'Accept' => 'text/plain' }) do |response|
      raise TransactionError, "Ошибка отправки транзакции: #{response.body}" unless response.success?

      response.body.strip
    end
  end

  def get_raw_transaction(tx_id)
    request(:get, "tx/#{tx_id}/raw", &:body)
  end

  retryable :get_utxos, :get_raw_transaction,
            times: 3,
            on: [ServiceUnavailableError, GatewayTimeoutError],
            sleep_sec: 0.2

  private

  def request(method, path, body: nil, headers: {})
    response = nil
    label = caller_locations(1, 1)[0]&.label || 'request'
    url = url_for(path)
    begin
      response = case method
                 when :get
                   HTTParty.get(url, timeout: @timeout)
                 when :post
                   HTTParty.post(url, body: body, headers: headers, timeout: @timeout)
                 end
      block_given? ? yield(response) : response
    rescue Net::OpenTimeout, Socket::ResolutionError => e
      raise ServiceUnavailableError, e.message
    rescue Net::ReadTimeout, Net::WriteTimeout => e
      raise GatewayTimeoutError, e.message
    rescue StandardError => e
      LoggerSingleton.error({ event: label, error: e.message })
      raise
    ensure
      LoggerSingleton.debug({ event: label, status: response&.code, url: url })
    end
  end

  def url_for(path)
    File.join(base_url, path).strip
  end

  def base_url
    api_url = ENV.fetch('BLOCKSTREAM_API_URL', nil)
    return api_url unless api_url.nil?

    case @network
    when :testnet3 then 'https://blockstream.info/testnet/api'
    when :testnet4 then 'https://mempool.space/testnet4/api'
    when :signet then 'https://mempool.space/signet/api'
    else 'https://blockstream.info/api'
    end
  end
end
