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

# Ensure DATABASE_URL is set from the postgres service DSN (trim DB name)
echo "Ensuring DATABASE_URL is set once with base DSN..."
# Try to read DSN directly from the service; fall back to current config if unavailable
DB_DSN=""
if run_dokku postgres:info "${DB}" --dsn >/dev/null 2>&1; then
  DB_DSN=$(run_dokku postgres:info "${DB}" --dsn | tr -d '\r' | tail -n1)
else
  # Fallback: attempt to parse from serialized info
  DB_DSN=$(run_dokku postgres:info "${DB}" --serialized 2>/dev/null | awk -F': ' '/DSN/ {print $2}' | tr -d '\r' | tail -n1 || true)
fi

if [[ -z "${DB_DSN}" ]]; then
  echo "Warning: Could not determine DSN from service ${DB}. Leaving existing DATABASE_URL as-is."
else
  # Trim the trailing "/<db_name>" part from DSN (e.g., "/conapi_db") to keep only scheme://user:pass@host:port
  # Prefer robust trim by capturing scheme+authority; fallback to removing last path segment.
  DB_BASE_DSN=$(printf "%s" "${DB_DSN}" | sed -E 's#(postgres(ql)?://[^/]+).*#\1#')
  if [[ -z "${DB_BASE_DSN}" || "${DB_BASE_DSN}" == "${DB_DSN}" && "${DB_DSN}" == *"/"* ]]; then
    # Fallback: drop everything after the final slash
    DB_BASE_DSN="${DB_DSN%/*}"
  fi

  CURRENT_DB_URL=$(run_dokku config:get "${APP}" DATABASE_URL || true)
  if [[ "${CURRENT_DB_URL}" == "${DB_BASE_DSN}" ]]; then
    echo "DATABASE_URL already set to trimmed base; skipping."
  else
    echo "Saving trimmed base DATABASE_URL to app config..."
    run_dokku config:set "${APP}" DATABASE_URL="${DB_BASE_DSN}"
  fi
fi

DEPLOY_SUCCEEDED=false
echo "Deploying using image via dokku git:from-image..."
# Use the specified image reference; deploy to the selected app name
if run_dokku git:from-image "${APP}" ghcr.io/get-convex/convex-backend:08139ef318b1898dad7731910f49ba631631c902; then
  DEPLOY_SUCCEEDED=true
else
  echo "dokku git:from-image failed. Check Dokku logs for details."
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
