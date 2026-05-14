# Moving Docker's Data Directory

**What it solves**: Docker stores all images, containers, volumes, and build cache under `/var/lib/docker` by default. When your root partition fills up (common on systems with a small `/` and a separate large data disk), you need to relocate this directory.

## Steps

```bash
# 1. Stop Docker completely
sudo systemctl stop docker.service
sudo systemctl stop docker.socket

# 2. Edit the Docker service unit to set a new data root
sudo nano /lib/systemd/system/docker.service

# Find this line:
#   ExecStart=/usr/bin/dockerd -H fd://
# Change it to:
#   ExecStart=/usr/bin/dockerd --data-root /mnt/data/var/lib/docker/ -H fd://

# 3. (Optional) Copy existing data to the new location
sudo rsync -aP /var/lib/docker/ /mnt/data/var/lib/docker/

# 4. Reload and restart
sudo systemctl daemon-reload
sudo systemctl start docker

# 5. Verify the new root is active
docker info | grep "Docker Root Dir"
```

## The risk: network mount

If `/mnt/data` is a **network filesystem** (NFS, CIFS/SMB, iSCSI), Docker will break on any network interruption — containers will fail to start, image pulls will corrupt, and volumes may go missing. Use network mounts only if you have a reliable, low-latency connection and understand the failure mode.

**Recommended targets**: A local SSD partition, an LVM logical volume, or a dedicated physical disk mounted at a stable path.

## Verify migration

```bash
docker info | grep "Docker Root Dir"
# Should show your new path, e.g.:
# Docker Root Dir: /mnt/data/var/lib/docker
```

Run `docker images` and `docker ps -a` to confirm existing images and containers are visible after the move.

Reference: https://linuxconfig.org/how-to-move-docker-s-default-var-lib-docker-to-another-directory-on-ubuntu-debian-linux
