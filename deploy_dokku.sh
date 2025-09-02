#!/usr/bin/env bash
set -euo pipefail

# Prompt for app name with default
read -r -p "App name [conapi]: " APP_INPUT || true
APP=${APP_INPUT:-conapi}

# Prompt for domain with default
read -r -p "App domain [api.moll.lt]: " DOMAIN_INPUT || true
DOMAIN=${DOMAIN_INPUT:-api.moll.lt}

# Prompt for Let's Encrypt settings
read -r -p "Enable Let's Encrypt? [Y/n]: " LE_ENABLE_INPUT || true
LE_ENABLE_INPUT=${LE_ENABLE_INPUT:-Y}
LE_ENABLE=${LE_ENABLE_INPUT,,} # to lowercase
LE_ENABLE=${LE_ENABLE:-y}
if [[ ${LE_ENABLE} == "y" || ${LE_ENABLE} == "yes" ]]; then
  read -r -p "Let's Encrypt email (optional) [moliugas@gmail.com]: " LE_EMAIL_INPUT || true
  LE_EMAIL=${LE_EMAIL_INPUT:-moliugas@gmail.com}
else
  LE_EMAIL=""
fi

# Default DB name derived from app
DB="${APP}-db"

echo "Using app: ${APP}"
echo "Using domain: ${DOMAIN}"
echo "Using database: ${DB}"

# Helper to run dokku commands on the remote
run_dokku() {
  dokku "$@"
}

echo "Checking if app exists on remote..."
APP_EXISTS=false
if run_dokku apps:exists "${APP}"; then
  echo "App ${APP} exists. Reusing it."
  APP_EXISTS=true
else
  echo "App ${APP} does not exist. Creating..."
  echo "Creating app ${APP}..."
  run_dokku apps:create "${APP}"
fi



echo "Configuring domain for ${APP}..."
# Ensure app uses vhost-based domains and set the desired domain
run_dokku domains:enable "${APP}"
run_dokku domains:set "${APP}" "${DOMAIN}"

# Optionally enable Let's Encrypt and certificates
if [[ ${LE_ENABLE} == "y" || ${LE_ENABLE} == "yes" ]]; then
  echo "Ensuring letsencrypt plugin is installed..."
  set +o pipefail
  if dokku plugin:list 2>/dev/null | grep -qiE "(^|[[:space:]])letsencrypt([[:space:]]|$)"; then
    echo "Let's Encrypt plugin already installed."
  else
    if command -v sudo >/dev/null 2>&1; then
      sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git letsencrypt
    else
      su -c "dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git letsencrypt"
    fi
  fi
  set -o pipefail

  if [[ -n ${LE_EMAIL} ]]; then
    run_dokku letsencrypt:set "${APP}" email "${LE_EMAIL}" || true
  fi
  echo "Enabling Let's Encrypt for ${APP}..."
  run_dokku letsencrypt:enable "${APP}" || true
fi

echo "Setting explicit port mappings for ${APP}..."
# Replace any existing port mappings with desired one
run_dokku ports:set "${APP}" http:80:3210 http:8080:3211

# Ensure postgres plugin is installed
echo "Ensuring postgres plugin is installed..."
# Workaround for SIGPIPE from plugin:list when piped; temporarily disable pipefail
set +o pipefail
if run_dokku plugin:list 2>/dev/null | grep -qE "(^|[[:space:]])postgres([[:space:]]|$)"; then
  echo "Postgres plugin already installed."
else
  # Install requires root; prefer sudo, fallback to su
  if command -v sudo >/dev/null 2>&1; then
    sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
  else
    su -c "dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres"
  fi
fi
set -o pipefail

echo "Creating postgres service ${DB} (if missing)..."
if run_dokku postgres:info "${DB}" >/dev/null 2>&1; then
  echo "Postgres service ${DB} already exists."
else
  run_dokku postgres:create "${DB}"
fi

echo "Linking ${DB} -> ${APP} (if missing)..."
if run_dokku postgres:links "${DB}" | grep -qE "\b${APP}\b"; then
  echo "Service ${DB} already linked to ${APP}."
else
  run_dokku postgres:link "${DB}" "${APP}"
fi

DEPLOY_SUCCEEDED=false
if git remote | grep -q "^dokku$"; then
  # Ensure the dokku remote points at the selected app name
  EXISTING_URL=$(git remote get-url dokku 2>/dev/null || true)
  if [[ -n "${EXISTING_URL}" ]]; then
    REMOTE_APP=""
    NEW_URL=""
    if [[ ${EXISTING_URL} =~ ^ssh:// ]]; then
      # ssh://dokku@host[:port]/app or ssh://dokku@host/app
      REMOTE_APP=${EXISTING_URL##*/}
      PREFIX=${EXISTING_URL%/*}
      NEW_URL="${PREFIX}/${APP}"
    else
      # scp-like syntax dokku@host:app
      REMOTE_APP=${EXISTING_URL#*:}
      HOSTSPEC=${EXISTING_URL%%:*}
      NEW_URL="${HOSTSPEC}:${APP}"
    fi
    if [[ -n "${REMOTE_APP}" && "${REMOTE_APP}" != "${APP}" ]]; then
      echo "Updating 'dokku' git remote to point to app '${APP}' (was '${REMOTE_APP}')."
      git remote set-url dokku "${NEW_URL}"
    fi
  fi
  echo "Pushing to Dokku (branch: master)..."
  git push dokku master
  DEPLOY_SUCCEEDED=true
else
  echo "No 'dokku' git remote configured; skipping git push."
  echo "Add one with: git remote add dokku dokku@<host>:${APP}"
  echo "Or deploy using Dokku commands like 'dokku git:sync ${APP} <repo> <branch>' if available."
fi

if [ "${DEPLOY_SUCCEEDED}" = true ]; then
  # Read and print Convex admin key with warning
  echo "Checking for Convex admin key (CONVEX_ADMIN_KEY)..."
  ADMIN_KEY=$(run_dokku config:get "${APP}" CONVEX_ADMIN_KEY || true)
  if [ -n "${ADMIN_KEY:-}" ]; then
    echo "================= IMPORTANT SECRET ================="
    echo "Convex admin key for app '${APP}':"
    echo "${ADMIN_KEY}"
    echo "WARNING: Save this key securely now. It grants admin access."
    echo "===================================================="
  else
    echo "No CONVEX_ADMIN_KEY set for '${APP}'."
    echo "Set one with: dokku config:set ${APP} CONVEX_ADMIN_KEY=..."
  fi
else
  echo "Skipping admin key retrieval because deploy did not complete."
fi

echo "Done. Deployed ${APP}."
