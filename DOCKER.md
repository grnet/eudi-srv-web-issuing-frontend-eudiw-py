# Local development with Docker: issuer frontend

Runs the frontend as a container over HTTPS, with certificate verification
switched **on**. No virtualenv, no `sudo`, no `certbot`.

This is the web UI a person uses to request a credential. It needs both other
services, which live in their own repositories and have their own `DOCKER.md`:

| Service | Repository | Port |
| --- | --- | --- |
| Authorization server | `eudi-srv-issuer-oidc-py` | 5601 |
| Issuer backend | `eudi-srv-web-issuing-eudiw-py` | 5600 |
| Frontend (this one) | | 5602 |

Start them in that order. The authorization server creates the Docker network
and the development CA that all three share, and this service asks the issuer to
sign its metadata while starting up.

## Quick start

In the authorization server repository:

```sh
./pki/bootstrap.sh     # once; mints the CA all three services trust
docker compose up -d
```

In the issuer repository:

```sh
./pki/bootstrap.sh     # once; lays out the document-signing material
docker compose up -d
```

Then here:

```sh
docker compose up --build
```

Open <https://localhost:5602>. The browser warns until the development CA is
imported; the command for that is in the authorization server's `DOCKER.md`.

To check it from a shell, using the CA from that checkout:

```sh
curl --cacert /path/to/eudi-srv-issuer-oidc-py/pki/out/ca.crt https://localhost:5602/
```

No `-k`. A 200 means TLS is verifying properly.

## What this service needs from the others

At startup it POSTs its own metadata to the issuer's `/metadata/metadata_signer`
and **exits if that call fails**, so the issuer has to be running first. The
issuer's compose declares a healthcheck and this stack waits on it, so a single
`docker compose up` from a parent project orders them correctly. Started on its
own against a stopped issuer, the container restarts until the issuer appears.

Two configuration values, `backend_url` and `oauth_url`, are used for two
different things at once: this container makes server-side calls with them, and
the browser follows them as redirects. Unlike the issuer, which has a separate
`internal_url`, there is no way to split those here. The compose file maps
`localhost` to the Docker host so a browser-facing URL also resolves from inside
the container; the other services' certificates carry a SAN for `localhost`, so
TLS still verifies either way.

## Configuration

`docker/config.yaml.template` is a template, not the file the application reads.
At container start `docker/entrypoint.sh` runs `envsubst` over it and writes the
result to the path the application loads:

| In the container | What |
| --- | --- |
| `/tmp/config.yaml.template` | the template, mounted read-only from `docker/` |
| `/config.yaml` | the rendered config, what the app reads |

Two files because the mount is read-only, so the rendered output cannot overwrite
it. Your file on disk is never modified and stays a clean template.

The substitution is needed because the application's config loader is a plain
`yaml.safe_load()` with no variable expansion
([`app/__init__.py:58`](app/__init__.py)). A placeholder left unsubstituted stops
startup rather than serving pages that link to a literal `${...}`.

Only three values are templated, all URLs that differ between a laptop and a
deployed host:

| Variable | Locally | Purpose |
| --- | --- | --- |
| `FRONTEND_PUBLIC_URL` | `https://localhost:5602` | this service's own address |
| `ISSUER_PUBLIC_URL` | `https://localhost:5600` | the issuer backend |
| `OIDC_PUBLIC_URL` | `https://localhost:5601` | the authorization server |

The credential list and everything else in that file is identical in every
environment and stays literal.

The entrypoint also rewrites the host inside `app/metadata_config/*.json`, which
hardcode absolute URLs for all three services and are read from a fixed path next
to the code. Only the host is replaced, so the ports keep pointing at the right
service. That happens on the image's copy inside the container, so the tracked
files are never touched and `git status` stays clean.

Ports come from `.env`. Copy `.env.example` if something already listens on 5602.

## TLS

This service has no PKI of its own. It mounts the `eudiw-pki` volume created by
the authorization server's `pki/bootstrap.sh`, which issues a leaf for each
service in the stack, `frontend` included. Each leaf carries subject alternative
names for both the compose service name and `localhost`, so a certificate works
whether it is reached from a sibling container or from the host.

## Day to day

```sh
docker compose up -d              # start
docker compose logs -f            # follow logs
docker compose restart            # after editing docker/config.yaml.template
docker compose up -d --build      # after changing requirements.txt or the CSS
docker compose down               # stop
```

`app/` is bind-mounted, so ordinary code edits are picked up by the Flask
reloader without a rebuild. The Tailwind CSS build runs in the image, so changes
to styles do need `--build`.

## Two compose files in this repo

Upstream ships `docker-compose.yml`, which pulls the published `ghcr.io` image.
It is untouched and still works:

```sh
docker compose -f docker-compose.yml up
```

Compose prefers `compose.yaml`, so a bare `docker compose up` runs the local
development stack instead. With both files present Compose prints
`Found multiple config files with supported names` on every command, followed by
the one it chose. That warning is noise rather than a problem.

## Troubleshooting

**The container restarts in a loop**, with `Connection refused` for
`/metadata/metadata_signer`. The issuer is not running, or not yet ready. Start
it first and this settles on its own.

**`500 Server Error` from `/metadata/metadata_signer`**. The issuer could not
sign the metadata. Its logs give the reason; the usual causes are a
document-signing key it cannot read, or a `frontend_id` it does not recognise.

**`unsubstituted variables remain`**. A variable used by the config template is
missing from the environment. The entrypoint prints which ones.

**Certificate errors after regenerating the CA**. The leaves changed but running
containers still hold the old ones. `docker compose restart` in all three
repositories.
