#!/bin/bash

# Function to check Docker Hub image version
check_docker_hub_version() {
    local image=$1
    local current_version=$2
    local env_var=$3
    local token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${image}:pull" | jq -r .token)
    local latest_version=$(curl -s -H "Authorization: Bearer ${token}" "https://registry.hub.docker.com/v2/${image}/tags/list" | jq -r '.tags[]' | sort -V | tail -n 1)
    
    if [ "$current_version" != "$latest_version" ]; then
        echo "UPDATE AVAILABLE: ${image} - Current: ${current_version}, Latest: ${latest_version}"
        if [ "$UPDATE_ENV" = "true" ]; then
            update_env_version "$env_var" "$current_version" "$latest_version"
        fi
    fi
}

# Function to check GitHub repository version
check_github_version() {
    local repo=$1
    local current_version=$2
    local env_var=$3
    local latest_version=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r .tag_name)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        # Try tags if releases are not available
        latest_version=$(curl -s "https://api.github.com/repos/${repo}/tags" | jq -r '.[0].name')
    fi
    
    if [ "$current_version" != "$latest_version" ] && [ -n "$latest_version" ] && [ "$latest_version" != "null" ]; then
        echo "UPDATE AVAILABLE: ${repo} - Current: ${current_version}, Latest: ${latest_version}"
        if [ "$UPDATE_ENV" = "true" ]; then
            update_env_version "$env_var" "$current_version" "$latest_version"
        fi
    fi
}

# Function to update version in .env file
update_env_version() {
    local env_var=$1
    local current_version=$2
    local latest_version=$3
    
    # Update version in .env file
    sed -i "s|${env_var}=${current_version}|${env_var}=${latest_version}|g" "${STACK_ROOT}/.env"
    echo "Updated ${env_var} from ${current_version} to ${latest_version}"
}

# Function to extract versions from .env file
extract_versions() {
    local env_file=$1
    declare -A docker_images
    declare -A github_repos
    
    # Read the .env file line by line
    while IFS= read -r line; do
        if [[ $line =~ ^#.*check-updates ]]; then
            if [[ $line =~ hub\.docker\.com[^[:space:]]*/([^[:space:]]+/[^[:space:]]+|_/[^[:space:]]+)[[:space:]]+([^[:space:]]+)$ ]]; then
                # Docker Hub image
                local image="${BASH_REMATCH[1]}"
                local version="${BASH_REMATCH[2]}"
                # Remove '_/' prefix if present
                image=${image/_\//}
                
                # Find the corresponding environment variable
                local env_var=$(grep -B1 "check-updates.*${image}" "${env_file}" | grep "GLOBAL_STACK" | cut -d'=' -f1)
                if [ -n "$env_var" ]; then
                    docker_images[$image]="${version}|${env_var}"
                fi
            elif [[ $line =~ github\.com/([^/]+/[^/]+)/(releases|tags)[[:space:]]+([^[:space:]]+) ]]; then
                # GitHub repository
                local repo="${BASH_REMATCH[1]}"
                local version="${BASH_REMATCH[3]}"
                
                # Find the corresponding environment variable
                local env_var=$(grep -B1 "check-updates.*${repo}" "${env_file}" | grep "GLOBAL_STACK" | cut -d'=' -f1)
                if [ -n "$env_var" ]; then
                    github_repos[$repo]="${version}|${env_var}"
                fi
            fi
        fi
    done < "$env_file"
    
    echo "Checking Docker image versions..."
    for image in "${!docker_images[@]}"; do
        IFS='|' read -r version env_var <<< "${docker_images[$image]}"
        check_docker_hub_version "$image" "$version" "$env_var"
    done
    
    echo -e "\nChecking GitHub repository versions..."
    for repo in "${!github_repos[@]}"; do
        IFS='|' read -r version env_var <<< "${github_repos[$repo]}"
        check_github_version "$repo" "$version" "$env_var"
    done
}

# Parse command line arguments
STACK_ROOT=${1:-$(dirname "$(dirname "$(readlink -f "$0")")")}
UPDATE_ENV=${2:-false}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    exit 1
fi

# Extract and check versions
extract_versions "${STACK_ROOT}/.env"

echo "Version check completed"
