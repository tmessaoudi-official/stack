#!/bin/bash

# Load OS information
. /etc/os-release

# @todo check-updates
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
# @todo change later
echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/docker.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://download.docker.com/linux/ubuntu\nSuites: ${UBUNTU_CODENAME}\nComponents: stable" | sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
sudo apt-get --allow-unauthenticated install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo groupadd docker > /dev/null
sudo usermod -aG docker "${GLOBAL_STACK_DOCKER_USER_ID}"

mkdir -p /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.docker/cli-plugins/

OPERATING_SYSTEM="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [[ "linux" != "${OPERATING_SYSTEM}" && "darwin" != "${OPERATING_SYSTEM}" ]]; then
	echo "Unsupported OS: ${OPERATING_SYSTEM}"
	OPERATING_SYSTEM=""
fi
SYSTEM_ARCH="$(uname -m)"

# x86_64 (also known as amd64): 64-bit version of the x86 instruction set, most common for desktops and servers.
# i386/i686: 32-bit versions of the x86 architecture, used in older systems.
# armv6l: ARM 32-bit, used in older ARM devices like Raspberry Pi 1.
# armv6lhf: ARM 32-bit hard float, used in older ARM devices like Raspberry Pi 1.
# armv6hf: ARM 32-bit hard float, used in older ARM devices like Raspberry Pi 1.
# armv7l: ARM 32-bit, used in newer 32-bit ARM devices (Raspberry Pi 2, etc.).
# aarch64: 64-bit ARM architecture, used in newer ARM devices (Raspberry Pi 3, Raspberry Pi 4, etc.).
# ppc64le: PowerPC 64-bit little-endian, often used in IBM systems.
# s390x: IBM mainframe architecture, used in enterprise environments.
# riscv64: 64-bit RISC-V architecture, used in newer open-source hardware platforms.
# mips: Architecture used in embedded systems and routers.
# mips64: 64-bit version of MIPS architecture.
# sparc: Architecture used in older Sun Microsystems workstations and servers.
# loongarch64: A relatively new Chinese-developed architecture.

DOCKER_COMPOSE_ARCH=""
DOCKER_BUILDX_ARCH=""

if [[ "linux" == "${OPERATING_SYSTEM}" ]]; then
	case "${SYSTEM_ARCH}" in
	"aarch64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="arm64"
		;;
	"armv6l")
		DOCKER_COMPOSE_ARCH="armv6"
		DOCKER_BUILDX_ARCH="arm-v6"
		;;
	"armv7l")
		DOCKER_COMPOSE_ARCH="armv7"
		DOCKER_BUILDX_ARCH="arm-v7"
		;;
	"ppc64le")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="${SYSTEM_ARCH}"
		;;
	"riscv64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="${SYSTEM_ARCH}"
		;;
	"s390x")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="${SYSTEM_ARCH}"
		;;
	"x86_64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="amd64"
		;;
	*)
		echo "Unsupported system/architecture (docker compose)/(docker buildx): ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	esac
fi

if [[ "darwin" == "${OPERATING_SYSTEM}" ]]; then
	case "${SYSTEM_ARCH}" in
	"aarch64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="arm64"
		;;
	"x86_64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="amd64"
		;;
	*)
		echo "Unsupported system/architecture (docker compose)/(docker buildx): ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	esac
fi

if [[ "" != "${OPERATING_SYSTEM}" ]]; then
	if [[ "" != "${DOCKER_COMPOSE_ARCH}" ]]; then
		GLOBAL_UNU_DOCKER_COMPOSEV1_LATEST=${GLOBAL_STACK_DOCKER_COMPOSE_V1_VERSION}
		echo "Installing docker-compose v1 - system : ${OPERATING_SYSTEM}, arch : ${DOCKER_COMPOSE_ARCH}"
		sudo curl -L https://github.com/docker/compose/releases/download/${GLOBAL_UNU_DOCKER_COMPOSEV1_LATEST}/docker-compose-${OPERATING_SYSTEM}-${DOCKER_COMPOSE_ARCH} -o /usr/local/bin/docker-compose
		sudo chmod a+rwx /usr/local/bin/docker-compose

		# GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | jq .name -r)
		GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST=${GLOBAL_STACK_DOCKER_COMPOSE_V2_VERSION}
		echo "Installing docker-compose v2 - system : ${OPERATING_SYSTEM}, arch : ${DOCKER_COMPOSE_ARCH}"
		curl -L https://github.com/docker/compose/releases/download/${GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST}/docker-compose-${OPERATING_SYSTEM}-${DOCKER_COMPOSE_ARCH} -o /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.docker/cli-plugins/docker-compose
		chmod a+rwx /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.docker/cli-plugins/docker-compose
	fi

	if [[ "" != "${DOCKER_BUILDX_ARCH}" ]]; then
		# GLOBAL_UNU_DOCKER_BUILDX_LATEST=$(curl --silent https://api.github.com/repos/docker/buildx/releases/latest | jq .name -r)
		GLOBAL_UNU_DOCKER_BUILDX_LATEST=${GLOBAL_STACK_DOCKER_BUILDX_VERSION}
		echo "Installing docker-buildx - system : ${OPERATING_SYSTEM}, arch : ${DOCKER_BUILDX_ARCH}"
		curl -L https://github.com/docker/buildx/releases/download/${GLOBAL_UNU_DOCKER_BUILDX_LATEST}/buildx-${GLOBAL_UNU_DOCKER_BUILDX_LATEST}.${OPERATING_SYSTEM}-${DOCKER_BUILDX_ARCH} -o /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.docker/cli-plugins/docker-buildx
		chmod a+rwx /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.docker/cli-plugins/docker-buildx
	fi
fi
# Latest Sep 18, 2021, 1:35 PM GMT+1
sudo curl -L https://raw.githubusercontent.com/samoshkin/docker-reclaim-disk-space/master/script.sh -o /usr/local/bin/docker-reclaim-disk-space-script.sh
sudo chmod a+rwx /usr/local/bin/docker-reclaim-disk-space-script.sh

sudo mkdir -p /etc/docker/
sudo touch /etc/docker/daemon.json
echo -e '{\n\t"storage-driver": "overlay2"\n}' | sudo tee /etc/docker/daemon.json