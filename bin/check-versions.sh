#!/bin/bash

# Set to 'true' to automatically update .env file with new versions
UPDATE_ENV=${UPDATE_ENV:-false}
STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${STACK_ROOT}/.env"
TMP_FILE="${STACK_ROOT}/.env.tmp"

# Check if required commands are available
for cmd in curl jq git; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done

echo "🔍 Checking for updates..."

# Function to check Docker Hub image version
check_docker_hub_version() {
    local image=$1
    local current_version=$2
    local env_var=$3
    
    echo -n "Checking Docker Hub: ${image}:${current_version}... "
    
    # Get auth token
    local token
    token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${image}:pull" | jq -r '.token' 2>/dev/null)
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "Failed to get auth token"
        return 1
    fi
    
    # Get tags
    local tags_url="https://registry.hub.docker.com/v2/${image}/tags/list"
    local tags_response
    tags_response=$(curl -s -H "Authorization: Bearer ${token}" "$tags_url" 2>/dev/null)
    
    # Extract and sort versions (handle both v1 and v2 API formats)
    local latest_version
    if echo "$tags_response" | jq -e '.tags' &>/dev/null; then
        # v2 API format
        latest_version=$(echo "$tags_response" | jq -r '.tags[]' | sort -V | grep -vE 'latest|alpha|beta|rc' | tail -n1 2>/dev/null)
    else
        # v1 API format (fallback)
        latest_version=$(curl -s "https://hub.docker.com/v1/repositories/${image}/tags" | 
                        jq -r '.[].name' | sort -V | grep -vE 'latest|alpha|beta|rc' | tail -n1 2>/dev/null)
    fi
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo "Failed to get latest version"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo "UPDATE AVAILABLE: ${latest_version}"
        if [ "$UPDATE_ENV" = "true" ] && [ -n "$env_var" ]; then
            update_env_version "$env_var" "$current_version" "$latest_version"
        fi
    else
        echo "up to date"
    fi
}

