# Motivation

Multi user Jupyterhub with Python and code-server, ready to use. [Jupyterhub is already dockerized](https://hub.docker.com/r/jupyterhub/jupyterhub/) but `"This image contains only the Hub itself, with no configuration. In general, one needs to make a derivative image, with at least a jupyterhub_config.py setting up an Authenticator and/or a Spawner."`. Here is a full example with config, nginx and student image.

## Installation

Copy `nginx/nginx.conf.example` to `nginx/nginx.conf` and replace `course.example.com` with your hostname.

For **HTTPS with Let's Encrypt**, follow the [SSL (Let's Encrypt)](#ssl-lets-encrypt) section below instead of the plain HTTP nginx example.

```
docker compose build
docker build -t student-image ./student
docker compose up -d
```

## SSL (Let's Encrypt)

This repository can obtain and renew TLS certificates using [Let's Encrypt](https://letsencrypt.org/) and the [EFF Certbot](https://certbot.eff.org/) client, with **nginx** terminating HTTPS in front of JupyterHub.

### What you configure

1. Copy `nginx/nginx.conf.example-with-ssl` to `nginx/nginx.conf`.
2. Replace every `course.example.com` in that file with your real public hostname (the same value you use for `CERTBOT_DOMAIN`).
3. Copy `.env.example` to `.env` and set `CERTBOT_DOMAIN` to that hostname. Set `CERTBOT_EMAIL` if you want an account email with Let's Encrypt (recommended for expiry and incident notices). If you leave `CERTBOT_EMAIL` empty, the certbot script uses Certbot’s `--register-unsafely-without-email` flag so no email is registered (Let’s Encrypt will not be able to warn you by email).

### What runs in Docker Compose

- **nginx** listens on ports **80** and **443**. It proxies JupyterHub and serves `/.well-known/acme-challenge/` from a shared volume (`certbot-www`) so Let’s Encrypt can complete **HTTP-01** validation.
- Before nginx loads TLS for the first time, a small **entrypoint script** in the nginx image may create a **short-lived self-signed** certificate under `/etc/letsencrypt/live/<your-domain>/` so nginx can start even before a real certificate exists. Your browser will show a warning only until the first successful issuance replaces those files.
- The **certbot** container waits until nginx answers on port 80, then runs `certbot certonly --webroot` against that shared webroot. When a certificate is issued, a **deploy hook** reloads nginx so it begins serving the Let’s Encrypt chain without a full container restart.
- The same **certbot** container then loops `certbot renew` about every **12 hours**. Renewals reuse the stored authenticator settings; when a certificate is actually renewed, the same hook reloads nginx again.

### Volumes

- `**letsencrypt`**: certificate material and Certbot metadata (`/etc/letsencrypt` in the containers).
- `**certbot-www`**: HTTP-01 challenge files under `/var/www/certbot`.

### Requirements

- DNS for `CERTBOT_DOMAIN` must point to this host.
- **TCP 80** must reach nginx (required for HTTP-01 issuance and renewal). **443** must be reachable for HTTPS clients.

### Caveats

- Let's Encrypt has [rate limits](https://letsencrypt.org/docs/rate-limits/); repeated failed attempts while debugging can temporarily block issuance.
- If something goes wrong and you need a clean slate for certificates, you can remove the named volume that backs `letsencrypt` (this deletes issued certs and account state for that stack) after `docker compose down`, then bring the stack up again.

## Create user

Creating a user called user1.

```
docker compose exec hub bash
adduser user1
usermod -aG students javi
```

## Usage

JupyterLab already has a simple editor with syntax highlighting for Python (that gets automatically applied when the file extension is .py, but you may want something more advanced. Login with your created user. To start code-server first start a terminal, then cat /home/jovyan/.config/code-server/config.yaml to get the password (which will be different from the auth password. Then go to course.example.com/user//proxy/8080 (replace domain and  accordingly)

## Security

Each student spawns its own container. You may want to remove the line about passwordless sudo in students/Dockerfile if you do not need your students to have root access inside the container.

The **certbot** service mounts the host **Docker socket** (`/var/run/docker.sock`) read-only so that, after a certificate is obtained or renewed, Certbot’s deploy hook can ask the Docker engine to send **SIGHUP** to the **nginx** container. Nginx reloads its configuration and picks up the new certificate files from the shared volume without restarting the hub. That socket is powerful: any process that can use it can control the Docker daemon, so treat the host, compose file, and images as part of your trust boundary. If you prefer not to expose the socket, you would need another way to reload nginx after renewals (for example a sidecar or host cron that runs `docker compose exec nginx nginx -s reload` with tightly scoped credentials).