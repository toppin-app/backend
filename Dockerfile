FROM ruby:3.0.6-slim-bullseye

RUN apt-get update -qq \
    && apt-get install -y build-essential libpq-dev nodejs npm curl default-libmysqlclient-dev imagemagick \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

# Sets the path where the app is going to be installed (for hot reloading)
ENV RAILS_ROOT /var/www/

# Creates the directory and all the parents (if they don't exist)
RUN mkdir -p "$RAILS_ROOT"

# Sets the working directory to the path where the app is going to be installed
WORKDIR $RAILS_ROOT

# Copies the Gemfile and Gemfile.lock first, so we can install all the dependencies.
COPY Gemfile Gemfile.lock ./

# Installs the Gem File.
RUN bundle install

# We copy all the files from the current directory to our
# /app directory
# Pay close attention to the dot (.)
# The first one will select ALL The files of the current directory,
# The second dot will copy it to the WORKDIR!
COPY . .

# Installs JavaScript dependencies
RUN yarn install --check-files

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]
