#!/bin/sh

echo "Migrating..."
bundle exec rake db:migrate
