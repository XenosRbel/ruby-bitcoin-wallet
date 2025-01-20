#!/bin/bash
set -e

# Установка гемов при первом запуске
bundle check || bundle install

# Первые два аргумента - это "ruby" и "bin/wallet_cli.rb"
# Остальные аргументы передаются в wallet_cli.rb
bundle exec "${@:1:2}" "${@:3}"
