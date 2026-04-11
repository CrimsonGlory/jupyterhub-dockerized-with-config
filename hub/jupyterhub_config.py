from dockerspawner import DockerSpawner

c = get_config()

# --- PAM Authentication ---
c.JupyterHub.authenticator_class = "jupyterhub.auth.PAMAuthenticator"
c.PAMAuthenticator.allowed_groups = {"students"}

# --- Spawner ---
c.JupyterHub.spawner_class = DockerSpawner

c.DockerSpawner.image = "student-image:latest"
c.DockerSpawner.remove = False

# Match usernames
c.DockerSpawner.username_template = "{username}"

# Persistent storage
c.DockerSpawner.volumes = {
    "jupyterhub-user-{username}": "/home/student"
}

# Resource limits (your 32GB system)
c.DockerSpawner.mem_limit = 3 * 1024 * 1024 * 1024
c.DockerSpawner.cpu_limit = 2

# Networking
c.DockerSpawner.network_name = "jupyterhub-network"

# Spawner cmd
#c.Spawner.cmd = ["jupyterhub-singleuser"]

# Default URL (JupyterLab)
c.Spawner.default_url = "/lab"

# Keep containers running
c.JupyterHub.cleanup_servers = False

# Security
c.JupyterHub.hub_ip = "0.0.0.0"

