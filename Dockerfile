FROM ruby:4.0.6-bookworm@sha256:b4aa7093ffca123d849e79b3e2bc582064f6dd9c22940e69c08bc47d74e355db

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates default-libmysqlclient-dev git tzdata \
    && groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --home-dir /app --no-create-home --shell /usr/sbin/nologin app \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN gem install bundler --version 4.0.19 --no-document

COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment true \
    && bundle install --jobs 4 --retry 3 \
    && chown app:app /app

COPY --chown=app:app . .

USER app

EXPOSE 9006
