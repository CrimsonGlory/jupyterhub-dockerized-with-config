#!/usr/bin/env python3
"""
Ask Docker Engine to send SIGHUP to the nginx container (reload) via the Unix socket.
The official certbot image does not ship curl; Python is always available.
"""
import os
import socket
import sys

DOCKER_SOCK = os.environ.get("DOCKER_HOST_PATH", "/var/run/docker.sock")
DOCKER_API = os.environ.get("DOCKER_API_VERSION", "v1.41")
NGINX_CONTAINER = os.environ.get("NGINX_CONTAINER", "nginx")


def main():
    req = (
        f"POST /{DOCKER_API}/containers/{NGINX_CONTAINER}/kill?signal=HUP "
        "HTTP/1.1\r\nHost: docker\r\nConnection: close\r\n\r\n"
    ).encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(DOCKER_SOCK)
        s.sendall(req)
        s.recv(65536)


if __name__ == "__main__":
    try:
        main()
    except OSError:
        sys.exit(0)
