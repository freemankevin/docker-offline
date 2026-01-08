#!/bin/bash

# Color and style settings
COLOR_YELLOW="\033[1;33m"
COLOR_GREEN="\033[1;32m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"
STYLE_BOLD="\033[1m"

# Unicode icons
ICON_INFO="🛈"
ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_CLOCK="⏰"

# Function to print timestamped message
print_timestamped() {
    local message="$1"
    local color="$2"
    local icon="$3"
    echo -e "${color}${icon} $(date '+%Y-%m-%d %H:%M:%S') - ${message}${COLOR_RESET}"
}

# Determine Base Directory
# Try to find where the binary files and services directory are located relative to this script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if ls "${SCRIPT_DIR}/../docker-"*.tgz 1> /dev/null 2>&1; then
    # Script is in scripts/ subdir, binaries are in parent dir
    BASE_DIR="$(readlink -f "${SCRIPT_DIR}/..")"
elif ls "${SCRIPT_DIR}/packages/docker-"*.tgz 1> /dev/null 2>&1; then
    # Script is in root, binaries are in packages/ subdir
    BASE_DIR="$(readlink -f "${SCRIPT_DIR}/packages")"
elif ls "${SCRIPT_DIR}/docker-"*.tgz 1> /dev/null 2>&1; then
    # Script is in the same dir as binaries
    BASE_DIR="${SCRIPT_DIR}"
else
    # Fallback to current working directory
    BASE_DIR="$(pwd)"
fi

# Detect Architecture
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            print_timestamped "Unsupported architecture: $arch" "${COLOR_RED}" "${ICON_WARNING}"
            exit 1
            ;;
    esac
}

ARCH=$(detect_arch)