# Function to check GitHub repository version
check_github_version() {
    local repo=$1
    local current_version=$2
    local env_var=$3
    
    echo -n "Checking GitHub: ${repo} ${current_version}... "
    
    # First try releases/latest
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // .name // ""' 2>/dev/null)
    
    # If no release found, try tags
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        latest_version=$(curl -s "https://api.github.com/repos/${repo}/tags" | jq -r '.[0].name // ""' 2>/dev/null)
    fi
    
    # Clean up version string (remove 'v' prefix if present)
    latest_version=${latest_version#v}
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo "Failed to get latest version"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo "UPDATE AVAILABLE: ${latest_version}"
        if [ "$UPDATE_ENV" = "true" ] && [ -n "$env_var" ]; then
            update_env_version "$env_var" "$current_version" "$latest_version"
        fi
    else
        echo "up to date"
    fi
}

# Function to check NPM package version
check_npm_version() {
    local package=$1
    local current_version=$2
    local env_var=$3
    
    echo -n "Checking NPM: ${package}@${current_version}... "
    
    local latest_version
    latest_version=$(curl -s "https://registry.npmjs.org/${package}/latest" | jq -r '.version' 2>/dev/null)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo "Failed to get latest version"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo "UPDATE AVAILABLE: ${latest_version}"
        if [ "$UPDATE_ENV" = "true" ] && [ -n "$env_var" ]; then
            update_env_version "$env_var" "$current_version" "$latest_version"
        fi
    else
        echo "up to date"
    fi
}

# Function to check PyPI package version
check_pypi_version() {
    local package=$1
    local current_version=$2
    local env_var=$3
    
    echo -n "Checking PyPI: ${package}==${current_version}... "
    
    local latest_version
    latest_version=$(curl -s "https://pypi.org/pypi/${package}/json" | jq -r '.info.version' 2>/dev/null)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo "Failed to get latest version"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        echo "UPDATE AVAILABLE: ${latest_version}"
        if [ "$UPDATE_ENV" = "true" ] && [ -n "$env_var" ]; then
            update_env_version "$env_var" "$current_version" "$latest_version"
        fi
    else
        echo "up to date"
    fi
}

# Function to update version in .env file
update_env_version() {
    local env_var=$1
    local current_version=$2
    local latest_version=$3
    
    # Escape special characters for sed
    current_version_escaped=$(printf '%s\n' "$current_version" | sed -e 's/[\/&]/\\&/g')
    latest_version_escaped=$(printf '%s\n' "$latest_version" | sed -e 's/[\/&]/\\&/g')
    
    # Update version in .env file
    if [ -f "$ENV_FILE" ]; then
        # Create a backup
        cp "$ENV_FILE" "${ENV_FILE}.bak"
        
        # Update the version
        sed -i.bak -E "s/(${env_var}=['\"])?${current_version_escaped}(['\"])?/\1${latest_version_escaped}\2/g" "$ENV_FILE"
        
        # Check if the update was successful
        if grep -q "${env_var}=.*${latest_version_escaped}" "$ENV_FILE"; then
            echo "✅ Updated ${env_var} from ${current_version} to ${latest_version}"
        else
            echo "⚠️  Failed to update ${env_var} in .env"
            # Restore backup on failure
            mv "${ENV_FILE}.bak" "$ENV_FILE"
        fi
    else
        echo "Error: .env file not found at ${ENV_FILE}" >&2
        return 1
    fi
}

# Function to parse .env file and check for updates
check_all_versions() {
    echo "🔍 Parsing ${ENV_FILE} for versions to check..."
    
    # Process each line in the .env file
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Extract variable name and value
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            
            # Remove surrounding quotes if present
            var_value=${var_value%\"}
            var_value=${var_value#\"}
            var_value=${var_value%\'}
            var_value=${var_value#\'}
            
            # Check for Docker images
            if [[ "$var_name" =~ ^GLOBAL_STACK_IMAGE_([A-Z0-9_]+)_VERSION$ ]]; then
                local image_name=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | tr '_' '/')
                check_docker_hub_version "$image_name" "$var_value" "$var_name"
            # Check for GitHub repositories
            elif [[ "$line" =~ @todo[[:space:]]+check-updates[[:space:]]+https://github.com/([^/]+/[^/\s]+) ]]; then
                local repo="${BASH_REMATCH[1]}"
                # Extract version from the next line if it's a version variable
                if [[ "$line" =~ GLOBAL_STACK_[A-Z0-9_]+_VERSION ]]; then
                    check_github_version "$repo" "$var_value" "$var_name"
                fi
            # Check for NPM packages
            elif [[ "$line" =~ @todo[[:space:]]+check-updates[[:space:]]+https://www.npmjs.com/package/([^/\s]+) ]]; then
                local package="${BASH_REMATCH[1]}"
                if [[ "$line" =~ GLOBAL_STACK_[A-Z0-9_]+_VERSION ]]; then
                    check_npm_version "$package" "$var_value" "$var_name"
                fi
            # Check for PyPI packages
            elif [[ "$line" =~ @todo[[:space:]]+check-updates[[:space:]]+https://pypi.org/project/([^/\s]+) ]]; then
                local package="${BASH_REMATCH[1]}"
                if [[ "$line" =~ GLOBAL_STACK_[A-Z0-9_]+_VERSION ]]; then
                    check_pypi_version "$package" "$var_value" "$var_name"
                fi
            fi
        fi
    done < "$ENV_FILE"
}

# Main execution
main() {
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        echo "Error: .env file not found at ${ENV_FILE}" >&2
        exit 1
    fi
    
    # Check for command line arguments
    if [ "$1" = "--update" ]; then
        UPDATE_ENV=true
        echo "⚠️  WARNING: Will update .env file with new versions"
    fi
    
    check_all_versions
    
    echo "✅ Version check complete!"
    
    if [ "$UPDATE_ENV" = "true" ]; then
        echo "\n💡 To apply the changes, you may need to rebuild your containers with 'make down-n-rebuild-force-recreate'"
    fi
}

# Run the main function with all arguments
main "$@"

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
