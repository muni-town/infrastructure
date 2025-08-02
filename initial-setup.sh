#!/bin/bash

set -ex

echo "Starting initial server setup"

echo "Installing docker compose"

mkdir -p /root/.docker/cli-plugins/
curl -SL https://github.com/docker/compose/releases/download/v2.30.1/docker-compose-linux-x86_64 -o /root/.docker/cli-plugins/docker-compose
chmod +x /root/.docker/cli-plugins/docker-compose

echo "Starting docker compose core stack"

docker network create webgateway
cd /docker-compose-core-stack
docker compose up -d

echo "Initial server setup complete! 🎉"