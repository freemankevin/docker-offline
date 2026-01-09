#!/bin/bash
# ============================================================================
# Docker 卸载脚本
# 完全清理 Docker、Docker Compose 及相关配置
# ============================================================================

# Color and style settings - VS Code style
readonly COLOR_RESET="\033[0m"
readonly COLOR_TIMESTAMP="\033[0;90m"      # 灰色 - 时间戳
readonly COLOR_INFO="\033[0;36m"           # 青色 - INFO
readonly COLOR_SUCCESS="\033[0;32m"        # 绿色 - SUCCESS
readonly COLOR_WARNING="\033[0;33m"        # 黄色 - WARNING
readonly COLOR_ERROR="\033[0;31m"          # 红色 - ERROR
readonly COLOR_DEBUG="\033[0;35m"          # 品红 - DEBUG
readonly COLOR_NOTICE="\033[1;36m"         # 亮青色 - NOTICE
readonly COLOR_KEY="\033[1;37m"            # 白色 - 关键信息
readonly COLOR_VALUE="\033[0;32m"          # 绿色 - 值
readonly COLOR_DIMMED="\033[0;37m"         # 淡白色 - 详细信息

# ============================================================================
# Utility Functions
# ============================================================================

print_log() {
    local level="$1"
    local message="$2"
    local color="$3"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local level_padded=$(printf "%-8s" "[$level]")
    
    echo -e "${COLOR_TIMESTAMP}${timestamp}${COLOR_RESET} ${color}${level_padded}${COLOR_RESET} ${message}"
}

print_info() { print_log "info" "$1" "$COLOR_INFO"; }
print_success() { print_log "success" "$1" "$COLOR_SUCCESS"; }
print_warning() { print_log "warning" "$1" "$COLOR_WARNING"; }
print_error() { print_log "error" "$1" "$COLOR_ERROR"; }
print_notice() { print_log "notice" "$1" "$COLOR_NOTICE"; }
print_debug() { print_log "debug" "$1" "$COLOR_DEBUG"; }

# 打印进度信息
print_progress() {
    local message="$1"
    local icon="$2"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local level_padded=$(printf "%-8s" "[step]")
    
    echo -e "${COLOR_TIMESTAMP}${timestamp}${COLOR_RESET} ${COLOR_NOTICE}${level_padded}${COLOR_RESET} ${icon} ${message}"
}

# ============================================================================
# Service Management
# ============================================================================

stop_docker_services() {
    print_progress "Stopping Docker services" "🛑"
    
    # Stop services gracefully
    systemctl stop docker.socket &>/dev/null || true
    systemctl stop docker &>/dev/null || true
    systemctl stop containerd &>/dev/null || true
    
    # Disable autostart
    systemctl disable docker.socket &>/dev/null || true
    systemctl disable docker &>/dev/null || true
    systemctl disable containerd &>/dev/null || true
    
    print_debug "  → docker.socket stopped and disabled"
    print_debug "  → docker service stopped and disabled"
    print_debug "  → containerd service stopped and disabled"
    
    print_success "✓ Docker services stopped and disabled"
}

# ============================================================================
# Binary Cleanup
# ============================================================================

remove_docker_binaries() {
    print_progress "Removing Docker binaries" "🗑️ "
    
    local binaries=(
        "docker"
        "dockerd"
        "docker-init"
        "docker-proxy"
        "containerd"
        "containerd-shim"
        "containerd-shim-runc-v2"
        "ctr"
        "runc"
        "rootlesskit"
        "rootlesskit-docker-proxy"
        "vpnkit"
        "docker-compose"
    )
    
    local removed_count=0
    for bin in "${binaries[@]}"; do
        # 检查文件是否存在
        if [[ -f "/usr/bin/${bin}" ]]; then
            rm -f "/usr/bin/${bin}" 2>/dev/null || true
            if [[ ! -f "/usr/bin/${bin}" ]]; then
                print_debug "  → Removed: ${COLOR_VALUE}${bin}${COLOR_RESET}"
                ((removed_count++))
            fi
        fi
        
        if [[ -f "/usr/local/bin/${bin}" ]]; then
            rm -f "/usr/local/bin/${bin}" 2>/dev/null || true
            if [[ ! -f "/usr/local/bin/${bin}" ]]; then
                print_debug "  → Removed: ${COLOR_VALUE}${bin}${COLOR_RESET}"
                ((removed_count++))
            fi
        fi
    done
    
    print_success "✓ Docker binaries removed (${COLOR_VALUE}${removed_count}${COLOR_RESET} items)"
}

