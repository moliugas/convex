
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

# Port mapping in dokku
dokku ports:set convex http:80:3210
dokku ports:add convex https:443:3210

# Create nginx template for actions endpont port mapping to same container
    # copy the default template as a starting point
    sudo mkdir -p /home/dokku/convex
    sudo cp /var/lib/dokku/plugins/available/nginx-vhosts/templates/nginx.conf.sigil \
            /home/dokku/convex/nginx.conf.sigil
    

 # Create postgres DB for convex
dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
dokku postgres:create convex-db

    # Get url
    dokku postgres:info convex-db

# Linking injects DATABASE_URL into the app’s config automatically:
dokku postgres:link convex-db convex

    # Check
    dokku config convex

