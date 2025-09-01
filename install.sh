#!/bin/bash
set -e

APP=convex
DB=${APP}db

dokku apps:create $APP || true
dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres || true
dokku postgres:create $DB || true
dokku postgres:link $DB $APP

git remote add dokku dokku@moll.lt:$APP || true
git push dokku main