# ============================================================================
# Configuration Cleanup
# ============================================================================

remove_systemd_units() {
    print_progress "Removing systemd units" "⚙️ "
    
    local service_dirs=(
        "/usr/lib/systemd/system"
        "/etc/systemd/system"
        "/lib/systemd/system"
    )
    
    local removed_count=0
    
    for dir in "${service_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        
        # 删除 docker 相关的 service 文件
        if [[ -f "$dir/docker.service" ]]; then
            rm -f "$dir/docker.service"
            print_debug "  → Removed: ${COLOR_VALUE}docker.service${COLOR_RESET}"
            ((removed_count++))
        fi
        
        if [[ -f "$dir/docker.socket" ]]; then
            rm -f "$dir/docker.socket"
            print_debug "  → Removed: ${COLOR_VALUE}docker.socket${COLOR_RESET}"
            ((removed_count++))
        fi
        
        # 删除 containerd 相关的 service 文件
        if [[ -f "$dir/containerd.service" ]]; then
            rm -f "$dir/containerd.service"
            print_debug "  → Removed: ${COLOR_VALUE}containerd.service${COLOR_RESET}"
            ((removed_count++))
        fi
    done
    
    # 删除 service drop-in 目录
    if [[ -d "/etc/systemd/system/docker.service.d" ]]; then
        rm -rf "/etc/systemd/system/docker.service.d"
        print_debug "  → Removed: ${COLOR_VALUE}/etc/systemd/system/docker.service.d${COLOR_RESET}"
        ((removed_count++))
    fi
    
    systemctl daemon-reload 2>/dev/null || true
    
    print_success "✓ Systemd units removed (${COLOR_VALUE}${removed_count}${COLOR_RESET} items)"
}

remove_config_files() {
    print_progress "Removing configuration files" "📄"
    
    local config_paths=(
        "/etc/docker"
        "/etc/default/docker"
        "/etc/sysconfig/docker"
    )
    
    local removed_count=0
    for path in "${config_paths[@]}"; do
        if [[ -e "$path" ]]; then
            if rm -rf "$path" &>/dev/null 2>&1; then
                print_debug "  → Removed: ${COLOR_VALUE}${path}${COLOR_RESET}"
                ((removed_count++))
            fi
        fi
    done
    
    print_success "✓ Configuration files removed (${COLOR_VALUE}${removed_count}${COLOR_RESET} items)"
}

# ============================================================================
# User/Group Cleanup
# ============================================================================

remove_docker_user_group() {
    print_progress "Removing Docker user and group" "👤"
    
    local removed_count=0
    
    # Remove dockeruser
    if id dockeruser &>/dev/null 2>&1; then
        userdel -r dockeruser 2>/dev/null || true
        print_debug "  → Removed user: ${COLOR_VALUE}dockeruser${COLOR_RESET}"
        ((removed_count++))
    fi
    
    # Remove docker group
    if getent group docker &>/dev/null 2>&1; then
        groupdel docker 2>/dev/null || true
        print_debug "  → Removed group: ${COLOR_VALUE}docker${COLOR_RESET}"
        ((removed_count++))
    fi
    
    print_success "✓ User and group cleanup completed (${COLOR_VALUE}${removed_count}${COLOR_RESET} items)"
}

# ============================================================================
# Data Cleanup
# ============================================================================

remove_docker_data() {
    print_progress "Removing Docker data directories" "🗂️ "
    
    local data_dirs=(
        "/var/lib/docker"
        "/var/lib/containerd"
        "/var/lib/dockershim"
        "/var/run/docker"
        "/var/run/docker.sock"
        "/run/docker"
        "/run/docker.sock"
    )
    
    local removed_count=0
    for dir in "${data_dirs[@]}"; do
        if [[ -e "$dir" ]]; then
            rm -rf "$dir" 2>/dev/null || true
            print_debug "  → Removed: ${COLOR_VALUE}${dir}${COLOR_RESET}"
            ((removed_count++))
        fi
    done
    
    # Check for Docker directories in common locations
    for location in /var/lib /data; do
        if [[ -d "$location" ]]; then
            local docker_dir="${location}/docker"
            if [[ -d "$docker_dir" ]]; then
                rm -rf "$docker_dir" 2>/dev/null || true
                print_debug "  → Removed: ${COLOR_VALUE}${docker_dir}${COLOR_RESET}"
                ((removed_count++))
            fi
        fi
    done
    
    print_success "✓ Docker data directories removed (${COLOR_VALUE}${removed_count}${COLOR_RESET} items)"
}

