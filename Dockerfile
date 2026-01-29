FROM docker.finagle.org/ruby:3.4.8-slim-trixie
MAINTAINER Steve Sloan <steve@finagle.org>

ENV HOME=/app RAILS_ENV=production PORT=80
RUN \
  apt-get update -qq && \
  apt-get install --no-install-recommends -y \
    # build
    build-essential libssl-dev libyaml-dev curl gnupg git \
    # Nokogiri
    libxml2-dev libxslt1-dev \
    # NodeJS
    nodejs npm \
    # debug tools
    less nano \

  # other setup and cleanup
  mkdir -p $HOME && \
  echo 'alias ll="ls -lh"' >> $HOME/.bashrc && \
  mkdir -p /app/log /app/tmp /app/tmp/pids && \
  echo 'gem: --no-document' >> /etc/gemrc && \
  chmod uog+r /etc/gemrc && \

  gem install -N bundler thin && \
  gem install -N nokogiri -- --use-system-libraries && \
  cd /app/lib/alpha_tab && npm install && \

  apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/dpkg.log

WORKDIR /app

# rubygems
ARG JOBS=1
COPY Gemfile Gemfile.lock .ruby-version /app/
RUN \
  gem install -N bundler && \
  bundle config set deployment 'true' && \
  bundle config set without 'development test' && \
  MAKEFLAGS="-j $JOBS" bundle install --jobs $JOBS

# app
ADD . /app
RUN RAILS_ENV=test bundle exec bin/rails assets:precompile # use test environment to get dummy credentials

CMD ["bundle", "exec", "falcon", "host"]
EXPOSE 80

ARG GIT_VERSION
ENV GIT_VERSION=$GIT_VERSION
