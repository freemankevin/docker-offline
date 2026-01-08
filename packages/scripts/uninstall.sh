#!/bin/bash

# Color settings
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_RESET="\033[0m"
ICON_INFO="🛈"
ICON_SUCCESS="✅"
ICON_WARNING="⚠️"

# Function to print timestamped message (re-using from install script for consistency)
print_timestamped() {
    local message="$1"
    local color="$2"
    local icon="$3"
    echo -e "${color}${icon} $(date '+%Y-%m-%d %H:%M:%S') - ${message}${COLOR_RESET}"
}

# Function to remove Docker binaries
remove_docker_binaries() {
    print_timestamped "Removing Docker binaries..." "${COLOR_RED}" "${ICON_INFO}"
    find /usr/bin /usr/local/bin -maxdepth 1 -type f \( -name "docker*" -o -name "containerd*" -o -name "ctr" -o -name "runc" \) -exec rm -f {} +
    print_timestamped "Docker binaries removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to remove Docker Compose
remove_docker_compose() {
    print_timestamped "Removing Docker Compose..." "${COLOR_RED}" "${ICON_INFO}"
    rm -f /usr/bin/docker-compose
    print_timestamped "Docker Compose removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to teardown Docker configuration
teardown_docker_configuration() {
    print_timestamped "Stopping and disabling Docker services..." "${COLOR_RED}" "${ICON_INFO}"
    systemctl stop docker 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    systemctl disable containerd 2>/dev/null || true

    print_timestamped "Removing Docker configuration files and systemd units..." "${COLOR_RED}" "${ICON_INFO}"
    find /usr/lib/systemd/system /etc/systemd/system -type f \( -name "*docker*.service" -o -name "*docker*.socket" -o -name "*containerd*.service" \) -exec rm -f {} +
    find /etc/systemd/system -type d -name "docker.service.d" -exec rm -rf {} +
    find /etc -type d -name "docker" -exec rm -rf {} +
    find /etc -type f -path "/etc/docker/daemon.json" -exec rm -f {} +

    systemctl daemon-reload
    print_timestamped "Docker configuration and services removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to remove Docker user and group
remove_docker_user() {
    print_timestamped "Removing Docker user and group..." "${COLOR_RED}" "${ICON_INFO}"
    if getent passwd dockeruser &>/dev/null; then
        userdel -r dockeruser 2>/dev/null || true
        print_timestamped "Docker user 'dockeruser' removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
    else
        print_timestamped "Docker user 'dockeruser' does not exist." "${COLOR_YELLOW}" "${ICON_INFO}"
    fi
    if getent group docker &>/dev/null; then
        groupdel docker 2>/dev/null || true
        print_timestamped "Docker group removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
    else
        print_timestamped "Docker group does not exist." "${COLOR_YELLOW}" "${ICON_INFO}"
    fi
    print_timestamped "Docker user and group cleanup complete." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to clean up Docker security settings
cleanup_docker_security() {
    print_timestamped "Cleaning up security settings..." "${COLOR_RED}" "${ICON_INFO}"
    sed -i '/DOCKER_CONTENT_TRUST=1/d' ~/.bashrc 2>/dev/null || true
    print_timestamped "Docker security settings cleaned up." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Function to remove Docker data directories automatically
remove_docker_data_directories_auto() {
    print_timestamped "Removing Docker data directories automatically..." "${COLOR_RED}" "${ICON_INFO}"
    find /var/lib /data -type d -name "docker" -exec rm -rf {} +
    print_timestamped "Docker data directories removed." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Main function to orchestrate all steps
main() {
    remove_docker_binaries
    remove_docker_compose
    teardown_docker_configuration
    remove_docker_user
    cleanup_docker_security
    remove_docker_data_directories_auto
    print_timestamped "Docker has been completely uninstalled, including security, audit configurations, and data directories." "${COLOR_GREEN}" "${ICON_SUCCESS}"
}

# Execute the main function
main