# ============================================================================
# Security Settings Cleanup
# ============================================================================

cleanup_security_settings() {
    print_progress "Cleaning up security settings" "🔐"
    
    local shell_configs=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.zshrc"
        "$HOME/.profile"
    )
    
    local removed_count=0
    for config in "${shell_configs[@]}"; do
        if [[ -f "$config" ]]; then
            # 清理 DOCKER_CONTENT_TRUST
            if grep -q "DOCKER_CONTENT_TRUST=1" "$config" 2>/dev/null; then
                sed -i '/DOCKER_CONTENT_TRUST=1/d' "$config" 2>/dev/null || true
                print_debug "  → Cleaned: ${COLOR_VALUE}${config}${COLOR_RESET} (DOCKER_CONTENT_TRUST)"
                ((removed_count++))
            fi
            
            # 清理 DOCKER_HOST
            if grep -q "DOCKER_HOST=" "$config" 2>/dev/null; then
                sed -i '/DOCKER_HOST=/d' "$config" 2>/dev/null || true
                print_debug "  → Cleaned: ${COLOR_VALUE}${config}${COLOR_RESET} (DOCKER_HOST)"
                ((removed_count++))
            fi
        fi
    done
    
    print_success "✓ Security settings cleaned up (${COLOR_VALUE}${removed_count}${COLOR_RESET} items)"
}

# ============================================================================
# Verification
# ============================================================================

verify_removal() {
    print_notice "🔎 Verifying Docker removal..."
    echo ""
    
    local issues=()
    local all_clean=true
    
    # Check for remaining binaries
    if command -v docker &>/dev/null; then
        issues+=("Docker binary still exists")
        print_error "  ✗ Docker binary still exists at: $(command -v docker)"
        all_clean=false
    else
        print_success "  ✓ Docker binary removed"
    fi
    
    # Check for running services
    if systemctl is-active docker &>/dev/null 2>&1; then
        issues+=("Docker service still running")
        print_error "  ✗ Docker service still running"
        all_clean=false
    else
        print_success "  ✓ Docker service not running"
    fi
    
    # Check for remaining data
    if [[ -d "/var/lib/docker" ]]; then
        issues+=("/var/lib/docker still exists")
        print_error "  ✗ /var/lib/docker still exists"
        all_clean=false
    else
        print_success "  ✓ /var/lib/docker removed"
    fi
    
    echo ""
    
    if [[ "$all_clean" == true ]]; then
        print_success "✓ Docker has been completely removed"
        return 0
    else
        print_warning "⚠️  Some issues detected during removal (see above)"
        return 1
    fi
}

# ============================================================================
# Main Uninstallation Flow
# ============================================================================

main() {
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as ${COLOR_KEY}root${COLOR_RESET}"
        exit 1
    fi
    
    echo ""
    print_notice "╔════════════════════════════════════════════════════════════════╗"
    print_notice "║           🐳 Docker Offline Uninstallation Script 🐳            ║"
    print_notice "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Confirm with user
    print_warning "⚠️  ${COLOR_KEY}WARNING${COLOR_RESET}: This will completely remove Docker and all its data"
    echo ""
    read -p "$(echo -e "${COLOR_WARNING}[warning  ]${COLOR_RESET} Are you sure? (y/N): ")" -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "💭 Uninstallation cancelled"
        echo ""
        exit 0
    fi
    
    echo ""
    
    # Execute removal steps with error handling
    stop_docker_services || true
    echo ""
    
    remove_docker_binaries || true
    echo ""
    
    remove_systemd_units || true
    echo ""
    
    remove_config_files || true
    echo ""
    
    remove_docker_user_group || true
    echo ""
    
    remove_docker_data || true
    echo ""
    
    cleanup_security_settings || true
    echo ""
    
    # Verify removal
    if verify_removal; then
        echo ""
        print_success "╔════════════════════════════════════════════════════════════════╗"
        print_success "║      ✓ Docker has been completely uninstalled! ✓               ║"
        print_success "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        exit 0
    else
        echo ""
        print_warning "╔════════════════════════════════════════════════════════════════╗"
        print_warning "║  Uninstallation completed with warnings (see details above)    ║"
        print_warning "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        exit 1
    fi
}

# Execute main function
main "$@"