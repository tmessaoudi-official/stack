#!/bin/bash

sudo mkdir -p "/opt/${GLOBAL_STACK_DOCKER_USER_ID}"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/"
sudo chmod -R a+rwx "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/"

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

HADOLINT_ARCH=""
SHELLCHECK_ARCH=""
GITLEAKS_ARCH=""
SONAR_SCANNER_CLI_ARCH=""
DIFFTASTIC_ARCH=""
SHFMT_ARCH=""
BAT_ARCH=""
TASK_ARCH=""
SOPS_ARCH=""
YAMLFMT_ARCH=""
RTK_ARCH=""
CLAUDE_CODE_ARCH=""
YQ_ARCH=""

if [[ "linux" == "${OPERATING_SYSTEM}" ]]; then
	DIFFTASTIC_OPERATING_SYSTEM="unknown-${OPERATING_SYSTEM}-gnu"
	# @todo add linux-musl
	BAT_OPERATING_SYSTEM="unknown-${OPERATING_SYSTEM}-gnu"
	SOPS_OPERATING_SYSTEM="${OPERATING_SYSTEM}"
	case "${SYSTEM_ARCH}" in
	"aarch64")
		HADOLINT_ARCH="arm64"
		SHELLCHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="arm64"
		SONAR_SCANNER_CLI_ARCH="${SYSTEM_ARCH}"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="arm64"
		RTK_ARCH="aarch64"
		CLAUDE_CODE_ARCH="arm64"
		YQ_ARCH="arm64"
		;;
	"armv6l")
		GITLEAKS_ARCH="armv6"
		SHFMT_ARCH="arm"
		YQ_ARCH="arm"
		echo "Unsupported system/architecture hadolint/shellcheck/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"armv6hf")
		SHELLCHECK_ARCH="${SYSTEM_ARCH}"
		echo "Unsupported system/architecture hadolint/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"armv6lhf")
		SHELLCHECK_ARCH="armv6hf"
		echo "Unsupported system/architecture hadolint/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"armv7l")
		GITLEAKS_ARCH="armv7"
		SHFMT_ARCH="arm"
		YQ_ARCH="arm"
		echo "Unsupported system/architecture hadolint/shellcheck/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"riscv64")
		SHELLCHECK_ARCH="${SYSTEM_ARCH}"
		echo "Unsupported system/architecture hadolint/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"x86_64")
		HADOLINT_ARCH="${SYSTEM_ARCH}"
		SHELLCHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="x64"
		SONAR_SCANNER_CLI_ARCH="x64"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="amd64"
		BAT_ARCH="${SYSTEM_ARCH}"
		TASK_ARCH="amd64"
		SOPS_ARCH="amd64"
		YAMLFMT_ARCH="${SYSTEM_ARCH}"
		RTK_ARCH="x86_64"
		CLAUDE_CODE_ARCH="x64"
		YQ_ARCH="amd64"
		;;
	"i386")
		GITLEAKS_ARCH="x32"
		SHFMT_ARCH="386"
		YQ_ARCH="386"
		echo "Unsupported system/architecture hadolint/shellcheck/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"i686")
		GITLEAKS_ARCH="x32"
		SHFMT_ARCH="386"
		YQ_ARCH="386"
		echo "Unsupported system/architecture hadolint/shellcheck/sonar-scanner-cli/difftastic: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	*)
		echo "Unsupported system/architecture hadolint/shellcheck/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
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
		SHELLCHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="arm64"
		SONAR_SCANNER_CLI_ARCH="${SYSTEM_ARCH}"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="arm64"
		RTK_ARCH="aarch64"
		CLAUDE_CODE_ARCH="arm64"
		YQ_ARCH="arm64"
		echo "Unsupported system/architecture hadolint: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	"x86_64")
		HADOLINT_ARCH="${SYSTEM_ARCH}"
		SHELLCHECK_ARCH="${SYSTEM_ARCH}"
		GITLEAKS_ARCH="x64"
		SONAR_SCANNER_CLI_ARCH="x64"
		DIFFTASTIC_ARCH="${SYSTEM_ARCH}"
		SHFMT_ARCH="amd64"
		SOPS_ARCH="amd64"
		YAMLFMT_ARCH="${SYSTEM_ARCH}"
		RTK_ARCH="x86_64"
		CLAUDE_CODE_ARCH="x64"
		YQ_ARCH="amd64"
		;;
	*)
		echo "Unsupported system/architecture hadolint/shellcheck/gitleaks/sonar-scanner-cli/difftastic/shfmt: ${OPERATING_SYSTEM}/${SYSTEM_ARCH}"
		;;
	esac
