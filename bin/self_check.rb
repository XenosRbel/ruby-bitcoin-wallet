#!/usr/bin/env ruby
# frozen_string_literal: true

# Минимальный runnable check без фреймворков: падает, если логика сломана.
# Запуск: ruby bin/self_check.rb
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'utils/threadable'
require 'utils/retryable'
require 'errors'
require 'money_conversion'
begin
  require 'blockstream_client'
rescue LoadError => e
  puts "skip: blockstream_client не загружен без гемов (#{e.message.lines.first&.strip})"
end

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond

  puts "ok: #{msg}"
end

include Utils::Threadable

# 1. Порядок + bounded pool
res = threaded_map([1, 2, 3, 4], max_threads: 2) do |x, _|
  sleep(rand * 0.01)
  x * 2
end
assert(res == [2, 4, 6, 8], 'threaded_map сохраняет порядок')

# 2. Пустая коллекция
assert(threaded_map([]) { raise 'must not run' } == [], 'пустая коллекция -> []')

# 3. Ошибки не теряются
begin
  threaded_map([1, 2]) { |_, i| raise 'boom' if i == 1 }
  raise 'should have raised'
rescue RuntimeError => e
  assert(e.message == 'boom', 'ошибка из воркера пробрасывается')
end

# 4. DSL ошибок: те же имена + code
assert(defined?(InsufficientFundsError) == 'constant', 'InsufficientFundsError существует')
assert(InsufficientFundsError.new.code == 402, 'код ошибки доступен')
assert(InsufficientFundsError.ancestors.include?(BaseError), 'иерархия сохранена')

# 5. MoneyConversion реестр
MoneyConversion.register_currency('LTC', precision: 8)
assert(MoneyConversion.from_float_to_minimal(1.5, 'LTC') == 150_000_000, 'кастомная валюта работает')
begin
  MoneyConversion.from_minimal_to_float(1, 'XXX')
  raise 'should have raised'
rescue PrecisionNotFoundError
  puts 'ok: неизвестная валюта рейзит PrecisionNotFoundError'
end

# 6. Retryable только на GET (проверяем, что метод обёрнут и ретраит)
klass = Class.new do
  extend Utils::Retryable
  attr_reader :calls

  def initialize
    @calls = 0
  end

  def flaky
    @calls += 1
    raise ServiceUnavailableError, 'down' if @calls < 3

    :recovered
  end

  retryable :flaky, times: 3, on: [ServiceUnavailableError], sleep_sec: 0
end
assert(klass.new.flaky == :recovered, 'retryable восстанавливается за 3 попытки')

# 7. BlockstreamClient stateless: в коде нет shared @path/@response
src = File.read(File.expand_path('../lib/blockstream_client.rb', __dir__))
assert(!src.match?(/@path|@response/), 'нет shared @path/@response в исходнике')
assert(src.include?('freeze'), 'настройки замораживаются')
if defined?(BlockstreamClient)
  c1 = BlockstreamClient.new(:signet)
  assert(!c1.instance_variable_defined?(:@path) && !c1.instance_variable_defined?(:@response),
         'инстанс без мутабельного состояния запроса')
end

# 8. OpenSSL3-совместимость bitcoin-ruby (вне контейнера гема нет — скип).
begin
  require 'wallet'
  Bitcoin.network = :bitcoin
  k = Bitcoin::Key.generate
  assert(!k.addr.to_s.empty?, 'generate даёт адрес')
  k2 = Bitcoin::Key.from_base58(k.to_base58)
  assert(k2.addr == k.addr && k2.priv == k.priv, 'WIF roundtrip сохраняет адрес и priv')
  k3 = Bitcoin::Key.new(nil, k.pub)
  assert(k3.addr == k.addr, 'pub-only ключ даёт тот же адрес')
  sig = k.sign('test-message')
  assert(k3.verify('test-message', sig), 'verify через pub-only ключ')
  assert(Bitcoin.verify_signature('test-message', sig + [Bitcoin::Script::SIGHASH_TYPE[:all]].pack('C'), k.pub), 'Bitcoin.verify_signature')
  puts 'ok: OpenSSL3 compat (generate/WIF/pub-only/sign/verify)'
rescue LoadError => e
  puts "skip: bitcoin-стек недоступен (#{e.message.lines.first&.strip})"
end

puts 'ALL GREEN'
