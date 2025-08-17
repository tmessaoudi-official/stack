#!/bin/bash

env_file_exists="[ -n \"${GLOBAL_STACK_DOCKER_ROOT_PATH}\" ] && [ -f \"${GLOBAL_STACK_DOCKER_ROOT_PATH}/.env.local\" ]"
if eval "${env_file_exists}"; then
  	eval $(grep -vE "^(COMPOSE_FILE|BUILDX_EXPERIMENTAL|BUILDKIT_PROGRESS|BUILDX_BUILDER|COMPOSE_PROJECT_NAME|COMPOSE_REMOVE_ORPHANS|COMPOSE_HTTP_TIMEOUT|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS|COMPOSE_PATH_SEPARATOR|DOCKER_BUILDKIT|COMPOSE_DOCKER_CLI_BUILD|GLOBAL_STACK_COMPOSE_CLI|GLOBAL_STACK_POSTGRES17_DBS|GLOBAL_STACK_HTTPS_LOCALHOST_IPS|GLOBAL_STACK_HTTPS_CONTAINER_IPS|GLOBAL_STACK_(.*)_COMMAND_SUFFIX|GLOBAL_STACK_(.*)_CLI_OPTIONS|GLOBAL_STACK_(.*)_CLI_VARIANTS|GLOBAL_STACK_ANDROID_SYSTEM_IMAGES|GLOBAL_STACK_ANDROID_PACKAGES)=" "${GLOBAL_STACK_DOCKER_ROOT_PATH}"/.env.local | sed 's/^/export /')
  	eval $(grep -vE "^(COMPOSE_FILE|BUILDX_EXPERIMENTAL|BUILDKIT_PROGRESS|BUILDX_BUILDER|COMPOSE_PROJECT_NAME|COMPOSE_REMOVE_ORPHANS|COMPOSE_HTTP_TIMEOUT|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS|COMPOSE_PATH_SEPARATOR|DOCKER_BUILDKIT|COMPOSE_DOCKER_CLI_BUILD|GLOBAL_STACK_COMPOSE_CLI|GLOBAL_STACK_POSTGRES17_DBS|GLOBAL_STACK_HTTPS_LOCALHOST_IPS|GLOBAL_STACK_HTTPS_CONTAINER_IPS|GLOBAL_STACK_(.*)_COMMAND_SUFFIX|GLOBAL_STACK_(.*)_CLI_OPTIONS|GLOBAL_STACK_(.*)_CLI_VARIANTS|GLOBAL_STACK_ANDROID_SYSTEM_IMAGES|GLOBAL_STACK_ANDROID_PACKAGES)=" "${GLOBAL_STACK_DOCKER_ROOT_PATH}"/.env.local | sed 's/^/export /')
  	eval $(grep -vE "^(COMPOSE_FILE|BUILDX_EXPERIMENTAL|BUILDKIT_PROGRESS|BUILDX_BUILDER|COMPOSE_PROJECT_NAME|COMPOSE_REMOVE_ORPHANS|COMPOSE_HTTP_TIMEOUT|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS|COMPOSE_PATH_SEPARATOR|DOCKER_BUILDKIT|COMPOSE_DOCKER_CLI_BUILD|GLOBAL_STACK_COMPOSE_CLI|GLOBAL_STACK_POSTGRES17_DBS|GLOBAL_STACK_HTTPS_LOCALHOST_IPS|GLOBAL_STACK_HTTPS_CONTAINER_IPS|GLOBAL_STACK_(.*)_COMMAND_SUFFIX|GLOBAL_STACK_(.*)_CLI_OPTIONS|GLOBAL_STACK_(.*)_CLI_VARIANTS|GLOBAL_STACK_ANDROID_SYSTEM_IMAGES|GLOBAL_STACK_ANDROID_PACKAGES)=" "${GLOBAL_STACK_DOCKER_ROOT_PATH}"/.env.local | sed 's/^/export /')
fi

# Update and fix broken dependencies
sudo apt -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
sudo dpkg --configure -a
sudo apt install -y --fix-broken --no-install-recommends --fix-missing

# Perform upgrades
sudo apt upgrade -y
sudo apt dist-upgrade -y
sudo apt full-upgrade -y

# Clean up unnecessary packages and cache
sudo apt purge -y
sudo apt autoremove -y
sudo apt clean -y
sudo apt autoclean -y
sudo apt autopurge -y

# Final update and cleanup of remaining cached files
sudo apt -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
if [[ "" != "$(command -v snap)" ]]; then
	sudo snap refresh
fi
if [[ "" != "$(command -v flatpak)" ]]; then
	flatpak update
fi

mkdir -p ~/.local/bin/ ~/.docker/cli-plugins/ 
if [[ ! -d /opt/"${USER}" ]]; then
	sudo mkdir -p /opt/"${USER}"

	sudo chown -R "${USER}":"${USER}" /opt/"${USER}/"
	sudo chmod -R a+rwx /opt/"${USER}"/
fi

if [[ -n "${ZSH}" && -d "${ZSH}" ]]; then
	git -C "${ZSH}" fetch
	git -C "${ZSH}" pull --rebase
	git -C "${ZSH}" submodule update --init
fi

