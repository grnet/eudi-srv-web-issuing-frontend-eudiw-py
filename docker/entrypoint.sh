#!/usr/bin/env sh
#
# Render the config template and repoint the metadata, then start the app.
#
# Two things need doing before the frontend can run anywhere but the VM it was
# configured for:
#
#   1. The config is a template. The app's loader is a plain yaml.safe_load()
#      with no variable expansion (app/__init__.py:58), so the placeholders have
#      to be substituted before it ever sees the file.
#
#   2. app/metadata_config/*.json hardcode absolute URLs and are read from a
#      fixed path next to the code. No setting reaches them.
#
# Both happen on the container's own copies, so the repo's files are untouched
# and `git status` stays clean.

set -eu

TEMPLATE="${CONFIG_TEMPLATE:-/tmp/config.yaml.template}"
RENDERED="${ISSUER_CONFIG_PATH:-/config.yaml}"

if [ -f "$TEMPLATE" ]; then
    envsubst < "$TEMPLATE" > "$RENDERED"

    # A leftover placeholder means a variable was missing from the environment.
    # Stopping here beats serving a page that links to a literal "${VAR}".
    # Comments are skipped so prose about the templating cannot fail the run.
    if grep -v '^[[:space:]]*#' "$RENDERED" | grep -q '\${'; then
        echo "entrypoint: unsubstituted variables remain in $RENDERED:" >&2
        grep -vn '^[[:space:]]*#' "$RENDERED" | grep '\${' >&2
        exit 1
    fi
    echo "entrypoint: rendered $TEMPLATE -> $RENDERED"
fi

# The metadata names three services on the same host, distinguished only by
# port. Replacing the host and leaving the ports alone keeps all three correct.
if [ -n "${FRONTEND_HOST:-}" ]; then
    META_DIR="${FRONTEND_METADATA_DIR:-/app/app/metadata_config}"
    if [ -d "$META_DIR" ]; then
        sed -i -E "s#(https://)[A-Za-z0-9._-]+(:[0-9]+)#\1${FRONTEND_HOST}\2#g" \
            "$META_DIR"/*.json
        echo "entrypoint: frontend metadata points at $FRONTEND_HOST"
    fi
fi

exec "$@"
