FROM quay.io/jupyter/scipy-notebook:2026-04-06

USER root

RUN apt-get update && apt-get install -y \
    curl git nano \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN pip install --no-cache-dir \
    jupyterhub \
    jupyter-server-proxy
# Security: you may want to remove this if you don't need sudo inside the containers.
RUN echo "jovyan ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jovyan-nopasswd \
    && chmod 0440 /etc/sudoers.d/jovyan-nopasswd

USER jovyan