# Function to extract version from filename
extract_version() {
    local filename="$1"
    if [[ $filename =~ docker-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0.0.0"
    fi
}

# Function to find latest version file
find_latest_version() {
    local pattern="$1"
    local latest_file=""
    local latest_version="0.0.0"

    # Use find or glob to match files in BASE_DIR
    # We use ls to handle wildcard expansion safely
    for file in $pattern; do
        if [[ -f "$file" ]]; then
            local version=$(extract_version "$(basename "$file")")
            if [[ $(printf '%s\n' "$version" "$latest_version" | sort -V | tail -n1) == "$version" ]]; then
                latest_version="$version"
                latest_file="$file"
            fi
        fi
    done

    echo "$latest_file"
}

# Function to detect Kylin Linux system
detect_kylin_system() {
    if [[ -f "/etc/.productinfo" ]]; then
        if grep -q "Kylin Linux Advanced Server" /etc/.productinfo; then
            local version=$(grep -oP 'release V\K[0-9]+' /etc/.productinfo | head -1)
            print_timestamped "Detected Kylin Linux Advanced Server (Version: $version)" "${COLOR_YELLOW}" "${ICON_INFO}"
            return 0
        fi
    fi
    return 1
}

# Function to check and remove podman
check_and_remove_podman() {
    print_timestamped "Checking for podman installation on Kylin system..." "${COLOR_YELLOW}" "${ICON_INFO}"
    
    # Check if podman is installed
    if command -v podman &> /dev/null; then
        print_timestamped "Podman is installed. Starting cleanup process..." "${COLOR_YELLOW}" "${ICON_WARNING}"
        
        # Stop all podman containers
        print_timestamped "Stopping all podman containers..." "${COLOR_YELLOW}" "${ICON_INFO}"
        local running_containers=$(podman ps -q 2>/dev/null)
        if [[ -n "$running_containers" ]]; then
            podman stop --all >/dev/null 2>&1
            print_timestamped "Podman containers stopped." "${COLOR_GREEN}" "${ICON_SUCCESS}"
        else
            print_timestamped "No running podman containers found." "${COLOR_GREEN}" "${ICON_SUCCESS}"
        fi
        
        # Remove all podman containers
        print_timestamped "Removing all podman containers..." "${COLOR_YELLOW}" "${ICON_INFO}"
        podman rm --all >/dev/null 2>&1
        print_timestamped "Podman containers removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
        
        # Remove all podman images
        print_timestamped "Removing all podman images..." "${COLOR_YELLOW}" "${ICON_INFO}"
        podman rmi --all >/dev/null 2>&1
        print_timestamped "Podman images removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
        
        # Uninstall podman packages
        print_timestamped "Uninstalling podman packages..." "${COLOR_YELLOW}" "${ICON_INFO}"
        if command -v yum &> /dev/null; then
            yum remove -y podman podman-cni-config >/dev/null 2>&1
        elif command -v apt-get &> /dev/null; then
            apt-get remove -y podman >/dev/null 2>&1
        fi
        print_timestamped "Podman packages uninstalled successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"
        
        # Clean up podman data directories
        print_timestamped "Cleaning up podman data directories..." "${COLOR_YELLOW}" "${ICON_INFO}"
        rm -rf /var/lib/podman >/dev/null 2>&1
        rm -rf /var/lib/containers >/dev/null 2>&1
        rm -rf ~/.local/share/podman >/dev/null 2>&1
        print_timestamped "Podman data directories cleaned." "${COLOR_GREEN}" "${ICON_SUCCESS}"
        
        print_timestamped "Podman cleanup completed successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"
    else
        print_timestamped "Podman is not installed. Skipping cleanup." "${COLOR_GREEN}" "${ICON_SUCCESS}"
    fi
}

# Function to install Docker binaries
install_docker_binaries() {
    print_timestamped "Searching for latest Docker binary package for ${ARCH}..." "${COLOR_YELLOW}" "${ICON_INFO}"
    local docker_file=$(find_latest_version "${BASE_DIR}/docker-*-${ARCH}.tgz")
    if [[ -z "$docker_file" ]]; then
        print_timestamped "No Docker binary package found for ${ARCH} in ${BASE_DIR}. Please provide a docker-*-${ARCH}.tgz file." "${COLOR_RED}" "${ICON_WARNING}"
        exit 1
    fi
    print_timestamped "Installing Docker binaries from $docker_file..." "${COLOR_YELLOW}" "${ICON_INFO}"
    tar xzvf "$docker_file" -C /tmp >/dev/null 2>&1
    cp -rf /tmp/docker/* /usr/bin/
    print_timestamped "Docker binaries installed successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"
    rm -rf /tmp/docker
}

# Function to install Docker Compose
install_docker_compose() {
    print_timestamped "Searching for Docker Compose binary for ${ARCH}..." "${COLOR_YELLOW}" "${ICON_INFO}"
    # Try to find a versioned file or just the architecture named file
    local compose_file=$(find_latest_version "${BASE_DIR}/docker-compose-linux-${ARCH}*")
    
    if [[ -z "$compose_file" ]]; then
        # Fallback to check if exact match exists (find_latest_version might handle this, but to be safe)
        if [[ -f "${BASE_DIR}/docker-compose-linux-${ARCH}" ]]; then
             compose_file="${BASE_DIR}/docker-compose-linux-${ARCH}"
        fi
    fi

    if [[ -z "$compose_file" ]]; then
        print_timestamped "No Docker Compose binary found for ${ARCH} in ${BASE_DIR}." "${COLOR_RED}" "${ICON_WARNING}"
        exit 1
    fi
    print_timestamped "Installing Docker Compose from $compose_file..." "${COLOR_YELLOW}" "${ICON_INFO}"
    cp -f "$compose_file" /usr/bin/docker-compose
    chmod +x /usr/bin/docker-compose
    print_timestamped "Docker Compose installed successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to install Docker rootless extras
install_docker_rootless_extras() {
    print_timestamped "Searching for latest Docker rootless extras package for ${ARCH}..." "${COLOR_YELLOW}" "${ICON_INFO}"
    local rootless_file=$(find_latest_version "${BASE_DIR}/docker-rootless-extras-*-${ARCH}.tgz")
    if [[ -z "$rootless_file" ]]; then
        print_timestamped "No Docker rootless extras package found. Skipping..." "${COLOR_YELLOW}" "${ICON_INFO}"
        return 0
    fi
    print_timestamped "Installing Docker rootless extras from $rootless_file..." "${COLOR_YELLOW}" "${ICON_INFO}"
    tar xzvf "$rootless_file" -C /tmp >/dev/null 2>&1
    if [[ -d "/tmp/docker" ]]; then
        cp -rf /tmp/docker/* /usr/bin/
    else
        # Handle case where rootless extras might extract to a different directory or files
        tar -xzvf "$rootless_file" -C /tmp --strip-components=1 >/dev/null 2>&1
        cp -rf /tmp/* /usr/bin/ 2>/dev/null || {
            print_timestamped "Failed to copy rootless extras. Check file contents manually." "${COLOR_RED}" "${ICON_WARNING}"
            rm -rf /tmp/*
            return 1
        }
    fi
    print_timestamped "Docker rootless extras installed successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"
    rm -rf /tmp/*
}

# Function to setup Docker from pre-created configuration files
setup_docker_from_files() {
    print_timestamped "Setting up Docker from configuration files..." "${COLOR_YELLOW}" "${ICON_INFO}"

    mkdir -p /etc/docker
    if [[ ! -d "/etc/docker" ]]; then
        print_timestamped "Failed to create /etc/docker directory. Please check permissions." "${COLOR_RED}" "${ICON_WARNING}"
        exit 1
    fi

    local services_dir="${BASE_DIR}/services"
    
    if [[ ! -d "$services_dir" ]]; then
        # Try finding services dir relative to script if BASE_DIR detection was slightly off for some reason
        local script_base_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
        if [[ -d "${script_base_dir}/services" ]]; then
             services_dir="${script_base_dir}/services"
        elif [[ -d "../services" ]]; then
             services_dir="../services"
        else
             print_timestamped "Services directory not found at ${services_dir} or nearby locations." "${COLOR_RED}" "${ICON_WARNING}"
             exit 1
        fi
    fi

    cp -f "${services_dir}/containerd.service" /usr/lib/systemd/system/
    cp -f "${services_dir}/daemon.json" /etc/docker/
    cp -f "${services_dir}/docker.service" /usr/lib/systemd/system/
    cp -f "${services_dir}/docker.socket" /usr/lib/systemd/system/

    systemctl daemon-reload

    print_timestamped "Attempting to start containerd service..." "${COLOR_YELLOW}" "${ICON_INFO}"
    if ! systemctl enable containerd >/dev/null 2>&1 || ! systemctl start containerd >/dev/null 2>&1; then
        print_timestamped "Containerd service failed to start or enable. Check logs with 'systemctl status containerd.service'." "${COLOR_RED}" "${ICON_WARNING}"
        exit 1
    fi
    print_timestamped "Containerd service started and enabled successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"

    print_timestamped "Attempting to start Docker service..." "${COLOR_YELLOW}" "${ICON_INFO}"
    if ! systemctl enable docker >/dev/null 2>&1 || ! systemctl start docker >/dev/null 2>&1; then
        print_timestamped "Docker service failed to start or enable. Check logs with 'systemctl status docker.service'." "${COLOR_RED}" "${ICON_WARNING}"
        exit 1
    fi
    print_timestamped "Docker service started and enabled successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"

    print_timestamped "Docker setup from files completed successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to ensure Docker group and user
ensure_docker_user() {
    print_timestamped "Ensuring Docker user and group exist and current user is in docker group..." "${COLOR_YELLOW}" "${ICON_INFO}"
    if ! getent group docker; then
        groupadd docker
        print_timestamped "Docker group created." "${COLOR_GREEN}" "${ICON_INFO}"
    fi
    if ! id dockeruser &>/dev/null; then
        useradd -m -g docker dockeruser
        print_timestamped "Docker user 'dockeruser' created." "${COLOR_GREEN}" "${ICON_INFO}"
    fi

    # Add the current user to the docker group if not already a member
    local current_user=$(whoami)
    if ! id -nG "$current_user" | grep -qw "docker"; then
        usermod -aG docker "$current_user"
        print_timestamped "Current user '$current_user' added to the 'docker' group. You may need to log out and log back in for changes to take effect, or run 'newgrp docker'." "${COLOR_YELLOW}" "${ICON_WARNING}"
    else
        print_timestamped "Current user '$current_user' is already in the 'docker' group." "${COLOR_GREEN}" "${ICON_SUCCESS}"
    fi

    print_timestamped "Docker user and group configured successfully." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to check Docker status and versions
check_docker() {
    print_timestamped "Checking service status, versions, and home directory..." "${COLOR_YELLOW}" "${ICON_INFO}"
    local svc_name="docker"

    # Check service status and attempt to start
    if ! systemctl is-active "$svc_name" &> /dev/null; then
        print_timestamped "$svc_name service is not active. Attempting to start..." "${COLOR_YELLOW}" "${ICON_INFO}"
        if ! systemctl start "$svc_name" &> /dev/null; then
            print_timestamped "$svc_name startup issue, please check manually with 'systemctl status $svc_name'." "${COLOR_RED}" "${ICON_WARNING}"
            exit 2
        fi
        sleep 5 # Give it a moment to fully start
        if ! systemctl is-active "$svc_name" &> /dev/null; then
            print_timestamped "$svc_name still not active after attempted start. Please check manually with 'systemctl status $svc_name'." "${COLOR_RED}" "${ICON_WARNING}"
            exit 2
        fi
    fi
    print_timestamped "$svc_name service status: Running" "${COLOR_GREEN}" "${ICON_SUCCESS}"

    # Check auto-start status and set
    if ! systemctl is-enabled "$svc_name" &> /dev/null; then
        print_timestamped "$svc_name auto-start is not enabled. Attempting to enable..." "${COLOR_YELLOW}" "${ICON_INFO}"
        if ! systemctl enable "$svc_name" &> /dev/null; then
            print_timestamped "Setting $svc_name auto-start issue, please check manually." "${COLOR_RED}" "${ICON_WARNING}"
            exit 2
        fi
    fi
    print_timestamped "$svc_name auto-start status: Enabled" "${COLOR_GREEN}" "${ICON_SUCCESS}"

    # Get versions and root directory
    local dkVersion dkRoot dcVersion runcVersion containerdVersion
    dkVersion=$(docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "Not available")
    dkRoot=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    dcVersion=$(docker-compose --version --short 2>/dev/null || echo "Not available")
    runcVersion=$(runc --version 2>/dev/null | head -1 | awk '{print $3}' || echo "Not available")
    containerdVersion=$(containerd --version 2>/dev/null | head -1 | awk '{print $3}' || echo "Not available")

    print_timestamped "Docker root directory: $dkRoot" "${COLOR_GREEN}" "${ICON_SUCCESS}"
    print_timestamped "Docker version: $dkVersion" "${COLOR_GREEN}" "${ICON_SUCCESS}"
    print_timestamped "Docker Compose version: $dcVersion" "${COLOR_GREEN}" "${ICON_SUCCESS}"
    print_timestamped "runc version: $runcVersion" "${COLOR_GREEN}" "${ICON_SUCCESS}"
    print_timestamped "containerd version: $containerdVersion" "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Main function to orchestrate Docker setup
main() {
    print_timestamped "Starting Docker installation for architecture: ${ARCH}" "${COLOR_YELLOW}" "${ICON_INFO}"
    print_timestamped "Base directory: ${BASE_DIR}" "${COLOR_YELLOW}" "${ICON_INFO}"

    # Always check and cleanup podman if present
    check_and_remove_podman
    
    install_docker_binaries
    install_docker_compose
    install_docker_rootless_extras
    ensure_docker_user
    setup_docker_from_files
    check_docker
    print_timestamped "Docker installation complete. If you were not already in the 'docker' group, please log out and back in, or run 'newgrp docker' to use Docker without 'sudo'." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Execute the main function
main
