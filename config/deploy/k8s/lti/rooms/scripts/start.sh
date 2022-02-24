#!/bin/sh

echo "Installing root certificate..."
cp tmp/ca-certificates/mconf-dev-ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

echo "Start app..."
bundle exec rails s -b 0.0.0.0 -p 3000