fi

if [[ "" != "${OPERATING_SYSTEM}" ]]; then
	if [[ "" != "${HADOLINT_ARCH}" ]]; then
		echo "Installing hadolint - system : ${OPERATING_SYSTEM}, arch : ${HADOLINT_ARCH}"
		# GLOBAL_STACK_HADOLINT_VERSION="$(curl --silent https://api.github.com/repos/hadolint/hadolint/releases/latest | jq .name -r)"
		sudo curl -L "https://github.com/hadolint/hadolint/releases/download/${GLOBAL_STACK_HADOLINT_VERSION}/hadolint-${OPERATING_SYSTEM}-${HADOLINT_ARCH}" -o /usr/local/bin/hadolint
		sudo chmod a+rwx /usr/local/bin/hadolint
	fi

	if [[ "" != "${SHELLCHECK_ARCH}" ]]; then
		echo "Installing shellcheck - system : ${OPERATING_SYSTEM}, arch : ${SHELLCHECK_ARCH}"
		# GLOBAL_STACK_SHELLCHECK_VERSION="$(curl --silent https://github.com/koalaman/shellcheck/releases/latest | jq .name -r)"
		sudo curl -L "https://github.com/koalaman/shellcheck/releases/download/${GLOBAL_STACK_SHELLCHECK_VERSION}/shellcheck-${GLOBAL_STACK_SHELLCHECK_VERSION}.${OPERATING_SYSTEM}.${SHELLCHECK_ARCH}.tar.xz" -o /usr/local/bin/shellcheck-"${GLOBAL_STACK_SHELLCHECK_VERSION}".tar.xz
		sudo mkdir -p /usr/local/bin/shellcheck-${GLOBAL_STACK_SHELLCHECK_VERSION}
		sudo tar -xf /usr/local/bin/shellcheck-${GLOBAL_STACK_SHELLCHECK_VERSION}.tar.xz -C /usr/local/bin/shellcheck-${GLOBAL_STACK_SHELLCHECK_VERSION}
		sudo mv /usr/local/bin/shellcheck-${GLOBAL_STACK_SHELLCHECK_VERSION}/shellcheck-${GLOBAL_STACK_SHELLCHECK_VERSION}/shellcheck /usr/local/bin/shellcheck
		sudo rm -rf /usr/local/bin/shellcheck-${GLOBAL_STACK_SHELLCHECK_VERSION}*
		sudo chmod a+rwx /usr/local/bin/shellcheck
	fi

	if [[ "" != "${GITLEAKS_ARCH}" ]]; then
		echo "Installing gitleaks - system : ${OPERATING_SYSTEM}, arch : ${GITLEAKS_ARCH}"
		GLOBAL_UNU_GITLEAKS_LATEST=$(echo "${GLOBAL_STACK_GITLEAKS_VERSION}" | sed 's/v//')
		sudo curl -L "https://github.com/gitleaks/gitleaks/releases/download/v${GLOBAL_UNU_GITLEAKS_LATEST}/gitleaks_${GLOBAL_UNU_GITLEAKS_LATEST}_${OPERATING_SYSTEM}_${GITLEAKS_ARCH}.tar.gz" -o /usr/local/bin/gitleaks.tar.gz
		sudo mkdir -p /usr/local/bin/gitleaks_archive
		sudo tar -xf /usr/local/bin/gitleaks.tar.gz -C /usr/local/bin/gitleaks_archive
		sudo mv /usr/local/bin/gitleaks_archive/gitleaks /usr/local/bin/gitleaks
		sudo rm -rf /usr/local/bin/gitleaks_archive /usr/local/bin/gitleaks.tar.gz
		sudo chmod a+rwx /usr/local/bin/gitleaks
	fi

	if [[ "" != "${SHFMT_ARCH}" ]]; then
		echo "Installing shfmt - system : ${OPERATING_SYSTEM}, arch : ${SHFMT_ARCH}"
		sudo curl -L "https://github.com/mvdan/sh/releases/download/${GLOBAL_STACK_SHFMT_VERSION}/shfmt_${GLOBAL_STACK_SHFMT_VERSION}_${OPERATING_SYSTEM}_${SHFMT_ARCH}" -o /usr/local/bin/shfmt
		sudo chmod a+rwx /usr/local/bin/shfmt
	fi

	if [[ "" != "${TASK_ARCH}" ]]; then
		echo "Installing task - ${OPERATING_SYSTEM}, arch : ${TASK_ARCH}"
		TASK_ARCHIVE_NAME="task_${OPERATING_SYSTEM}_${TASK_ARCH}"
		echo "https://github.com/go-task/task/releases/download/${GLOBAL_STACK_TASK_VERSION}/${TASK_ARCHIVE_NAME}.tar.gz"
		sudo curl -L "https://github.com/go-task/task/releases/download/${GLOBAL_STACK_TASK_VERSION}/${TASK_ARCHIVE_NAME}.tar.gz" -o "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/${TASK_ARCHIVE_NAME}.tar.gz"
		cd "/opt/${GLOBAL_STACK_DOCKER_USER_ID}"
		sudo mkdir -p cd "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/${TASK_ARCHIVE_NAME}"
		sudo tar -xf ${TASK_ARCHIVE_NAME}.tar.gz -C "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/${TASK_ARCHIVE_NAME}"
		sudo mv "${TASK_ARCHIVE_NAME}" task
		sudo rm -rf ${TASK_ARCHIVE_NAME}.tar.gz
		sudo chmod a+x "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/task/task"
	fi

	if [[ "" != "${YAMLFMT_ARCH}" ]]; then
		echo "Installing yamfmt - ${OPERATING_SYSTEM}, arch : ${YAMLFMT_ARCH}"
		YAMLFMT_ARCHIVE_NAME="yamlfmt_$(echo "${GLOBAL_STACK_YAMLFMT_VERSION}" | sed 's/v//')_${OPERATING_SYSTEM}_${YAMLFMT_ARCH}"
		echo "https://github.com/google/yamlfmt/releases/download/${GLOBAL_STACK_YAMLFMT_VERSION}/${YAMLFMT_ARCHIVE_NAME}.tar.gz"
		sudo curl -L "https://github.com/google/yamlfmt/releases/download/${GLOBAL_STACK_YAMLFMT_VERSION}/${YAMLFMT_ARCHIVE_NAME}.tar.gz" -o /usr/local/bin/${YAMLFMT_ARCHIVE_NAME}.tar.gz
		sudo mkdir -p /usr/local/bin/${YAMLFMT_ARCHIVE_NAME}
		sudo tar -xf /usr/local/bin/${YAMLFMT_ARCHIVE_NAME}.tar.gz -C /usr/local/bin/${YAMLFMT_ARCHIVE_NAME}
		sudo cp /usr/local/bin/${YAMLFMT_ARCHIVE_NAME}/yamlfmt /usr/local/bin/yamlfmt
		sudo rm -rf /usr/local/bin/${YAMLFMT_ARCHIVE_NAME} /usr/local/bin/${YAMLFMT_ARCHIVE_NAME}.tar.gz
		sudo chmod a+x /usr/local/bin/yamlfmt
	fi