if [[ -n "${ZSH}" && -d "${ZSH_CUSTOM:-${ZSH}/custom}" ]]; then
	find "${ZSH_CUSTOM:-${ZSH}/custom}"/plugins -mindepth 1 -maxdepth 1 -type d ! -name "example" | while read -r DIR; do
		git -C "${DIR}" fetch
		git -C "${DIR}" pull --rebase
		git -C "${DIR}" submodule update --init
	done
	find "${ZSH_CUSTOM:-${ZSH}/custom}"/themes -mindepth 1 -maxdepth 1 -type d | while read -r DIR; do
		git -C "${DIR}" fetch
		git -C "${DIR}" pull --rebase
		git -C "${DIR}" submodule update --init
	done
fi

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

SONAR_SCANNER_CLI_OPERATING_SYSTEM="${OPERATING_SYSTEM}"
DIFFTASTIC_OPERATING_SYSTEM=""
BAT_OPERATING_SYSTEM=""
SOPS_OPERATING_SYSTEM=""

DOCKER_COMPOSE_ARCH=""
DOCKER_BUILDX_ARCH=""
HADOLINT_ARCH=""
SHELL_CHECK_ARCH=""
GITLEAKS_ARCH=""
SONAR_SCANNER_CLI_ARCH=""
DIFFTASTIC_ARCH=""
SHFMT_ARCH=""
BAT_ARCH=""
TASK_ARCH=""
SOPS_ARCH=""
YAMLFMT_ARCH=""

if [[ "linux" == "${OPERATING_SYSTEM}" ]]; then
	DIFFTASTIC_OPERATING_SYSTEM="unknown-${OPERATING_SYSTEM}-gnu"
	# @todo add linux-musl
	BAT_OPERATING_SYSTEM="unknown-${OPERATING_SYSTEM}-gnu"
	SOPS_OPERATING_SYSTEM="${OPERATING_SYSTEM}"
	case "${SYSTEM_ARCH}" in
	"aarch64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="arm64"
		HADOLINT_ARCH="arm64"
		SHELL_CHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="arm64"
		SONAR_SCANNER_CLI_ARCH="${SYSTEM_ARCH}"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="arm64"
		;;
	"armv6l")
		DOCKER_COMPOSE_ARCH="armv6"
		DOCKER_BUILDX_ARCH="arm-v6"
		GITLEAKS_ARCH="armv6"
		SHFMT_ARCH="arm"
		echo "Unsupported system/architecture hadolint/shell-check/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"armv6hf")
		SHELL_CHECK_ARCH="${SYSTEM_ARCH}"
		echo "Unsupported system/architecture (docker compose)/(docker buildx)/hadolint/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"armv6lhf")
		SHELL_CHECK_ARCH="armv6hf"
		echo "Unsupported system/architecture (docker compose)/(docker buildx)/hadolint/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"armv7l")
		DOCKER_COMPOSE_ARCH="armv7"
		DOCKER_BUILDX_ARCH="arm-v7"
		GITLEAKS_ARCH="armv7"
		SHFMT_ARCH="arm"
		echo "Unsupported system/architecture hadolint/shell-check/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"ppc64le")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="${SYSTEM_ARCH}"
		echo "Unsupported system/architecture hadolint/shell-check/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"riscv64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="${SYSTEM_ARCH}"
		SHELL_CHECK_ARCH="${SYSTEM_ARCH}"
		echo "Unsupported system/architecture hadolint/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"s390x")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="${SYSTEM_ARCH}"
		echo "Unsupported system/architecture hadolint/shell-check/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"x86_64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="amd64"
		HADOLINT_ARCH="${SYSTEM_ARCH}"
		SHELL_CHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="x64"
		SONAR_SCANNER_CLI_ARCH="x64"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="amd64"
		BAT_ARCH="${SYSTEM_ARCH}"
		TASK_ARCH="amd64"
		SOPS_ARCH="amd64"
		YAMLFMT_ARCH="${SYSTEM_ARCH}"
		;;
	"i386")
		GITLEAKS_ARCH="x32"
		SHFMT_ARCH="386"
		echo "Unsupported system/architecture (docker compose)/(docker buildx)/hadolint/shell-check/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"i686")
		GITLEAKS_ARCH="x32"
		SHFMT_ARCH="386"
		echo "Unsupported system/architecture (docker compose)/(docker buildx)/hadolint/shell-check/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	*)
		echo "Unsupported system/architecture (docker compose)/(docker buildx)/hadolint/shell-check/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	esac
fi

if [[ "darwin" == "${OPERATING_SYSTEM}" ]]; then
	SONAR_SCANNER_CLI_OPERATING_SYSTEM="macosx"
	DIFFTASTIC_OPERATING_SYSTEM="apple-${OPERATING_SYSTEM}"
	BAT_OPERATING_SYSTEM="apple-${OPERATING_SYSTEM}"
	SOPS_OPERATING_SYSTEM="${OPERATING_SYSTEM}"
	case "${SYSTEM_ARCH}" in
	"aarch64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="arm64"
		SHELL_CHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="arm64"
		SONAR_SCANNER_CLI_ARCH="${SYSTEM_ARCH}"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="arm64"
		echo "Unsupported system/architecture hadolint: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"x86_64")
		DOCKER_COMPOSE_ARCH="${SYSTEM_ARCH}"
		DOCKER_BUILDX_ARCH="amd64"
		HADOLINT_ARCH="${SYSTEM_ARCH}"
		SHELL_CHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="x64"
		SONAR_SCANNER_CLI_ARCH="x64"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="amd64"
		BAT_ARCH="${SYSTEM_ARCH}"
		TASK_ARCH="amd64"
		SOPS_ARCH="amd64"
		YAMLFMT_ARCH="${SYSTEM_ARCH}"
		;;
	*)
		echo "Unsupported system/architecture (docker compose)/(docker buildx)/hadolint/shell-check/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	esac
