#!/bin/bash

# Version Manager for Development Stack
# This script provides a structured way to manage versions of all dependencies

# Load environment variables if not already loaded
if [ -z "${STACK_ROOT}" ]; then
    export STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${STACK_ROOT}/bin/load-env.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =====================
# VERSION DEFINITIONS
# =====================

# This function defines all versions in a structured way
define_versions() {
    # Docker Images
    declare -gA DOCKER_IMAGES=(
        [MYSQL]="8.0.26"
        [POSTGRES]="13.4"
        [REDIS]="6.2.5"
        [NODE]="16.14.0"
        [PYTHON]="3.9.7"
    )

    # System Packages
    declare -gA SYSTEM_PACKAGES=(
        [NODE]="16.14.0"
        [PYTHON]="3.9.7"
        [RUBY]="3.0.2"
    )

    # NPM Packages (format: package@version)
    declare -ga NPM_PACKAGES=(
        "@angular/cli@12.2.0"
        "typescript@4.3.5"
        "eslint@7.32.0"
    )

    # Python Packages (format: package==version)
    declare -ga PYTHON_PACKAGES=(
        "django==3.2.9"
        "flask==2.0.1"
        "requests==2.26.0"
    )

    # GitHub Repositories (format: owner/repo@version)
    declare -ga GITHUB_REPOS=(
        "docker/compose@v2.3.3"
        "moby/moby@v20.10.7"
    )
}

# =====================
# VERSION METADATA
# =====================
# This function defines metadata for version checking
define_version_metadata() {
    # Format: CHECK_FUNCTION|NAME|CURRENT_VERSION|SOURCE_URL
    declare -ga VERSION_METADATA=(
        # Docker Images
        "check_docker_version|mysql|${DOCKER_IMAGES[MYSQL]}|library/mysql"
        "check_docker_version|postgres|${DOCKER_IMAGES[POSTGRES]}|library/postgres"
        
        # System Packages
        "check_github_version|node|${SYSTEM_PACKAGES[NODE]}|nodejs/node"
        "check_pypi_version|python|${SYSTEM_PACKAGES[PYTHON]}|python"
    )

    # Add NPM packages
    for pkg in "${NPM_PACKAGES[@]}"; do
        IFS='@' read -r name version <<< "$pkg"
        VERSION_METADATA+=("check_npm_version|${name}|${version}|${name}")
    done

    # Add Python packages
    for pkg in "${PYTHON_PACKAGES[@]}"; do
        IFS='==' read -r name version <<< "$pkg"
        VERSION_METADATA+=("check_pypi_version|${name}|${version}|${name}")
    done

    # Add GitHub repositories
    for repo in "${GITHUB_REPOS[@]}"; do
        IFS='@' read -r name version <<< "$repo"
        VERSION_METADATA+=("check_github_version|${name}|${version}|${name}")
    done
}

# =====================
# VERSION CHECKING FUNCTIONS
# =====================

check_docker_version() {
    local name=$1
    local current_version=$2
    local source=$3
    
    echo -n "Checking Docker: ${name}:${current_version}... "
    
    local token
    token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${source}:pull" | jq -r '.token' 2>/dev/null)
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo -e "${YELLOW}Failed to get auth token${NC}"
        return 1
    fi
    
    local latest_version
    latest_version=$(curl -s -H "Authorization: Bearer ${token}" \
        "https://registry.hub.docker.com/v2/${source}/tags/list" 2>/dev/null | \
        jq -r '.tags[]' | grep -vE 'latest|alpha|beta|rc' | sort -V | tail -n1)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo -e "${YELLOW}Failed to get latest version${NC}"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo -e "${GREEN}UPDATE AVAILABLE: ${latest_version}${NC}"
        return 0
    else
        echo -e "${BLUE}up to date${NC}"
        return 1
    fi
}

check_github_version() {
    local name=$1
    local current_version=$2
    local repo=$3
    
    echo -n "Checking GitHub: ${repo} ${current_version}... "
    
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | \
        jq -r '.tag_name // .name // ""' | sed 's/^v//')
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        latest_version=$(curl -s "https://api.github.com/repos/${repo}/tags" 2>/dev/null | \
            jq -r '.[0].name // ""' | sed 's/^v//')
    fi
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo -e "${YELLOW}Failed to get latest version${NC}"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo -e "${GREEN}UPDATE AVAILABLE: ${latest_version}${NC}"
        return 0
    else
        echo -e "${BLUE}up to date${NC}"
        return 1
    fi
}

check_npm_version() {
    local name=$1
    local current_version=$2
    local package=$3
    
    echo -n "Checking NPM: ${package}@${current_version}... "
    
    local latest_version
    latest_version=$(curl -s "https://registry.npmjs.org/${package}/latest" 2>/dev/null | \
        jq -r '.version // ""')
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo -e "${YELLOW}Failed to get latest version${NC}"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo -e "${GREEN}UPDATE AVAILABLE: ${latest_version}${NC}"
        return 0
    else
        echo -e "${BLUE}up to date${NC}"
        return 1
    fi
}

check_pypi_version() {
    local name=$1
    local current_version=$2
    local package=$3
    
    echo -n "Checking PyPI: ${package}==${current_version}... "
    
    local latest_version
    latest_version=$(curl -s "https://pypi.org/pypi/${package}/json" 2>/dev/null | \
        jq -r '.info.version // ""')
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo -e "${YELLOW}Failed to get latest version${NC}"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo -e "${GREEN}UPDATE AVAILABLE: ${latest_version}${NC}"
        return 0
    else
        echo -e "${BLUE}up to date${NC}"
        return 1
    fi
}

# =====================
# MAIN FUNCTIONS
# =====================

check_all_versions() {
    echo -e "${BLUE}🔍 Checking for updates...${NC}"
    
    local updates_available=0
    
    # Define all versions and metadata
    define_versions
    define_version_metadata
    
    # Check each item in the metadata
    for item in "${VERSION_METADATA[@]}"; do
        IFS='|' read -r check_func name version source <<< "$item"
        
        # Call the appropriate check function
        if "$check_func" "$name" "$version" "$source"; then
            updates_available=$((updates_available + 1))
        fi
    done
    
    echo -e "\n${GREEN}✅ Check complete. ${updates_available} updates available.${NC}"
    return $updates_available
}

update_versions() {
    echo -e "${YELLOW}⚠️  Updating versions is not yet implemented${NC}"
    echo "This function would update the version definitions in this script"
    return 1
}

# =====================
# COMMAND LINE INTERFACE
# =====================

print_help() {
    echo "Version Manager for Development Stack"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  check      Check for available updates (default)"
    echo "  update     Update versions (not yet implemented)"
    echo "  help       Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  DRY_RUN    Set to '1' to prevent making changes (default: 1)"
}

main() {
    local command=${1:-check}
    
    case "$command" in
        check)
            check_all_versions
            ;;
        update)
            update_versions
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
            print_help
            return 1
            ;;
    esac
}

# Run the main function if the script is executed directly
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main "$@"
fi
