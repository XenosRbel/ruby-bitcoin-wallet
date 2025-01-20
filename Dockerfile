FROM ruby:3.3.6-bullseye

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

RUN apt-get update -qq \
    && apt-get install -qq -y locales \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && echo "LANG=en_US.UTF-8" > /etc/default/locale \
    && locale-gen

RUN apt-get update && apt-get install -qq -y --no-install-recommends \
    build-essential \
    libssl1.1 \
    openssl

RUN wget https://www.openssl.org/source/openssl-1.1.1u.tar.gz && \
    tar -xzvf openssl-1.1.1u.tar.gz && \
    cd openssl-1.1.1u && \
    ./config && \
    make && \
    make install

RUN apt-get install -qq -y --no-install-recommends \
    ca-certificates && rm -rf /var/lib/apt/lists/*

ENV OPENSSL_LIB_DIR=/usr/local/ssl/lib
ENV OPENSSL_INCLUDE_DIR=/usr/local/ssl/include
ENV LD_LIBRARY_PATH=/usr/local/ssl/lib:$LD_LIBRARY_PATH
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs

ENV APP_NAME app
RUN mkdir /$APP_NAME
WORKDIR /$APP_NAME

# Копируем Gemfile и устанавливаем зависимости
COPY Gemfile* /$APP_NAME/

ENV BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=3 \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle
ENV PATH="${BUNDLE_BIN}:${PATH}"

COPY . /$APP_NAME

# Устанавливаем правильные разрешения для исполняемых файлов
RUN chmod +x bin/wallet_cli.rb docker-compose-entrypoint.sh