fi

if eval "${env_file_exists}"; then
	if [ "" != "${OPERATING_SYSTEM}" ]; then
		if [[ "" != "${DOCKER_COMPOSE_ARCH}" ]]; then
			if  [ -n "${GLOBAL_STACK_DOCKER_COMPOSE_V1_VERSION}" ] && [ "" != "${GLOBAL_STACK_DOCKER_COMPOSE_V1_VERSION}" ]; then
				if [ -f ~/.local/bin/docker-compose ]; then GLOBAL_UNU_DOCKER_COMPOSEV1_VERSION="$(docker-compose -v | sed 's/docker-compose version //' | sed 's/\, build .*//')"; else GLOBAL_UNU_DOCKER_COMPOSEV1_VERSION=0; fi
				GLOBAL_UNU_DOCKER_COMPOSEV1_LATEST=${GLOBAL_STACK_DOCKER_COMPOSE_V1_VERSION}
				if [ "${GLOBAL_UNU_DOCKER_COMPOSEV1_VERSION}" != "${GLOBAL_UNU_DOCKER_COMPOSEV1_LATEST}" ]; then
					echo "Updating/Installing docker-compose v1 - system : ${OPERATING_SYSTEM}, arch : ${DOCKER_COMPOSE_ARCH} https://github.com/docker/compose/releases/download/${GLOBAL_UNU_DOCKER_COMPOSEV1_LATEST}/docker-compose-${OPERATING_SYSTEM}-${DOCKER_COMPOSE_ARCH}"
					curl -L https://github.com/docker/compose/releases/download/${GLOBAL_UNU_DOCKER_COMPOSEV1_LATEST}/docker-compose-${OPERATING_SYSTEM}-${DOCKER_COMPOSE_ARCH} -o ~/.local/bin/docker-compose
					chmod a+rwx ~/.local/bin/docker-compose
				else
					echo "Docker compose v1 is latest '${GLOBAL_UNU_DOCKER_COMPOSEV1_VERSION}'"
				fi
			fi

			if  [ -n "${GLOBAL_STACK_DOCKER_COMPOSE_V2_VERSION}" ] && [ "" != "${GLOBAL_STACK_DOCKER_COMPOSE_V2_VERSION}" ]; then
				if [ -f ~/.docker/cli-plugins/docker-compose ]; then GLOBAL_UNU_DOCKER_COMPOSEV2_VERSION="$(docker compose version | sed 's/Docker Compose version //')"; else GLOBAL_UNU_DOCKER_COMPOSEV2_VERSION=0; fi
				# GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST="$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | jq .name -r)"
				GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST=${GLOBAL_STACK_DOCKER_COMPOSE_V2_VERSION}
				if [ "${GLOBAL_UNU_DOCKER_COMPOSEV2_VERSION}" != "${GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST}" ]; then
					echo "Updating/Installing docker-compose v2 - system : ${OPERATING_SYSTEM}, arch : ${DOCKER_COMPOSE_ARCH} https://github.com/docker/compose/releases/download/${GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST}/docker-compose-${OPERATING_SYSTEM}-${DOCKER_COMPOSE_ARCH}"
					curl -L https://github.com/docker/compose/releases/download/${GLOBAL_UNU_DOCKER_COMPOSEV2_LATEST}/docker-compose-${OPERATING_SYSTEM}-${DOCKER_COMPOSE_ARCH} -o ~/.docker/cli-plugins/docker-compose
					chmod a+rwx ~/.docker/cli-plugins/docker-compose
				else
					echo "Docker compose v2 is latest '${GLOBAL_UNU_DOCKER_COMPOSEV2_VERSION}'"
				fi
			fi
		fi

		if [[ "" != "${DOCKER_BUILDX_ARCH}" && -n "${GLOBAL_STACK_DOCKER_BUILDX_VERSION}" && "" != "${GLOBAL_STACK_DOCKER_BUILDX_VERSION}" ]]; then
			if [ -f ~/.docker/cli-plugins/docker-buildx ]; then GLOBAL_UNU_DOCKER_BUILDX_VERSION="$(docker buildx version | sed 's/github\.com\/docker\/buildx //' | sed 's/ .*//')"; else GLOBAL_UNU_DOCKER_BUILDX_VERSION=0; fi
			# GLOBAL_UNU_DOCKER_BUILDX_LATEST="$(curl --silent https://api.github.com/repos/docker/buildx/releases/latest | jq .name -r)"
			GLOBAL_UNU_DOCKER_BUILDX_LATEST=${GLOBAL_STACK_DOCKER_BUILDX_VERSION}
			if [ "${GLOBAL_UNU_DOCKER_BUILDX_VERSION}" != "${GLOBAL_UNU_DOCKER_BUILDX_LATEST}" ]; then
				echo "Updating/Installing docker-buildx - ${OPERATING_SYSTEM}, arch : ${DOCKER_BUILDX_ARCH} https://github.com/docker/buildx/releases/download/${GLOBAL_UNU_DOCKER_BUILDX_LATEST}/buildx-${GLOBAL_UNU_DOCKER_BUILDX_LATEST}.${OPERATING_SYSTEM}-${DOCKER_BUILDX_ARCH}"
				curl -L https://github.com/docker/buildx/releases/download/${GLOBAL_UNU_DOCKER_BUILDX_LATEST}/buildx-${GLOBAL_UNU_DOCKER_BUILDX_LATEST}.${OPERATING_SYSTEM}-${DOCKER_BUILDX_ARCH} -o ~/.docker/cli-plugins/docker-buildx
				chmod a+rwx ~/.docker/cli-plugins/docker-buildx
			else
				echo "Docker buildx is latest '${GLOBAL_UNU_DOCKER_BUILDX_VERSION}'"
			fi

			if [ "${GLOBAL_STACK_DOCKER_IN_DOCKER_ACTIVATE_BUILDX}" = "true" ]; then
				echo "Activating docker buildx"
				docker buildx install
			else				
				echo "Deactivating docker buildx"
				docker buildx uninstall
			fi
		fi

		if [[ "" != "${HADOLINT_ARCH}" && -n "${GLOBAL_STACK_HADOLINT_VERSION}" && "" != "${GLOBAL_STACK_HADOLINT_VERSION}" ]]; then
			if [ -f ~/.local/bin/.hadolint.version ]; then GLOBAL_UNU_HADOLINT_VERSION="$(cat ~/.local/bin/.hadolint.version)"; else GLOBAL_UNU_HADOLINT_VERSION=0; fi
			# GLOBAL_UNU_HADOLINT_LATEST="$(curl --silent https://api.github.com/repos/hadolint/hadolint/releases/latest | jq .name -r)"
			GLOBAL_UNU_HADOLINT_LATEST=${GLOBAL_STACK_HADOLINT_VERSION}
			if [ "${GLOBAL_UNU_HADOLINT_VERSION}" != "${GLOBAL_UNU_HADOLINT_LATEST}" ]; then
				echo "Updating/Installing hadolint - ${OPERATING_SYSTEM}, arch : ${HADOLINT_ARCH} https://github.com/hadolint/hadolint/releases/download/${GLOBAL_UNU_HADOLINT_LATEST}/hadolint-${OPERATING_SYSTEM}-${HADOLINT_ARCH}"
				curl -L https://github.com/hadolint/hadolint/releases/download/${GLOBAL_UNU_HADOLINT_LATEST}/hadolint-${OPERATING_SYSTEM}-${HADOLINT_ARCH} -o ~/.local/bin/hadolint
				chmod a+rwx ~/.local/bin/hadolint
				echo "${GLOBAL_UNU_HADOLINT_LATEST}" >~/.local/bin/.hadolint.version
			else
				echo "Hadolint is latest '${GLOBAL_UNU_HADOLINT_LATEST}'"
			fi
		fi

		if [[ "" != "${SHELL_CHECK_ARCH}" && -n "${GLOBAL_STACK_SHELL_CHECK_VERSION}" && "" != "${GLOBAL_STACK_SHELL_CHECK_VERSION}" ]]; then
			if [ -f ~/.local/bin/shell-check ]; then GLOBAL_UNU_SHELL_CHECK_VERSION="$(shell-check --version | grep 'version: ' | sed 's/version: /v/')"; else GLOBAL_UNU_SHELL_CHECK_VERSION=0; fi
			# GLOBAL_UNU_SHELL_CHECK_LATEST=$(curl --silent https://api.github.com/repos/koalaman/shellcheck/releases/latest | jq .name -r | sed 's/Stable version /v/')
			GLOBAL_UNU_SHELL_CHECK_LATEST=${GLOBAL_STACK_SHELL_CHECK_VERSION}
			if [ "${GLOBAL_UNU_SHELL_CHECK_VERSION}" != "${GLOBAL_UNU_SHELL_CHECK_LATEST}" ]; then
				echo "Updating/Installing shell-check - ${OPERATING_SYSTEM}, arch : ${SHELL_CHECK_ARCH} https://github.com/koalaman/shellcheck/releases/download/${GLOBAL_UNU_SHELL_CHECK_LATEST}/shellcheck-${GLOBAL_UNU_SHELL_CHECK_LATEST}.${OPERATING_SYSTEM}.${SHELL_CHECK_ARCH}.tar.xz"
				curl -L https://github.com/koalaman/shellcheck/releases/download/${GLOBAL_UNU_SHELL_CHECK_LATEST}/shellcheck-${GLOBAL_UNU_SHELL_CHECK_LATEST}.${OPERATING_SYSTEM}.${SHELL_CHECK_ARCH}.tar.xz -o ~/.local/bin/shell-check-"${GLOBAL_UNU_SHELL_CHECK_LATEST}".tar.xz
				mkdir -p ~/.local/bin/shell-check-${GLOBAL_UNU_SHELL_CHECK_LATEST}
				tar -xf ~/.local/bin/shell-check-${GLOBAL_UNU_SHELL_CHECK_LATEST}.tar.xz -C ~/.local/bin/shell-check-${GLOBAL_UNU_SHELL_CHECK_LATEST}
				mv ~/.local/bin/shell-check-${GLOBAL_UNU_SHELL_CHECK_LATEST}/shellcheck-${GLOBAL_UNU_SHELL_CHECK_LATEST}/shellcheck ~/.local/bin/shell-check
				rm -rf ~/.local/bin/shell-check-${GLOBAL_UNU_SHELL_CHECK_LATEST}*
				chmod a+rwx ~/.local/bin/shell-check
			else
				echo "shell-check is latest '${GLOBAL_UNU_SHELL_CHECK_LATEST}'"
			fi
		fi

		if [[ "" != "${GITLEAKS_ARCH}" && -n "${GLOBAL_STACK_GITLEAKS_VERSION}" && "" != "${GLOBAL_STACK_GITLEAKS_VERSION}" ]]; then
			if [ -f ~/.local/bin/gitleaks ]; then GLOBAL_UNU_GITLEAKS_VERSION="$(gitleaks version)"; else GLOBAL_UNU_GITLEAKS_VERSION=0; fi
			GLOBAL_UNU_GITLEAKS_LATEST=$(echo "${GLOBAL_STACK_GITLEAKS_VERSION}" | sed 's/v//')
			if [ "${GLOBAL_UNU_GITLEAKS_LATEST}" != "${GLOBAL_UNU_GITLEAKS_VERSION}" ]; then
				echo "Updating/Installing gitleaks - ${OPERATING_SYSTEM}, arch : ${GITLEAKS_ARCH} https://github.com/gitleaks/gitleaks/releases/download/v${GLOBAL_UNU_GITLEAKS_LATEST}/gitleaks_${GLOBAL_UNU_GITLEAKS_LATEST}_${OPERATING_SYSTEM}_${GITLEAKS_ARCH}.tar.gz"
				curl -L https://github.com/gitleaks/gitleaks/releases/download/v${GLOBAL_UNU_GITLEAKS_LATEST}/gitleaks_${GLOBAL_UNU_GITLEAKS_LATEST}_${OPERATING_SYSTEM}_${GITLEAKS_ARCH}.tar.gz -o ~/.local/bin/gitleaks.tar.gz
				mkdir -p ~/.local/bin/gitleaks_archive
				tar -xf ~/.local/bin/gitleaks.tar.gz -C ~/.local/bin/gitleaks_archive
				mv ~/.local/bin/gitleaks_archive/gitleaks ~/.local/bin/gitleaks
				rm -rf ~/.local/bin/gitleaks_archive ~/.local/bin/gitleaks.tar.gz
				chmod a+rwx ~/.local/bin/gitleaks
			else
				echo "Gitleaks is latest 'v${GLOBAL_UNU_GITLEAKS_VERSION}'"
			fi
		fi

		if [[ "" != "${SHFMT_ARCH}" && -n "${GLOBAL_STACK_SHFMT_VERSION}" && "" != "${GLOBAL_STACK_SHFMT_VERSION}" ]]; then
			if [ -f ~/.local/bin/shfmt ]; then GLOBAL_UNU_SHFMT_VERSION="$(shfmt --version)"; else GLOBAL_UNU_SHFMT_VERSION=0; fi
			GLOBAL_UNU_SHFMT_LATEST=$(echo "${GLOBAL_STACK_SHFMT_VERSION}")
			if [ "${GLOBAL_UNU_SHFMT_LATEST}" != "${GLOBAL_UNU_SHFMT_VERSION}" ]; then
				echo "Updating/Installing shfmt - ${OPERATING_SYSTEM}, arch : ${GITLEAKS_ARCH} https://github.com/mvdan/sh/releases/download/${GLOBAL_UNU_SHFMT_LATEST}/shfmt_${GLOBAL_UNU_SHFMT_LATEST}_${OPERATING_SYSTEM}_${SHFMT_ARCH}"
				curl -L https://github.com/mvdan/sh/releases/download/${GLOBAL_UNU_SHFMT_LATEST}/shfmt_${GLOBAL_UNU_SHFMT_LATEST}_${OPERATING_SYSTEM}_${SHFMT_ARCH} -o ~/.local/bin/shfmt
				chmod a+rwx ~/.local/bin/shfmt
			else
				echo "Shfmt is latest '${GLOBAL_UNU_SHFMT_VERSION}'"
			fi
		fi

		if [[ "" != "${TASK_ARCH}" && -n "${GLOBAL_STACK_TASK_VERSION}" && "" != "${GLOBAL_STACK_TASK_VERSION}" ]]; then
			if [ -f "/opt/${USER}/task/task" ]; then GLOBAL_UNU_TASK_VERSION="$(task --version | sed 's/Task version: //' | sed 's/ \(.*\)//')"; else GLOBAL_UNU_TASK_VERSION=0; fi
			GLOBAL_UNU_TASK_LATEST="${GLOBAL_STACK_TASK_VERSION}"
			if [ "${GLOBAL_UNU_TASK_LATEST}" != "v${GLOBAL_UNU_TASK_VERSION}" ]; then
				echo "Updating/Installing task - ${OPERATING_SYSTEM}, arch : ${TASK_ARCH}"
				rm -rf /opt/${USER}/task
				TASK_ARCHIVE_NAME="task_${OPERATING_SYSTEM}_${TASK_ARCH}"
				echo "https://github.com/go-task/task/releases/download/${GLOBAL_UNU_TASK_LATEST}/${TASK_ARCHIVE_NAME}.tar.gz"
				curl -L https://github.com/go-task/task/releases/download/${GLOBAL_UNU_TASK_LATEST}/${TASK_ARCHIVE_NAME}.tar.gz -o "/opt/${USER}/${TASK_ARCHIVE_NAME}.tar.gz"
				cd "/opt/${USER}"
				mkdir -p "/opt/${USER}/${TASK_ARCHIVE_NAME}"
				tar -xf ${TASK_ARCHIVE_NAME}.tar.gz -C "/opt/${USER}/${TASK_ARCHIVE_NAME}"
				mv "${TASK_ARCHIVE_NAME}" task
				rm -rf ${TASK_ARCHIVE_NAME}.tar.gz
				sudo chmod a+x "/opt/${USER}/task/task"
			else
				echo "Task is latest ${GLOBAL_UNU_TASK_VERSION}"
			fi
		fi

		if [[ "" != "${YAMLFMT_ARCH}" && -n "${GLOBAL_STACK_YAMLFMT_VERSION}" && "" != "${GLOBAL_STACK_YAMLFMT_VERSION}" ]]; then
			if [ -f ~/.local/bin/yamlfmt ]; then GLOBAL_UNU_YAMLFMT_VERSION="$(yamlfmt -version | sed 's/yamlfmt //' | sed 's/ \(.*\)//')"; else GLOBAL_UNU_YAMLFMT_VERSION=0; fi
			if [ "${GLOBAL_STACK_YAMLFMT_VERSION}" != "v${GLOBAL_UNU_YAMLFMT_VERSION}" ]; then
				echo "Updating/Installing yamfmt - ${OPERATING_SYSTEM}, arch : ${YAMLFMT_ARCH}"
				YAMLFMT_ARCHIVE_NAME="yamlfmt_$(echo "${GLOBAL_STACK_YAMLFMT_VERSION}" | sed 's/v//')_${OPERATING_SYSTEM}_${YAMLFMT_ARCH}"
				echo "https://github.com/google/yamlfmt/releases/download/${GLOBAL_STACK_YAMLFMT_VERSION}/${YAMLFMT_ARCHIVE_NAME}.tar.gz"
				curl -L https://github.com/google/yamlfmt/releases/download/${GLOBAL_STACK_YAMLFMT_VERSION}/${YAMLFMT_ARCHIVE_NAME}.tar.gz -o ~/.local/bin/${YAMLFMT_ARCHIVE_NAME}.tar.gz
				mkdir -p ~/.local/bin/${YAMLFMT_ARCHIVE_NAME}
				tar -xf ~/.local/bin/${YAMLFMT_ARCHIVE_NAME}.tar.gz -C ~/.local/bin/${YAMLFMT_ARCHIVE_NAME}
				cp ~/.local/bin/${YAMLFMT_ARCHIVE_NAME}/yamlfmt ~/.local/bin/yamlfmt
				rm -rf ~/.local/bin/${YAMLFMT_ARCHIVE_NAME} ~/.local/bin/${YAMLFMT_ARCHIVE_NAME}.tar.gz
				chmod a+x ~/.local/bin/yamlfmt
			else
				echo "Yamfmt is latest ${GLOBAL_UNU_YAMLFMT_VERSION}"
			fi
		fi
	fi


	if [ -n "${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}" ] && [ "" != "${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}" ]; then
		if [ -f ~/.local/bin/.podman-compose.version ]; then GLOBAL_UNU_PODMAN_COMPOSE_VERSION="$(cat ~/.local/bin/.podman-compose.version)"; else GLOBAL_UNU_PODMAN_COMPOSE_VERSION=0; fi
		GLOBAL_UNU_PODMAN_COMPOSE_LATEST="$(curl --silent https://raw.githubusercontent.com/containers/podman-compose/${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}/podman_compose.py | grep -i -E -w "__version__ = " | sed 's/__version__ = //' | sed 's/"//g' | sed "s/'//g")"
		if [ "${GLOBAL_UNU_PODMAN_COMPOSE_VERSION}" != "${GLOBAL_UNU_PODMAN_COMPOSE_LATEST}" ]; then
			echo "Updating/Installing podman-compose https://raw.githubusercontent.com/containers/podman-compose/${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}/podman_compose.py"
			curl -L https://raw.githubusercontent.com/containers/podman-compose/${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}/podman_compose.py -o ~/.local/bin/podman-compose
			chmod a+rwx ~/.local/bin/podman-compose
			echo "${GLOBAL_UNU_PODMAN_COMPOSE_LATEST}" >~/.local/bin/.podman-compose.version
		else
			echo "Podman compose is latest '${GLOBAL_UNU_PODMAN_COMPOSE_LATEST}'"
		fi
	fi

	if [ "" != "${SONAR_SCANNER_CLI_ARCH}" ] && [ "" != "${SONAR_SCANNER_CLI_OPERATING_SYSTEM}" ] && [ -n "${GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION}" ] && [ "" != "${GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION}" ]; then
		if [ -f "/opt/${USER}/sonar-scanner-cli/bin/sonar-scanner" ]; then GLOBAL_UNU_SONAR_SCANNER_CLI_VERSION="$(sonar-scanner --version | grep 'SonarScanner.*' | sed 's/.*SonarScanner //' | sed 's/CLI //')"; else GLOBAL_UNU_SONAR_SCANNER_CLI_VERSION=0; fi
		GLOBAL_UNU_SONAR_SCANNER_CLI_LATEST="${GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION}"
		if [ "${GLOBAL_UNU_SONAR_SCANNER_CLI_LATEST}" != "${GLOBAL_UNU_SONAR_SCANNER_CLI_VERSION}" ]; then
			echo "Updating/Installing sonar-scanner-cli - ${SONAR_SCANNER_CLI_OPERATING_SYSTEM}, arch : ${SONAR_SCANNER_CLI_ARCH}"
			rm -rf /opt/${USER}/sonar-scanner-cli
			SONAR_SCANNER_CLI_ARCHIVE_NAME="sonar-scanner-cli-${GLOBAL_UNU_SONAR_SCANNER_CLI_LATEST}-${SONAR_SCANNER_CLI_OPERATING_SYSTEM}"
			if [ "$(echo "${GLOBAL_UNU_SONAR_SCANNER_CLI_LATEST}" | sed 's@^[^0-9]*\([0-9]\+\).*@\1@')" -ge "6" ]; then
				SONAR_SCANNER_CLI_ARCHIVE_NAME="${SONAR_SCANNER_CLI_ARCHIVE_NAME}-${SONAR_SCANNER_CLI_ARCH}"
			fi
			echo "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip"
			curl -L https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip -o "/opt/${USER}/${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip"
			cd "/opt/${USER}"
			unzip ${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip
			mv $(echo ${SONAR_SCANNER_CLI_ARCHIVE_NAME} | sed 's/sonar-scanner-cli-/sonar-scanner-/') sonar-scanner-cli
			rm -rf ${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip
			sudo chmod a+x "/opt/${USER}/sonar-scanner-cli/bin/sonar-scanner" "/opt/${USER}/sonar-scanner-cli/bin/sonar-scanner-debug"
		else
			echo "Sonar scanner cli is latest ${GLOBAL_UNU_SONAR_SCANNER_CLI_VERSION}"
		fi
	fi

	if [ "" != "${DIFFTASTIC_ARCH}" ] && [ "" != "${DIFFTASTIC_OPERATING_SYSTEM}" ] && [ -n "${GLOBAL_STACK_DIFFTASTIC_VERSION}" ] && [ "" != "${GLOBAL_STACK_DIFFTASTIC_VERSION}" ]; then
		if [ -f ~/.local/bin/difft ]; then GLOBAL_UNU_DIFFTASTIC_VERSION="$(difft --version | grep "Difftastic " | sed 's/Difftastic //' | sed 's/ \(.*\)//')"; else GLOBAL_UNU_DIFFTASTIC_VERSION=0; fi
		GLOBAL_UNU_DIFFTASTIC_LATEST=$(echo "${GLOBAL_STACK_DIFFTASTIC_VERSION}" | sed 's/v//')
		if [ "${GLOBAL_UNU_DIFFTASTIC_LATEST}" != "${GLOBAL_UNU_DIFFTASTIC_VERSION}" ]; then
			echo "Updating/Installing difftastic - ${DIFFTASTIC_OPERATING_SYSTEM}, arch : ${DIFFTASTIC_ARCH} https://github.com/Wilfred/difftastic/releases/download/${GLOBAL_UNU_DIFFTASTIC_LATEST}/difft-${DIFFTASTIC_ARCH}-${DIFFTASTIC_OPERATING_SYSTEM}.tar.gz"
			curl -L https://github.com/Wilfred/difftastic/releases/download/${GLOBAL_UNU_DIFFTASTIC_LATEST}/difft-${DIFFTASTIC_ARCH}-${DIFFTASTIC_OPERATING_SYSTEM}.tar.gz -o ~/.local/bin/difftastic.tar.gz
			mkdir -p ~/.local/bin/difftastic_archive
			tar -xf ~/.local/bin/difftastic.tar.gz -C ~/.local/bin/difftastic_archive
			mv ~/.local/bin/difftastic_archive/difft ~/.local/bin/difft
			rm -rf ~/.local/bin/difftastic_archive ~/.local/bin/difftastic.tar.gz
			chmod a+rwx ~/.local/bin/difft
		else
			echo "Difftastic is latest '${GLOBAL_UNU_DIFFTASTIC_VERSION}'"
		fi
	fi

	if [ "" != "${BAT_ARCH}" ] && [ "" != "${BAT_OPERATING_SYSTEM}" ] && [ -n "${GLOBAL_STACK_BAT_VERSION}" ] && [ "" != "${GLOBAL_STACK_BAT_VERSION}" ]; then
		if [ -f "/opt/${USER}/bat/bat" ]; then GLOBAL_UNU_BAT_VERSION="v$(bat --version | sed 's/bat //' | sed 's/ \(.*\)//')"; else GLOBAL_UNU_BAT_VERSION=0; fi
		GLOBAL_UNU_BAT_LATEST="${GLOBAL_STACK_BAT_VERSION}"
		if [ "${GLOBAL_UNU_BAT_LATEST}" != "${GLOBAL_UNU_BAT_VERSION}" ]; then
			echo "Updating/Installing bat - ${BAT_OPERATING_SYSTEM}, arch : ${BAT_ARCH}"
			rm -rf /opt/${USER}/bat
			BAT_ARCHIVE_NAME="bat-${GLOBAL_UNU_BAT_LATEST}-${BAT_ARCH}-${BAT_OPERATING_SYSTEM}"
			echo "https://github.com/sharkdp/bat/releases/download/${GLOBAL_UNU_BAT_LATEST}/${BAT_ARCHIVE_NAME}.tar.gz"
			curl -L https://github.com/sharkdp/bat/releases/download/${GLOBAL_UNU_BAT_LATEST}/${BAT_ARCHIVE_NAME}.tar.gz -o "/opt/${USER}/${BAT_ARCHIVE_NAME}.tar.gz"
			cd "/opt/${USER}"
			mkdir -p "/opt/${USER}/${BAT_ARCHIVE_NAME}"
			tar -xzf ${BAT_ARCHIVE_NAME}.tar.gz --strip-components=1 -C "/opt/${USER}/${BAT_ARCHIVE_NAME}"
			mv "${BAT_ARCHIVE_NAME}" bat
			rm -rf ${BAT_ARCHIVE_NAME}.tar.gz
			sudo chmod a+x "/opt/${USER}/bat/bat"
		else
			echo "Bat is latest ${GLOBAL_UNU_BAT_VERSION}"
		fi
	fi

	if [ "" != "${SOPS_OPERATING_SYSTEM}${SOPS_ARCH}" ] && [ -n "${GLOBAL_STACK_SOPS_VERSION}" ] && [ "" != "${GLOBAL_STACK_SOPS_VERSION}" ]; then
		if [ -f ~/.local/bin/sops ]; then GLOBAL_UNU_SOPS_VERSION="v$(sops --version | grep -E -o -m 1 "sops .*" | sed 's/sops //' | sed 's/ \(.*\)//')"; else GLOBAL_UNU_SOPS_VERSION=0; fi
		GLOBAL_UNU_SOPS_LATEST="${GLOBAL_STACK_SOPS_VERSION}"
		if [ "${GLOBAL_UNU_SOPS_LATEST}" != "${GLOBAL_UNU_SOPS_VERSION}" ]; then
			echo "Updating/Installing sops - ${SOPS_OPERATING_SYSTEM}, arch : ${SOPS_ARCH}"
			SOPS_FILE_NAME="sops-${GLOBAL_STACK_SOPS_VERSION}.${SOPS_OPERATING_SYSTEM}.${SOPS_ARCH}"
			echo "https://github.com/getsops/sops/releases/download/${GLOBAL_STACK_SOPS_VERSION}/${SOPS_FILE_NAME}"
			curl -L https://github.com/getsops/sops/releases/download/${GLOBAL_STACK_SOPS_VERSION}/${SOPS_FILE_NAME} -o ~/.local/bin/sops
			sudo chmod a+x ~/.local/bin/sops
		else
			echo "Sops is latest ${GLOBAL_UNU_SOPS_VERSION}"
		fi
	fi
fi


if [ -f ~/.local/bin/yq ]; then GLOBAL_UNU_YQ_VERSION="$(yq --version | sed "s/yq (https:\/\/github.com\/mikefarah\/yq\/) version //")"; else GLOBAL_UNU_YQ_VERSION=0; fi
if [ "${GLOBAL_UNU_YQ_VERSION}" != "${GLOBAL_STACK_YQ_VERSION}" ]; then
	echo "Updating/Installing yq"
	echo "https://github.com/mikefarah/yq/releases/download/${GLOBAL_STACK_YQ_VERSION}/yq_linux_amd64"
	curl -L https://github.com/mikefarah/yq/releases/download/${GLOBAL_STACK_YQ_VERSION}/yq_linux_amd64 -o ~/.local/bin/yq
	sudo chmod a+x ~/.local/bin/yq
else
	echo "Yq is latest ${GLOBAL_STACK_YQ_VERSION}"
fi

if [[ ! -f ~/.local/bin/docker-reclaim-disk-space-script.sh ]]; then
	echo "Downloading docker-reclaim-disk-space-script.sh"
	curl -L https://raw.githubusercontent.com/samoshkin/docker-reclaim-disk-space/master/script.sh -o ~/.local/bin/docker-reclaim-disk-space-script.sh
	chmod a+rwx ~/.local/bin/docker-reclaim-disk-space-script.sh
	echo "docker-reclaim-disk-space-script.sh installed"
else
	echo "docker-reclaim-disk-space-script.sh is installed (check for latest version manually)"
fi

# change python 3 path in podman compose
# sed -i "s|\/usr\/bin\/python3|${GLOBAL_STACK_PYENV_ROOT}/versions/${GLOBAL_STACK_PYTHON3_VERSION}/bin/python3|g" ~/.local/bin/podman-compose

echo -e "Successfull :)"