fi

if [[ "" != "${DIFFTASTIC_OPERATING_SYSTEM}" && "" != "${DIFFTASTIC_ARCH}" ]]; then
	echo "Installing difftastic - system : ${DIFFTASTIC_OPERATING_SYSTEM}, arch : ${DIFFTASTIC_ARCH}"
	echo "https://github.com/Wilfred/difftastic/releases/download/${GLOBAL_STACK_DIFFTASTIC_VERSION}/difft-${DIFFTASTIC_ARCH}-${DIFFTASTIC_OPERATING_SYSTEM}.tar.gz"
	sudo curl -L "https://github.com/Wilfred/difftastic/releases/download/${GLOBAL_STACK_DIFFTASTIC_VERSION}/difft-${DIFFTASTIC_ARCH}-${DIFFTASTIC_OPERATING_SYSTEM}.tar.gz" -o /usr/local/bin/difftastic.tar.gz
	sudo mkdir -p /usr/local/bin/difftastic_archive
	sudo tar -xf /usr/local/bin/difftastic.tar.gz -C /usr/local/bin/difftastic_archive
	sudo mv /usr/local/bin/difftastic_archive/difft /usr/local/bin/difft
	sudo rm -rf /usr/local/bin/difftastic_archive /usr/local/bin/difftastic.tar.gz
	sudo chmod a+rwx /usr/local/bin/difft
