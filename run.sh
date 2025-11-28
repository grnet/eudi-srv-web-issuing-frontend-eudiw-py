#!/usr/bin/env bash

if [ -f ".config.hostname" ]; then
    HOST=$(<.config.hostname)
elif [ -f ".config.ip" ]; then
    HOST=$(<.config.ip)
else
    echo "Missing frontend setup"
    exit
fi

source .venv/bin/activate
export FLASK_RUN_PORT=5602
export ISSUER_URL=https://snf-74864.ok-kno.grnetcloud.net:5600/
export SERVICE_URL=https://snf-74864.ok-kno.grnetcloud.net:5602/

echo "Running in branch: "$(git rev-parse --abbrev-ref HEAD)
flask --app app run --debug --cert=/etc/letsencrypt/live/snf-74864.ok-kno.grnetcloud.net/fullchain.pem --key=/etc/letsencrypt/live/snf-74864.ok-kno.grnetcloud.net/privkey.pem --host="$HOST" --port ${FLASK_RUN_PORT}
