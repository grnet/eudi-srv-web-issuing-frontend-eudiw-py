#!/usr/bin/env bash

if [ -f ".config.hostname" ]; then
    HOST=$(<.config.hostname)
    TLS="--cert=/etc/letsencrypt/live/${HOST}/fullchain.pem --key=/etc/letsencrypt/live/${HOST}/privkey.pem"
elif [ -f ".config.ip" ]; then
    HOST=$(<.config.ip)
    TLS=
else
    echo "Missing frontend setup"
    exit
fi

source .venv/bin/activate
export FLASK_RUN_PORT=5602
export ISSUER_CONFIG_PATH=$(realpath frontend_config.yaml)

echo "Running in branch: "$(git rev-parse --abbrev-ref HEAD)
flask --app app run --debug ${TLS} --host="$HOST" --port ${FLASK_RUN_PORT}
