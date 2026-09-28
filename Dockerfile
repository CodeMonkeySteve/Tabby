FROM docker.finagle.org/ruby:3.4.11-slim-trixie
MAINTAINER Steve Sloan <steve@finagle.org>

ENV HOME=/app RAILS_ENV=production PORT=80 TZ="America/Los_Angeles"

RUN \
  apt update -qq && \
  apt install --no-install-recommends -y ca-certificates curl && \
  # PostgreSQL client
  install -d /usr/share/postgresql-common/pgdg && \
  curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list && \
  apt update -qq && \
  apt install --no-install-recommends -y \
    # build
    build-essential libssl-dev libyaml-dev gnupg git \
    # pg_dump
    postgresql-client-18 \
    # Nokogiri
    libxml2-dev libxslt1-dev \
    # NodeJS
    nodejs npm \
    # yt-dlp audio extraction
    ffmpeg \
    # debug tools
    less nano \
    && \

  # yt-dlp: official standalone release (distro packages lag behind YouTube changes), using NodeJS as its JavaScript runtime
  case "$(dpkg --print-architecture)" in arm64) YT_DLP=yt-dlp_linux_aarch64 ;; *) YT_DLP=yt-dlp_linux ;; esac && \
  curl -fsSL -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$YT_DLP" && \
  chmod a+rx /usr/local/bin/yt-dlp && \
  echo '--js-runtimes node' > /etc/yt-dlp.conf && \

  # other setup and cleanup
  mkdir -p $HOME && \
  echo 'alias ll="ls -lh"' >> $HOME/.bashrc && \
  mkdir -p /app/log /app/tmp /app/tmp/pids && \
  echo 'gem: --no-document' >> /etc/gemrc && \
  chmod uog+r /etc/gemrc && \

  gem install -N bundler thin && \
  gem install -N nokogiri -- --use-system-libraries && \

  apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/dpkg.log

WORKDIR /app

# rubygems
ARG JOBS=1
COPY Gemfile Gemfile.lock .ruby-version /app/
COPY lib/alpha_tab /app/lib/alpha_tab
RUN \
  gem install -N bundler && \
  bundle config set deployment 'true' && \
  bundle config set without 'development test' && \
  MAKEFLAGS="-j $JOBS" bundle install --jobs $JOBS && \
  cd /app/lib/alpha_tab && npm install

# app
ADD . /app
RUN RAILS_ENV=test bundle exec bin/rails assets:precompile # use test environment to get dummy credentials

CMD ["bundle", "exec", "falcon", "host"]
EXPOSE 80

ARG GIT_VERSION
ENV GIT_VERSION=$GIT_VERSION
