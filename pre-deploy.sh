#!/usr/bin/env bash
# pre-deploy.sh — Pre-deployment hook for Dokku/Convex
# Description: Add any checks or build steps to run before deployment.
# Usage: ./pre-deploy.sh

# Enable strict mode for safer scripts
set -euo pipefail
IFS=$'\n\t'

# TODO: Add pre-deployment steps below
dokku apps:create convex

# Set api & actions urls with your domain in dokku
dokku domains:set convex api.*.* actions.*.*

# Deploy (set url)
git remote add dokku dokku@YOUR_HOST:convex
git push dokku main

 # Create postgres DB for convex
dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
dokku postgres:create convex-db

    # Get url
    dokku postgres:info convex-db

# Linking injects DATABASE_URL into the app’s config automatically:
dokku postgres:link convex-db convex

    # Check
    dokku config convex

