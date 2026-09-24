# Deploying the issuer frontend

One container, its own stack. `docker-build.yml` publishes an image on push;
`docker-deploy.yml` is manual only, so merging a branch never changes what is
running.

The deploy drives the box's Docker daemon over SSH. Nothing is copied to the
server: compose reads the file and the environment on the runner and sends the
daemon an already-expanded spec.

## Why this is standalone, unlike the OIDC server

The OIDC server shares the issuer's stack because it has two URLs for one
service: `base_url` for the browser and `internal_url` for the issuer's
server-to-server calls. Co-locating them is what makes the internal one
meaningful.

The frontend has no such pair. It makes three server-side calls, two to the
issuer at startup (`/.well-known/openid-credential-issuer` and
`/metadata/metadata_signer`) and one to the OIDC server per request
(`/pushed_authorization`, proxied in `app/auth_redirect.py`), and every one of
them works fine over the public URL. Nothing calls the frontend except a browser.

It also has no database, no volumes and no init container, so there is nothing to
share. Talking to the backend over HTTPS is also the honest configuration: it is
what a deployment would look like if the frontend ran on a different host.

Two consequences accepted deliberately:

`setup_metadata()` calls the backend at **import time**, so if the issuer is down
the frontend crashes on start. `restart: unless-stopped` retries, and the
`9c9b5c1` fix carried on `grnet` makes the fallback path work instead of raising
`UnboundLocalError`. That fix matters more here than it would in a coupled stack.

The PAR proxy hairpins: browser to proxy to frontend, back out through the proxy
to the OIDC server. One extra local hop, not a correctness problem.

## Repository secrets

| Secret | What it is |
| --- | --- |
| `SSH_KEY` | Private key authorised for `ubuntu@3.69.83.252`. Written to `~/.ssh/eudiw-deploy` on the runner. |

That is all. The frontend has no credentials of its own: the three URLs and the
frontend id in `stack.env` are public, which is why the config template is
committed.

## Routing

    VIRTUAL_HOST=demo.eudiw.grnet.gr
    VIRTUAL_PATH=/frontend/
    VIRTUAL_DEST=/

`/frontend/` on the shared hostname, alongside `/` (status list),
`/wallet-provider/`, `/issuer/` and `/auth/`. `VIRTUAL_DEST=/` strips the prefix,
so the app serves at its own root and is unaware of it.

### url_for() is not enough: the app needs SCRIPT_NAME

An earlier version of this file said the templates use `url_for()` and therefore
"assets resolve correctly behind the prefix". The premise is right and the
conclusion is wrong, and the page was broken in production until 2026-09-24.

`url_for('static', ...)` appears 140 times and nothing is hardcoded, which is
correct Flask. But `url_for` builds URLs from the WSGI `SCRIPT_NAME`, and
nothing sets it: `VIRTUAL_DEST=/` strips the prefix before the request arrives,
so the app genuinely believes it is at the root. The URLs come out absolute:

    href="/static/bootstrap-3.4.1-dist/css/bootstrap.min.css"      404
    href="/frontend/static/bootstrap-3.4.1-dist/css/bootstrap.min.css"  200

The browser drops the prefix and the request lands on whatever owns the host
root, which here is the status list. **The page returns 200 and renders
unstyled**, with every stylesheet, script and image 404ing in the console. There
is no HTTP status that shows this.

Verified there is no configuration-only fix on this side: nginx-proxy sends no
`SCRIPT_NAME`, and this app ignores an `X-Script-Name` header, tested against
the running container.

**Worked around in the proxy**, in `eudi-srv-wallet-provider`'s compose, as a
per-path location config keyed on `sha1("/frontend/")`:

    sub_filter 'href="/static/' 'href="/frontend/static/';
    sub_filter 'src="/static/'  'src="/frontend/static/';

so that this repository carries no deployment-specific change. Changing
`FRONTEND_PATH` means changing that config and its filename hash too.

The proper fix is `ProxyFix` or an explicit `SCRIPT_NAME` in the WSGI stack,
which would make the app prefix-aware and let the rewrite go. That is upstream
work: their app cannot currently be served under a path at all.

Checked at the same time: `/issuer/` and `/auth/` do **not** have this problem.
Neither emits a single absolute `/static/` reference.

### It needs the discovery rewrite too

The frontend serves `/.well-known/<service>` under **its own identity**: it
fetches signed metadata from the issuer's `/metadata/metadata_signer` at startup
and republishes it. So it is a credential issuer for discovery purposes, not just
a UI.

That means RFC 8414 applies to it as it does to the issuer and the OIDC server: a
client asking about `https://host/frontend` fetches
`https://host/.well-known/openid-credential-issuer/frontend`, which lands at the
host root where the status list is.

The rule lives in `eudi-srv-wallet-provider`'s deploy compose, mounted at
`/etc/nginx/vhost.d/demo.eudiw.grnet.gr`, and proxies to
`<host>-<sha1 of VIRTUAL_PATH>`. Changing `FRONTEND_PATH` means recomputing that
hash there:

    printf '%s' "/frontend/" | sha1sum

## Configuration

`app/__init__.py:58` reads `ISSUER_CONFIG_PATH` and `yaml.safe_load`s the file
with no variable expansion, so substitution happens on the runner.
`deploy/frontend_config.yaml.template` is rendered with `envsubst` and passed to
compose, which mounts it at `/app/frontend_config.yaml`.

`/app` rather than `/etc/issuer_config`: compose writes config content into the
container at create time and does not create parent directories, so the
destination has to exist in the image.

## Deploying by hand

`workflow_dispatch` only registers once the workflow file is on the default
branch, so until this merges use `./deploy.sh` (untracked).

    ./deploy.sh              sha- tag of HEAD
    ./deploy.sh <tag>        a specific tag
    RECREATE=1 ./deploy.sh   after a config-only change

Compose does not recreate a container when only a config's content changes, so a
change to `stack.env` or the template deploys without taking effect until the
container is recreated.

## Still to sort

- `FRONTEND_PUBLIC_URL` in the issuer's `stack.env` still points at the EU
  reference instance. Repoint it once this is deployed and verified.
- `e1799bb` on `deploy-okeanos-v8` swaps the `credential_request_encryption`
  public JWK for a GRNET one. Not carried: the matching private key is not in
  this repository, and advertising a key nobody holds is worse than advertising
  the reference one. See `TODO.md`.
