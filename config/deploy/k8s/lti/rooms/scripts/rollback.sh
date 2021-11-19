#!/bin/sh

echo "Rolling back..."
bundle exec rake db:rollback
