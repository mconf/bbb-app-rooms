#!/bin/sh

echo "Migrating..."
bundle exec rake db:migrate

echo "Seeding..."
bundle exec rake db:seed
