#!/bin/sh
# Certbot requires --deploy-hook to be an executable path; the .py helper may be bind-mounted without +x.
exec python3 /usr/local/lib/certbot-hooks/reload-via-docker-socket.py
