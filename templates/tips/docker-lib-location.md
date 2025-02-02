https://linuxconfig.org/how-to-move-docker-s-default-var-lib-docker-to-another-directory-on-ubuntu-debian-linux

sudo systemctl stop docker.service
sudo systemctl stop docker.socket
sudo subl /lib/systemd/system/docker.service

Look for a line like this : ExecStart=/usr/bin/dockerd -H fd://
Change it with : ExecStart=/usr/bin/dockerd --data-root /mnt/data/var/lib/docker/ -H fd://

sudo systemctl daemon-reload
sudo systemctl start docker