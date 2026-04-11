FROM quay.io/jupyter/scipy-notebook:2026-04-06

USER root

RUN apt-get update && apt-get install -y \
    curl git nano \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN pip install --no-cache-dir \
    jupyterhub \
    jupyter-server-proxy

USER jovyan