fi

if [[ "" != "${SONAR_SCANNER_CLI_OPERATING_SYSTEM}" && "" != "${SONAR_SCANNER_CLI_ARCH}" ]]; then
	echo "Installing sonar-scanner-cli - system : ${SONAR_SCANNER_CLI_OPERATING_SYSTEM}, arch : ${SONAR_SCANNER_CLI_ARCH}"
	SONAR_SCANNER_CLI_ARCHIVE_NAME="sonar-scanner-cli-${GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION}-${SONAR_SCANNER_CLI_OPERATING_SYSTEM}"
    if [ "$(echo "${GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION}" | sed 's@^[^0-9]*\([0-9]\+\).*@\1@')" -ge "6" ]; then
        SONAR_SCANNER_CLI_ARCHIVE_NAME="${SONAR_SCANNER_CLI_ARCHIVE_NAME}-${SONAR_SCANNER_CLI_ARCH}"
    fi
    
    sudo curl -L "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip" -o "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip"
    cd "/opt/${GLOBAL_STACK_DOCKER_USER_ID}"
    sudo unzip ${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip
    sudo mv $(echo ${SONAR_SCANNER_CLI_ARCHIVE_NAME} | sed 's/sonar-scanner-cli-/sonar-scanner-/') sonar-scanner-cli
    sudo rm -rf ${SONAR_SCANNER_CLI_ARCHIVE_NAME}.zip
    sudo chmod a+x "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/sonar-scanner-cli/bin/sonar-scanner" "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/sonar-scanner-cli/bin/sonar-scanner-debug"
fi

if [[ "" != "${BAT_OPERATING_SYSTEM}" && "" != "${BAT_ARCH}" ]]; then
	echo "Installing bat - ${BAT_OPERATING_SYSTEM}, arch : ${BAT_ARCH}"
	BAT_ARCHIVE_NAME="bat-${GLOBAL_STACK_BAT_VERSION}-${BAT_ARCH}-${BAT_OPERATING_SYSTEM}"
	echo "https://github.com/sharkdp/bat/releases/download/${GLOBAL_STACK_BAT_VERSION}/${BAT_ARCHIVE_NAME}.tar.gz"
	sudo curl -L "https://github.com/sharkdp/bat/releases/download/${GLOBAL_STACK_BAT_VERSION}/${BAT_ARCHIVE_NAME}.tar.gz" -o "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/${BAT_ARCHIVE_NAME}.tar.gz"
	cd "/opt/${GLOBAL_STACK_DOCKER_USER_ID}"
	sudo mkdir -p "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/${BAT_ARCHIVE_NAME}"
	sudo tar -xzf ${BAT_ARCHIVE_NAME}.tar.gz --strip-components=1 -C "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/${BAT_ARCHIVE_NAME}"
	sudo mv "${BAT_ARCHIVE_NAME}" bat
	sudo rm -rf ${BAT_ARCHIVE_NAME}.tar.gz
	sudo chmod a+x "/opt/${GLOBAL_STACK_DOCKER_USER_ID}/bat/bat"
fi

if [[ "" != "${SOPS_OPERATING_SYSTEM}${SOPS_ARCH}" ]]; then
	echo "Installing sops - ${SOPS_OPERATING_SYSTEM}, arch : ${SOPS_ARCH}"
	SOPS_FILE_NAME="sops-${GLOBAL_STACK_SOPS_VERSION}.${SOPS_OPERATING_SYSTEM}.${SOPS_ARCH}"
	echo "https://github.com/getsops/sops/releases/download/${GLOBAL_STACK_SOPS_VERSION}/${SOPS_FILE_NAME}"
	sudo curl -L "https://github.com/getsops/sops/releases/download/${GLOBAL_STACK_SOPS_VERSION}/${SOPS_FILE_NAME}" -o "/usr/local/bin/sops"
	sudo chmod a+x "/usr/local/bin/sops"
fi

if [[ "" != "${RTK_ARCH}" ]]; then
	echo "Installing rtk - system : ${OPERATING_SYSTEM}, arch : ${RTK_ARCH}"
	RTK_OS_TARGET=""
	if [[ "linux" == "${OPERATING_SYSTEM}" ]]; then
		if [[ "x86_64" == "${RTK_ARCH}" ]]; then
			RTK_OS_TARGET="${RTK_ARCH}-unknown-linux-musl"
		else
			RTK_OS_TARGET="${RTK_ARCH}-unknown-linux-gnu"
		fi
	elif [[ "darwin" == "${OPERATING_SYSTEM}" ]]; then
		RTK_OS_TARGET="${RTK_ARCH}-apple-darwin"
	fi
	sudo curl -L "https://github.com/rtk-ai/rtk/releases/download/${GLOBAL_STACK_RTK_VERSION}/rtk-${RTK_OS_TARGET}.tar.gz" -o /usr/local/bin/rtk.tar.gz
	sudo mkdir -p /usr/local/bin/rtk_archive
	sudo tar -xzf /usr/local/bin/rtk.tar.gz -C /usr/local/bin/rtk_archive
	sudo mv /usr/local/bin/rtk_archive/rtk /usr/local/bin/rtk
	sudo rm -rf /usr/local/bin/rtk_archive /usr/local/bin/rtk.tar.gz
	sudo chmod a+x /usr/local/bin/rtk
fi

if [[ "" != "${CLAUDE_CODE_ARCH}" && "" != "${OPERATING_SYSTEM}" && "" != "${GLOBAL_STACK_CLAUDE_CODE_VERSION}" ]]; then
	echo "Installing claude - system : ${OPERATING_SYSTEM}, arch : ${CLAUDE_CODE_ARCH}"
	sudo curl -L "https://downloads.claude.ai/claude-code-releases/${GLOBAL_STACK_CLAUDE_CODE_VERSION}/${OPERATING_SYSTEM}-${CLAUDE_CODE_ARCH}/claude" -o /usr/local/bin/claude
	sudo chmod a+x /usr/local/bin/claude
fi

if [[ "true" == "${GLOBAL_STACK_RTK_INIT}" ]] \
  && command -v rtk >/dev/null 2>&1 \
  && command -v claude >/dev/null 2>&1; then
	echo "Initializing rtk for Claude Code"
	sudo mkdir -p "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.claude"
	sudo chown "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.claude"
	rtk telemetry disable
	rtk init --agent claude --global --auto-patch
fi

if [[ "" != "${YQ_ARCH}" && "" != "${OPERATING_SYSTEM}" ]]; then
	echo "Installing yq - system : ${OPERATING_SYSTEM}, arch : ${YQ_ARCH}"
	echo "https://github.com/mikefarah/yq/releases/download/${GLOBAL_STACK_YQ_VERSION}/yq_${OPERATING_SYSTEM}_${YQ_ARCH}"
	sudo curl -L "https://github.com/mikefarah/yq/releases/download/${GLOBAL_STACK_YQ_VERSION}/yq_${OPERATING_SYSTEM}_${YQ_ARCH}" -o /usr/local/bin/yq
	sudo chmod a+x /usr/local/bin/yq
fi