#!/bin/bash

# Define server details and remote directory
SERVER="deploy@84.234.19.192"
REMOTE_DIR="/home/deploy/vaultwarden-raess"

echo "=== Ensuring remote directory exists ==="
ssh $SERVER "mkdir -p $REMOTE_DIR"

echo "=== Syncing configuration files ==="
scp docker-compose.yml $SERVER:$REMOTE_DIR/
scp .env $SERVER:$REMOTE_DIR/

echo "=== Updating and restarting Vaultwarden on server ==="
ssh $SERVER << EOF
    cd $REMOTE_DIR
    docker compose pull
    docker compose down
    docker compose up -d
    docker system prune -f
EOF

echo "=== Deployment complete! ==="
