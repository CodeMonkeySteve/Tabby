# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Build'n'run by hand:
# docker build -t tabby .
# docker run -d -p 8080:8080 -e RAILS_MASTER_KEY=<value from config/master.key> --name tabby tabby

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.13
FROM docker.io/library/ruby:$RUBY_VERSION-slim-trixie AS base
LABEL org.opencontainers.image.authors="Steve Sloan <steve@finagle.org>"

# Rails app lives here
WORKDIR /app

# Install base packages: NodeJS for AlphaTab (via Nodo) and as yt-dlp's JavaScript runtime, ffmpeg for yt-dlp, pg_dump
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl && \
    install -d /usr/share/postgresql-common/pgdg && \
    curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y libjemalloc2 libvips nodejs ffmpeg postgresql-client-18 less nano && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# yt-dlp: official standalone release (distro packages lag behind YouTube changes), using NodeJS as its JavaScript runtime
RUN case "$(dpkg --print-architecture)" in arm64) YT_DLP=yt-dlp_linux_aarch64 ;; *) YT_DLP=yt-dlp_linux ;; esac && \
    curl -fsSL -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$YT_DLP" && \
    chmod a+rx /usr/local/bin/yt-dlp && \
    echo '--js-runtimes node' > /etc/yt-dlp.conf

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    TZ="America/Los_Angeles" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems and AlphaTab's node modules
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config libssl-dev libxml2-dev libxslt1-dev npm && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock .ruby-version ./

ARG JOBS=1
RUN \
  MAKEFLAGS="-j $JOBS" bundle install --jobs $JOBS && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
  # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
  bundle exec bootsnap precompile -j 1 --gemfile

# Install AlphaTab, for score parsing and the player's assets (public/alphatab)
COPY lib/alpha_tab/package.json lib/alpha_tab/package-lock.json lib/alpha_tab/
RUN cd lib/alpha_tab && npm ci && npm cache clean --force

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Use the test environment to get dummy credentials
RUN RAILS_ENV=test ./bin/rails assets:precompile

# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 app && \
    useradd app --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    echo 'alias ll="ls -lh"' >> /home/app/.bashrc
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=app:app --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=app:app --from=build /app /app

# Entrypoint prepares the database.
ENTRYPOINT ["/app/bin/docker-entrypoint"]

# Runs the web server and the Solid Queue jobs service, see falcon.rb
ENV PORT=8080
EXPOSE 8080
CMD ["bundle", "exec", "falcon", "host"]

ARG GIT_VERSION
ENV GIT_VERSION=$GIT_VERSION
