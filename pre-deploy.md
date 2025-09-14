
# Enable strict mode for safer scripts
set -euo pipefail
IFS=$'\n\t'

# TODO: Add pre-deployment steps below
dokku apps:create convex

# Generate nginx.conf from tempplate
dokku proxy:build-config convex
    

 # Create postgres DB for convex
dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
dokku postgres:create convex-db

    # Get url
    dokku postgres:info convex-db

# Linking injects DATABASE_URL into the app’s config automatically (DONT)
# dokku postgres:link convex-db convex

    # Check and remove "/convex_db" from end of string
    dokku config convex
# manually set connection string
dokku config:set convex POSTGRES_URL='postgres://postgres:d25c69f87df2bfb51fef75abdc5076a4@dokku-postgres-convex-db:5432'

# Set api & actions urls with your domain in dokku
dokku domains:set convex api.*.* actions.*.*

# Deploy (set url)
git remote add dokku dokku@YOUR_HOST:convex
git push dokku main

# Port mapping in dokku
dokku ports:set convex http:80:3210
dokku ports:set convex https:443:3210
dokku ports:add convex http:8080:3211

# Create nginx template for actions endpont port mapping to same container
    # copy the default template as a starting point
    sudo mkdir -p /home/dokku/convex
    sudo cp /var/lib/dokku/plugins/available/nginx-vhosts/templates/nginx.conf.sigil \
            /home/dokku/convex/nginx.conf.sigil

# Config domains and pors using this template in /home/dokku/convex/nginx.conf.sigil

# --- upstreams (define for each Convex port) ---
upstream {{ $.APP }}-3210 {
{{ range $listeners := $.DOKKU_APP_WEB_LISTENERS | split " " }}
{{ $listener_list := $listeners | split ":" }}
{{ $listener_ip := index $listener_list 0 }}
  server {{ $listener_ip }}:3210;
{{ end }}
}

upstream {{ $.APP }}-3211 {
{{ range $listeners := $.DOKKU_APP_WEB_LISTENERS | split " " }}
{{ $listener_list := $listeners | split ":" }}
{{ $listener_ip := index $listener_list 0 }}
  server {{ $listener_ip }}:3211;
{{ end }}
}

# --- API: Convex client port ---
server {
  listen      [{{ $.NGINX_BIND_ADDRESS_IP6 }}]:80;
  listen      {{ if $.NGINX_BIND_ADDRESS_IP4 }}{{ $.NGINX_BIND_ADDRESS_IP4 }}:{{end}}80;
  server_name api.example.com;

  location / {
    proxy_pass http://{{ $.APP }}-3210;
    include {{ $.NGINX_SERVER_CONF }};
  }

  {{ if $.SSL_INUSE }}
  listen      [{{ $.NGINX_BIND_ADDRESS_IP6 }}]:443 ssl http2;
  listen      {{ if $.NGINX_BIND_ADDRESS_IP4 }}{{ $.NGINX_BIND_ADDRESS_IP4 }}:{{end}}443 ssl http2;
  ssl_certificate           {{ $.APP_SSL_PATH }}/server.crt;
  ssl_certificate_key       {{ $.APP_SSL_PATH }}/server.key;
  ssl_protocols             TLSv1.2 {{ if eq $.TLS13_SUPPORTED "true" }}TLSv1.3{{ end }};
  ssl_prefer_server_ciphers off;

  include {{ $.NGINX_SSL_CONFIG }};
  {{ end }}
}

# --- Actions: HTTP actions/webhooks port ---
server {
  listen      [{{ $.NGINX_BIND_ADDRESS_IP6 }}]:80;
  listen      {{ if $.NGINX_BIND_ADDRESS_IP4 }}{{ $.NGINX_BIND_ADDRESS_IP4 }}:{{end}}80;
  server_name actions.example.com;

  location / {
    proxy_pass http://{{ $.APP }}-3211;
    include {{ $.NGINX_SERVER_CONF }};
  }

  {{ if $.SSL_INUSE }}
  listen      [{{ $.NGINX_BIND_ADDRESS_IP6 }}]:443 ssl http2;
  listen      {{ if $.NGINX_BIND_ADDRESS_IP4 }}{{ $.NGINX_BIND_ADDRESS_IP4 }}:{{end}}443 ssl http2;
  ssl_certificate           {{ $.APP_SSL_PATH }}/server.crt;
  ssl_certificate_key       {{ $.APP_SSL_PATH }}/server.key;
  ssl_protocols             TLSv1.2 {{ if eq $.TLS13_SUPPORTED "true" }}TLSv1.3{{ end }};
  ssl_prefer_server_ciphers off;

  include {{ $.NGINX_SSL_CONFIG }};
  {{ end }}
}


# This lets us use custom sigil with deployment from image (IMPORTANT)
https://github.com/dewey/dokku-nginx-override-by-app

dokku plugin:install https://github.com/dewey/dokku-nginx-override-by-app.git
dokku nginx-override-by-app:add convex /home/dokku/convex/nginx.conf.sigil

    # Configs:
    /var/lib/dokku/data/nginx-override-by-app


