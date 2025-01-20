#!/usr/bin/env ruby
# frozen_string_literal: true

require 'thor'
require_relative '../lib/wallet'
require_relative '../lib/money_conversion'

class WalletCLI < Thor
  def initialize(*args)
    super(*args)

    network_type = ENV.fetch('BITCOIN_NETWORK', 'mainnet').to_sym
    @network = case network_type
               when :mainnet
                @currency = 'BTC'
                :bitcoin
               when :testnet
                @currency = 'tBTC'
                :testnet3
               end
  end

  desc 'address', 'Показать адрес кошелька'
  def address
    LoggerSingleton.info("Адрес кошелька: #{wallet.address}")
  end

  desc 'balance', 'Показать баланс кошелька'
  def balance
    satoshis = wallet.balance
    btc = MoneyConversion.from_minimal_to_float(satoshis, @currency)
    formatted_balance = sprintf("%.10f", btc)

    LoggerSingleton.info("Баланс: #{formatted_balance} #{@currency} (#{satoshis} satoshis)")
  end

  desc 'send ADDRESS AMOUNT', 'Отправить указанное количество монет на адрес'
  def send(address, amount)
    satoshis = amount.match?(/^\d+$/) ? amount.to_i : MoneyConversion.from_float_to_minimal(amount, @currency)
    tx_id = wallet.send(address, satoshis)

    LoggerSingleton.info("Транзакция отправлена. ID: #{tx_id}")
  rescue StandardError => e
    LoggerSingleton.error("Ошибка: #{e.message}; #{e.backtrace}")
  end

  private

  def wallet
    @wallet ||= Wallet.new(@network)
  end
end

WalletCLI.start(ARGV)
