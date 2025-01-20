FROM ruby:4.0.7-slim-bookworm

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

RUN apt-get update -qq \
    && apt-get install -qq -y --no-install-recommends locales \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && echo "LANG=en_US.UTF-8" > /etc/default/locale \
    && locale-gen

RUN apt-get update -qq && apt-get install -qq -y --no-install-recommends \
    build-essential \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs

ENV APP_NAME app
RUN mkdir /$APP_NAME
WORKDIR /$APP_NAME

COPY Gemfile* /$APP_NAME/

ENV BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=3 \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle
ENV PATH="${BUNDLE_BIN}:${PATH}"

COPY . /$APP_NAME

RUN chmod +x bin/wallet_cli.rb docker-compose-entrypoint.sh
