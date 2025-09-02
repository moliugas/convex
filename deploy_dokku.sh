#!/usr/bin/env bash
set -euo pipefail

# Prompt for app name with default
read -r -p "App name [conapi]: " APP_INPUT || true
APP=${APP_INPUT:-conapi}

# Default DB name derived from app
DB="${APP}-db"

# Prompt for remote with default
read -r -p "Dokku remote server [dokku@moll.lt]: " REMOTE_INPUT || true
REMOTE=${REMOTE_INPUT:-dokku@moll.lt}

echo "Using app: ${APP}"
echo "Using database: ${DB}"
echo "Using remote: ${REMOTE}"

# Helper to run dokku commands on the remote
run_dokku() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${REMOTE}" dokku "$@"
}

echo "Checking if app exists on remote..."
if run_dokku apps:exists "${APP}"; then
  echo "App ${APP} exists. Destroying..."
  run_dokku apps:destroy "${APP}" -f
else
  echo "App ${APP} does not exist."
fi

echo "Creating app ${APP}..."
run_dokku apps:create "${APP}"

# Ensure postgres plugin is installed
echo "Ensuring postgres plugin is installed..."
if ! run_dokku plugin:list | grep -q "postgres"; then
  run_dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
else
  echo "Postgres plugin already installed."
fi

echo "Creating postgres service ${DB} (if missing)..."
run_dokku postgres:create "${DB}" || true

echo "Linking ${DB} -> ${APP}..."
run_dokku postgres:link "${DB}" "${APP}" || true

# Configure git remote
echo "Configuring git remote 'dokku' to ${REMOTE}:${APP}..."
if git remote | grep -q "^dokku$"; then
  git remote set-url dokku "${REMOTE}:${APP}"
else
  git remote add dokku "${REMOTE}:${APP}" || true
fi

echo "Pushing to Dokku..."
git push dokku main

echo "Done. Deployed ${APP} to ${REMOTE}."

