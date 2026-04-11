# Motivation
Multi user Jupyterhub with Python and code-server, ready to use. [Jupyterhub is already dockerized](https://hub.docker.com/r/jupyterhub/jupyterhub/) but ```"This image contains only the Hub itself, with no configuration. In general, one needs to make a derivative image, with at least a jupyterhub_config.py setting up an Authenticator and/or a Spawner."```. Here is a full example with config, nginx and student image.

## Installation
Copy `nginx/nginx.conf.example` to `nginx/nginx.conf` and replace `course.example.com` with your hostname.

For **HTTPS with Let's Encrypt**, copy `nginx/nginx.conf.example-with-ssl` to `nginx/nginx.conf` instead, copy `.env.example` to `.env`, set `CERTBOT_DOMAIN` and `CERTBOT_EMAIL` to match that hostname, then use `docker compose` as below (the stack includes a `certbot` service and shared volumes for certificates and the ACME webroot).

```
docker compose build
docker build -t student-image ./student
docker compose up -d
```

## Create user
Creating a user called user1.
```
docker compose exec hub bash
adduser user1
usermod -aG students javi
```

## Usage
JupyterLab already has a simple editor with syntax highlighting for Python (that gets automatically applied when the file extension is .py, but you may want something more advanced. Login with your created user. To start code-server first start a terminal, then cat /home/jovyan/.config/code-server/config.yaml to get the password (which will be different from the auth password. Then go to course.example.com/user/<user1>/proxy/8080 (replace domain and <user1> accordingly)

## Security
Each student spwns its own container. You may want to remove the line about passwordless sudo in students/Dockerfile if you don't need your students to have root access inside the container.
