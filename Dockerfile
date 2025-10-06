ARG RUBY_VERSION=3.2
FROM ruby:${RUBY_VERSION}-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    build-essential \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN gem install jekyll bundler

WORKDIR /writings

COPY Gemfile ./
COPY Gemfile*.lock ./

COPY . .

RUN bundle install

CMD ["bundle", "exec", "jekyll", "serve", "-l", "-P", "3000", "-H", "0.0.0.0"]
