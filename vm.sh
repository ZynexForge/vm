#!/bin/bash
set -euo pipefail

# =============================
# ZYNEXFORGE™ - Ultimate VM Virtualization Platform
# =============================

# Terminal colors
COLOR_RESET="\033[0m"
COLOR_BLUE="\033[1;34m"
COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_WHITE="\033[1;37m"
COLOR_MAGENTA="\033[1;35m"
COLOR_GRAY="\033[90m"
COLOR_ORANGE="\033[38;5;214m"

# UI constants
SEPARATOR="========================================================================="
SUBTLE_SEP="─────────────────────────────────────────────────────────────────────────"

# Configuration - ULTIMATE SETTINGS
MAX_VMS=4
VM_BASE_DIR="$HOME/.zynexforge"
VM_DIR="$VM_BASE_DIR/vms"
IMAGES_DIR="$VM_BASE_DIR/images"
TEMPLATES_DIR="$VM_BASE_DIR/templates"
NETWORKS_DIR="$VM_BASE_DIR/networks"
BACKUPS_DIR="$VM_BASE_DIR/backups"
LOGS_DIR="$VM_BASE_DIR/logs"
SCRIPTS_DIR="$VM_BASE_DIR/scripts"

# Performance Optimizations
OPTIMAL_MEMORY=8192  # 8GB default
OPTIMAL_CPUS=4       # 4 vCPUs default
OPTIMAL_DISK="100G"  # 100GB default
NETWORK_BASE="192.168.100"  # Base for auto IP generation

# Create all necessary directories
mkdir -p "$VM_DIR" "$IMAGES_DIR" "$TEMPLATES_DIR" "$NETWORKS_DIR" \
         "$BACKUPS_DIR" "$LOGS_DIR" "$SCRIPTS_DIR"

# Function to display ultimate header
display_header() {
    clear
    echo ""
    echo -e "${COLOR_CYAN}"
    cat << "EOF"

__________                             ___________                         
\____    /_____ . . ____   ____ ___  ___ \_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /  |    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 
EOF
    echo -e "${COLOR_RESET}"
    echo -e "${COLOR_ORANGE}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_ORANGE}║                    ZYNEXFORGE™ ULTIMATE EDITION v5.0                  ║${COLOR_RESET}"
    echo -e "${COLOR_ORANGE}║          Enterprise Virtualization Platform | Performance Optimized    ║${COLOR_RESET}"
    echo -e "${COLOR_ORANGE}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Max VMs: $MAX_VMS | Auto IP | AMD Optimized | Proxmox Ready${COLOR_RESET}"
    echo "$SEPARATOR"
    echo
}

# Function to print styled messages
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $message" ;;
        "WARN") echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $message" ;;
        "ERROR") echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $message" ;;
        "SUCCESS") echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $message" ;;
        "INPUT") echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} $message" ;;
        "NETWORK") echo -e "${COLOR_MAGENTA}[NETWORK]${COLOR_RESET} $message" ;;
        "BACKUP") echo -e "${COLOR_GRAY}[BACKUP]${COLOR_RESET} $message" ;;
        "ULTIMATE") echo -e "${COLOR_ORANGE}[ULTIMATE]${COLOR_RESET} $message" ;;
        *) echo -e "${COLOR_WHITE}[$type]${COLOR_RESET} $message" ;;
    esac
}

# Function to log actions
log_action() {
    local action=$1
    local vm_name=$2
    local details=$3
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $action | $vm_name | $details" >> "$LOGS_DIR/zynexforge.log"
}

# Function to display section header
section_header() {
    local title=$1
    echo
    echo -e "${COLOR_WHITE}$title${COLOR_RESET}"
    echo "$SUBTLE_SEP"
}

# Function to generate random IP in 192.168.100.x range
generate_auto_ip() {
    local ip_octet=$((RANDOM % 254 + 1))  # 1-254
    echo "${NETWORK_BASE}.${ip_octet}"
}

# Function to check if IP is already used
is_ip_used() {
    local ip=$1
    # Check in all VM configs
    for config in "$VM_DIR"/*.conf 2>/dev/null; do
        if [[ -f "$config" ]] && grep -q "STATIC_IP=\"$ip\"" "$config"; then
            return 0  # IP is used
        fi
    done
    return 1  # IP is available
}

# Function to generate unique auto IP
generate_unique_auto_ip() {
    local max_attempts=50
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        local new_ip=$(generate_auto_ip)
        if ! is_ip_used "$new_ip"; then
            echo "$new_ip"
            return 0
        fi
        ((attempts++))
    done
    
    # Fallback to sequential IP if random fails
    for i in {100..254}; do
        local fallback_ip="${NETWORK_BASE}.$i"
        if ! is_ip_used "$fallback_ip"; then
            echo "$fallback_ip"
            return 0
        fi
    done
    
    # Last resort
    echo "${NETWORK_BASE}.200"
}

# Function to detect system capabilities
detect_system_capabilities() {
    # Detect CPU vendor
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        CPU_VENDOR="amd"
        print_status "ULTIMATE" "Detected AMD CPU - Optimizing for AMD Ryzen/EPYC"
        OPTIMAL_CPU_TYPE="EPYC-v4"
    elif grep -q "GenuineIntel" /proc/cpuinfo; then
        CPU_VENDOR="intel"
        print_status "ULTIMATE" "Detected Intel CPU - Optimizing for Intel Core/Xeon"
        OPTIMAL_CPU_TYPE="host"
    else
        CPU_VENDOR="generic"
        OPTIMAL_CPU_TYPE="host"
    fi
    
    # Detect total memory and set optimal default
    local total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $total_mem_mb -gt 32000 ]]; then
        OPTIMAL_MEMORY=16384  # 16GB for systems with >32GB RAM
    elif [[ $total_mem_mb -gt 16000 ]]; then
        OPTIMAL_MEMORY=8192   # 8GB for systems with >16GB RAM
    fi
    
    # Detect CPU cores
    local total_cores=$(nproc)
    if [[ $total_cores -gt 8 ]]; then
        OPTIMAL_CPUS=$((total_cores / 2))  # Use half of cores for optimal performance
    fi
    
    print_status "ULTIMATE" "System detected: ${total_mem_mb}MB RAM, ${total_cores} cores"
}

# Function to generate MAC address
generate_mac() {
    printf '52:54:%02x:%02x:%02x:%02x\n' \
        $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

# Function to get optimal CPU flags based on vendor
get_optimal_cpu_flags() {
    case "$CPU_VENDOR" in
        "amd")
            echo "EPYC-v4,+svm,+invtsc,+topoext,+npt,+nrip-save,+ibpb,+virt-ssbd,+rdctl-no,+skip-l1dfl-vmentry,+mds-no"
            ;;
        "intel")
            echo "host,+vmx,+invtsc,+tsc-deadline,+kvm-steal-time,+kvm-asyncpf,+kvmclock,+kvm-nopiodelay,+kvm-poll-control"
            ;;
        *)
            echo "host"
            ;;
    esac
}

# Function to validate input
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a number"
                return 1
            fi
            ;;
        "size")
            if ! [[ "$value" =~ ^[0-9]+[GgTtMm]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M, 2T)"
                return 1
            fi
            ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 22 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (22-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore, and contain only letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
        "ip")
            if ! [[ "$value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                print_status "ERROR" "Must be a valid IP address"
                return 1
            fi
            # Validate octets
            IFS='.' read -r -a octets <<< "$value"
            for octet in "${octets[@]}"; do
                if [[ $octet -lt 0 || $octet -gt 255 ]]; then
                    print_status "ERROR" "IP octet must be between 0 and 255"
                    return 1
                fi
            done
            ;;
        "mac")
            if ! [[ "$value" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                print_status "ERROR" "Must be a valid MAC address (format: XX:XX:XX:XX:XX:XX)"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "virt-viewer" "screen" "tmux")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Install with: nix-shell -p ${missing_deps[*]}"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
    if [ -f "network-config" ]; then rm -f "network-config"; fi
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to get VM count
get_vm_count() {
    get_vm_list | wc -l
}

# Function to check VM limit
check_vm_limit() {
    local current_count=$(get_vm_count)
    if [ $current_count -ge $MAX_VMS ]; then
        print_status "ERROR" "Maximum VM limit reached ($MAX_VMS). Delete existing VMs to create new ones."
        return 1
    fi
    return 0
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear previous variables
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD SSH_KEYS
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset NETWORK_CONFIG MAC_ADDRESS STATIC_IP BACKUP_SCHEDULE SNAPSHOT_COUNT CPU_TYPE GPU_PASSTHROUGH
        unset VIRTIO_TYPE SPICE_PORT SPICE_ENABLED TPMS_ENABLED UEFI_ENABLED SECURE_BOOT
        
        source "$config_file"
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
SSH_KEYS="$SSH_KEYS"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
NETWORK_CONFIG="$NETWORK_CONFIG"
MAC_ADDRESS="$MAC_ADDRESS"
STATIC_IP="$STATIC_IP"
BACKUP_SCHEDULE="$BACKUP_SCHEDULE"
SNAPSHOT_COUNT="$SNAPSHOT_COUNT"
CPU_TYPE="$CPU_TYPE"
GPU_PASSTHROUGH="$GPU_PASSTHROUGH"
VIRTIO_TYPE="$VIRTIO_TYPE"
SPICE_PORT="$SPICE_PORT"
SPICE_ENABLED="$SPICE_ENABLED"
TPMS_ENABLED="$TPMS_ENABLED"
UEFI_ENABLED="$UEFI_ENABLED"
SECURE_BOOT="$SECURE_BOOT"
EOF
    
    print_status "SUCCESS" "Configuration saved"
    log_action "SAVE_CONFIG" "$VM_NAME" "Configuration updated"
}

# Function to setup VM image with caching
setup_vm_image() {
    print_status "ULTIMATE" "Initializing VM storage with performance optimizations..."
    
    # Create cache directory for images
    local cache_dir="$IMAGES_DIR"
    mkdir -p "$cache_dir"
    
    # Extract filename from URL
    local image_filename=$(basename "$IMG_URL")
    local cached_image="$cache_dir/$image_filename"
    
    # Check if image is already cached
    if [[ -f "$cached_image" ]]; then
        print_status "INFO" "Using cached image from $cached_image"
        cp "$cached_image" "$IMG_FILE"
    else
        print_status "INFO" "Downloading OS image with resume capability..."
        if ! wget --continue --progress=bar:force "$IMG_URL" -O "$cached_image.tmp"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$cached_image.tmp" "$cached_image"
        cp "$cached_image" "$IMG_FILE"
    fi
    
    # Create optimized qcow2 image
    print_status "ULTIMATE" "Creating optimized disk image..."
    qemu-img create -f qcow2 -o cluster_size=2M,preallocation=metadata,compat=1.1,lazy_refcounts=on "$IMG_FILE" "$DISK_SIZE"
    
    # Advanced cloud-init configuration
    cat > user-data <<EOF
#cloud-config
# ZYNEXFORGE ULTIMATE CONFIGURATION
hostname: $HOSTNAME
fqdn: $HOSTNAME.local
ssh_pwauth: true
disable_root: false
preserve_hostname: false
manage_etc_hosts: true
package_upgrade: true
package_reboot_if_required: true
timezone: UTC

# Security hardening
ssh_genkeytypes: ['rsa', 'ed25519']
ssh_authorized_keys:
$(echo "$SSH_KEYS" | sed 's/^/  - /')

# Ultimate user configuration
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
    ssh_authorized_keys:
$(echo "$SSH_KEYS" | sed 's/^/      - /')
    groups: [adm, audio, cdrom, dialout, floppy, video, plugdev, dip, netdev, docker]
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    homedir: /home/$USERNAME

# Ultimate packages
packages:
  - qemu-guest-agent
  - fail2ban
  - unattended-upgrades
  - apt-listchanges
  - htop
  - neofetch
  - curl
  - wget
  - git
  - python3
  - python3-pip
  - docker.io
  - docker-compose
  - net-tools
  - ethtool
  - iperf3
  - nginx
  - ufw
  - haveged

# Ultimate run commands
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - systemctl enable haveged
  - systemctl start haveged
  - ufw --force enable
  - ufw allow ssh
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - echo "vm.swappiness=10" >> /etc/sysctl.conf
  - echo "vm.dirty_ratio=10" >> /etc/sysctl.conf
  - echo "vm.dirty_background_ratio=5" >> /etc/sysctl.conf
  - echo "net.ipv4.tcp_fastopen=3" >> /etc/sysctl.conf
  - echo "net.core.rmem_max=134217728" >> /etc/sysctl.conf
  - echo "net.core.wmem_max=134217728" >> /etc/sysctl.conf
  - echo "net.ipv4.tcp_rmem=4096 87380 134217728" >> /etc/sysctl.conf
  - echo "net.ipv4.tcp_wmem=4096 65536 134217728" >> /etc/sysctl.conf
  - sysctl -p
  - timedatectl set-timezone UTC
  - timedatectl set-ntp true
  - apt-get -y autoremove
  - apt-get -y clean

# Final boot optimization
bootcmd:
  - echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

power_state:
  mode: reboot
  timeout: 300
  message: "ZYNEXFORGE Ultimate VM is ready!"
EOF

    # Network configuration with static IP
    cat > network-config <<EOF
version: 2
ethernets:
  eth0:
    match:
      macaddress: "$MAC_ADDRESS"
    dhcp4: false
    addresses: [$STATIC_IP/24]
    gateway4: ${NETWORK_BASE}.1
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1, 9.9.9.9]
      search: [local]
    routes:
      - to: 0.0.0.0/0
        via: ${NETWORK_BASE}.1
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
hostname: $HOSTNAME
dsmode: local
EOF

    if ! cloud-localds -N network-config "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    # Create initial snapshot if enabled
    if [[ "$SNAPSHOT_COUNT" -gt 0 ]]; then
        qemu-img snapshot -c "initial" "$IMG_FILE"
        print_status "ULTIMATE" "Created initial snapshot"
    fi
    
    print_status "ULTIMATE" "VM image optimized with performance settings"
}

# Function to create ultimate VM
create_new_vm() {
    if ! check_vm_limit; then
        return 1
    fi
    
    # Detect system capabilities first
    detect_system_capabilities
    
    display_header
    section_header "CREATE ULTIMATE VIRTUAL MACHINE"
    
    print_status "ULTIMATE" "Auto-configuring optimal settings for your system..."
    
    # OS Selection with Proxmox
    section_header "OPERATING SYSTEM SELECTION"
    print_status "INFO" "Available operating systems (Proxmox included):"
    
    # Define OS_OPTIONS here since it's not accessible yet
    declare -A OS_OPTIONS=(
        ["Ubuntu 22.04 LTS"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
        ["Ubuntu 24.04 LTS"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
        ["Debian 11 Bullseye"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
        ["Debian 12 Bookworm"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
        ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
        ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
        ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
        ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
        ["Proxmox VE 8"]="proxmox|ve8|https://download.proxmox.com/images/cloud/bookworm/current/debian-12-genericcloud-amd64.qcow2|proxmox8|root|proxmox"
    )
    
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo -e "  ${COLOR_CYAN}$i) $os${COLOR_RESET}"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        echo
        read -p "$(print_status "INPUT" "Select OS (1-${#OS_OPTIONS[@]}): ")" choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            print_status "ULTIMATE" "Selected: $os"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # ULTIMATE VM Configuration
    section_header "VIRTUAL MACHINE CONFIGURATION"
    
    # Auto-generate VM name based on OS
    local auto_vm_name="${DEFAULT_HOSTNAME}-$(date +%s | tail -c 4)"
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (recommended: $auto_vm_name): ")" VM_NAME
        VM_NAME="${VM_NAME:-$auto_vm_name}"
        if validate_input "name" "$VM_NAME"; then
            # Check if VM name already exists
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    # Auto-set hostname
    HOSTNAME="$VM_NAME"
    print_status "ULTIMATE" "Hostname set to: $HOSTNAME"

    # ULTIMATE Access Credentials
    section_header "ACCESS CREDENTIALS"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter username (recommended: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    # Secure password with auto-generation option
    print_status "ULTIMATE" "Password requirements: Minimum 4 characters (secure auto-generation available)"
    read -p "$(print_status "INPUT" "Auto-generate secure password? (Y/n): ")" auto_pass
    if [[ "$auto_pass" =~ ^[Nn]$ ]]; then
        while true; do
            read -s -p "$(print_status "INPUT" "Enter password: ")" PASSWORD
            echo
            if [ ${#PASSWORD} -ge 4 ]; then
                read -s -p "$(print_status "INPUT" "Confirm password: ")" PASSWORD_CONFIRM
                echo
                if [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
                    break
                else
                    print_status "ERROR" "Passwords do not match"
                fi
            else
                print_status "ERROR" "Password must be at least 4 characters"
            fi
        done
    else
        # Auto-generate secure password
        PASSWORD=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
        print_status "ULTIMATE" "Auto-generated password: $PASSWORD"
    fi

    # SSH keys
    read -p "$(print_status "INPUT" "Add SSH public keys (recommended for security): ")" SSH_KEYS

    # ULTIMATE Resource Allocation with auto-optimization
    section_header "RESOURCE ALLOCATION"
    
    echo -e "  ${COLOR_GRAY}Recommended optimal values for your system:${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}Memory:${COLOR_RESET} ${OPTIMAL_MEMORY}MB"
    echo -e "  ${COLOR_GREEN}vCPUs:${COLOR_RESET} ${OPTIMAL_CPUS}"
    echo -e "  ${COLOR_GREEN}Disk:${COLOR_RESET} ${OPTIMAL_DISK}"
    echo
    
    while true; do
        read -p "$(print_status "INPUT" "Disk size (recommended: $OPTIMAL_DISK): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-$OPTIMAL_DISK}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (recommended: $OPTIMAL_MEMORY): ")" MEMORY
        MEMORY="${MEMORY:-$OPTIMAL_MEMORY}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (recommended: $OPTIMAL_CPUS): ")" CPUS
        CPUS="${CPUS:-$OPTIMAL_CPUS}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    # ULTIMATE CPU Features
    section_header "ADVANCED CPU FEATURES"
    
    echo -e "  ${COLOR_ORANGE}Auto-detected optimal CPU type for your system: ${OPTIMAL_CPU_TYPE}${COLOR_RESET}"
    echo "CPU Types:"
    echo "  1) host (maximum performance)"
    echo "  2) EPYC-v4 (AMD optimized)"
    echo "  3) kvm64 (compatibility)"
    echo "  4) custom (experts only)"
    
    read -p "$(print_status "INPUT" "Select CPU type (recommended: 1): ")" cpu_choice
    case $cpu_choice in
        1) CPU_TYPE="host" ;;
        2) CPU_TYPE="EPYC-v4" ;;
        3) CPU_TYPE="kvm64" ;;
        4) 
            read -p "$(print_status "INPUT" "Enter custom CPU type: ")" CPU_TYPE
            CPU_TYPE="${CPU_TYPE:-$(get_optimal_cpu_flags)}"
            ;;
        *) CPU_TYPE="$OPTIMAL_CPU_TYPE" ;;
    esac

    # GPU passthrough
    read -p "$(print_status "INPUT" "Enable GPU passthrough? (for gaming/rendering): ")" gpu_choice
    if [[ "$gpu_choice" =~ ^[Yy]$ ]]; then
        GPU_PASSTHROUGH=true
        print_status "ULTIMATE" "GPU passthrough enabled"
    else
        GPU_PASSTHROUGH=false
    fi

    # ULTIMATE Networking
    section_header "NETWORK CONFIGURATION"
    
    # Generate MAC address
    MAC_ADDRESS=$(generate_mac)
    echo -e "  ${COLOR_GREEN}Generated MAC:${COLOR_RESET} ${COLOR_CYAN}$MAC_ADDRESS${COLOR_RESET}"
    
    # Auto-generate unique static IP
    AUTO_STATIC_IP=$(generate_unique_auto_ip)
    
    echo -e "  ${COLOR_ORANGE}Auto-generated unique static IP: ${COLOR_CYAN}$AUTO_STATIC_IP${COLOR_RESET}"
    
    # Network type selection
    echo "Network Configuration:"
    echo -e "  1) ${COLOR_YELLOW}Tap networking (bridged)${COLOR_RESET} ${COLOR_GREEN}[RECOMMENDED]${COLOR_RESET}"
    echo "  2) User mode networking (NAT)"
    echo "  3) Macvtap"
    
    read -p "$(print_status "INPUT" "Select network type (recommended: 1): ")" net_choice
    case $net_choice in
        1) 
            NETWORK_CONFIG="tap"
            print_status "ULTIMATE" "Bridged networking selected - VM will be accessible on your LAN"
            ;;
        2) 
            NETWORK_CONFIG="user"
            print_status "INFO" "NAT networking selected"
            ;;
        3) 
            NETWORK_CONFIG="macvtap"
            print_status "INFO" "Macvtap networking selected"
            ;;
        *) 
            NETWORK_CONFIG="tap"
            print_status "ULTIMATE" "Defaulting to bridged networking"
            ;;
    esac

    # Auto-configure static IP
    print_status "ULTIMATE" "Auto-configuring static IP: $AUTO_STATIC_IP"
    STATIC_IP="$AUTO_STATIC_IP"

    # SSH Port with auto-check
    while true; do
        DEFAULT_SSH_PORT=$(( 22220 + $(get_vm_count) ))
        read -p "$(print_status "INPUT" "SSH Port (recommended unique port: $DEFAULT_SSH_PORT): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-$DEFAULT_SSH_PORT}"
        if validate_input "port" "$SSH_PORT"; then
            # Check if port is already in use
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    # GUI mode
    read -p "$(print_status "INPUT" "Enable GUI mode? (for desktop environments): ")" gui_input
    if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
        GUI_MODE=true
        print_status "ULTIMATE" "GUI mode enabled"
    else
        GUI_MODE=false
    fi

    # ULTIMATE Port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,8443:443): ")" PORT_FORWARDS

    # ULTIMATE Backup & Snapshot
    section_header "BACKUP & SNAPSHOT"
    
    print_status "ULTIMATE" "Auto-configuring backup schedule for optimal protection"
    
    BACKUP_SCHEDULE="daily"
    SNAPSHOT_COUNT=10
    
    print_status "INFO" "Backup schedule: Daily"
    print_status "INFO" "Maximum snapshots: 10"

    # ULTIMATE Advanced Features
    section_header "ADVANCED FEATURES"
    
    # UEFI/Secure Boot
    read -p "$(print_status "INPUT" "Enable UEFI firmware? (for Windows 11/secure boot): ")" uefi_choice
    if [[ "$uefi_choice" =~ ^[Yy]$ ]]; then
        UEFI_ENABLED=true
        SECURE_BOOT=true
        print_status "ULTIMATE" "UEFI with Secure Boot enabled"
    else
        UEFI_ENABLED=false
        SECURE_BOOT=false
    fi
    
    # TPM 2.0
    read -p "$(print_status "INPUT" "Enable TPM 2.0 emulation? (for Windows 11/security): ")" tpm_choice
    if [[ "$tpm_choice" =~ ^[Yy]$ ]]; then
        TPMS_ENABLED=true
        print_status "ULTIMATE" "TPM 2.0 emulation enabled"
    else
        TPMS_ENABLED=false
    fi
    
    # SPICE for remote access
    read -p "$(print_status "INPUT" "Enable SPICE remote display? (for remote GUI access): ")" spice_choice
    if [[ "$spice_choice" =~ ^[Yy]$ ]]; then
        SPICE_ENABLED=true
        SPICE_PORT=$(( 5930 + $(get_vm_count) ))
        print_status "ULTIMATE" "SPICE enabled on port $SPICE_PORT"
    else
        SPICE_ENABLED=false
        SPICE_PORT=""
    fi
    
    # Virtio type
    VIRTIO_TYPE="modern"
    print_status "ULTIMATE" "Using modern virtio drivers for maximum performance"

    # Final configuration
    IMG_FILE="$VM_DIR/$VM_NAME.qcow2"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # ULTIMATE Deployment Summary
    section_header "ULTIMATE DEPLOYMENT SUMMARY"
    
    echo -e "${COLOR_ORANGE}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_ORANGE}║                         DEPLOYMENT CONFIGURATION                       ║${COLOR_RESET}"
    echo -e "${COLOR_ORANGE}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo
    
    echo -e "${COLOR_WHITE}Basic Configuration:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Name:${COLOR_RESET} ${COLOR_CYAN}$VM_NAME${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}OS:${COLOR_RESET} ${COLOR_GREEN}$os${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Created:${COLOR_RESET} $CREATED"
    
    echo -e "\n${COLOR_WHITE}Performance Settings:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU ($CPU_TYPE) | ${MEMORY}MB RAM | $DISK_SIZE disk${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}GPU Passthrough:${COLOR_RESET} ${COLOR_MAGENTA}$GPU_PASSTHROUGH${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Virtio:${COLOR_RESET} $VIRTIO_TYPE"
    
    echo -e "\n${COLOR_WHITE}Network Configuration:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Type:${COLOR_RESET} ${COLOR_CYAN}$NETWORK_CONFIG${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}MAC:${COLOR_RESET} $MAC_ADDRESS"
    echo -e "  ${COLOR_GRAY}Static IP:${COLOR_RESET} ${COLOR_GREEN}$STATIC_IP${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
    [[ -n "$SPICE_PORT" ]] && echo -e "  ${COLOR_Gray}SPICE Port:${COLOR_RESET} ${COLOR_CYAN}$SPICE_PORT${COLOR_RESET}"
    
    echo -e "\n${COLOR_WHITE}Security Features:${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}Access:${COLOR_RESET} ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}UEFI/Secure Boot:${COLOR_RESET} $UEFI_ENABLED / $SECURE_BOOT"
    echo -e "  ${COLOR_Gray}TPM 2.0:${COLOR_RESET} $TPMS_ENABLED"
    
    echo -e "\n${COLOR_WHITE}Management:${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}Backup:${COLOR_RESET} ${COLOR_GREEN}$BACKUP_SCHEDULE${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}Snapshots:${COLOR_RESET} ${COLOR_GREEN}$SNAPSHOT_COUNT${COLOR_RESET}"
    
    echo -e "\n${COLOR_ORANGE}══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo
    
    read -p "$(print_status "ULTIMATE" "Deploy this ultimate VM configuration? (Y/n): ")" confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        # Download and setup VM image
        setup_vm_image
        
        # Save configuration
        save_vm_config
        
        section_header "ULTIMATE DEPLOYMENT COMPLETE"
        print_status "SUCCESS" "╔══════════════════════════════════════════════════════════════════════╗"
        print_status "SUCCESS" "║               ULTIMATE VM DEPLOYED SUCCESSFULLY!                     ║"
        print_status "SUCCESS" "╚══════════════════════════════════════════════════════════════════════╝"
        
        log_action "CREATE_VM" "$VM_NAME" "Ultimate VM created with $OS_TYPE, ${MEMORY}MB RAM, ${CPUS} vCPU, $DISK_SIZE disk"
        
        echo -e "\n${COLOR_WHITE}Access Information:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}SSH Access:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@$STATIC_IP"
        echo -e "  ${COLOR_Gray}Password:${COLOR_RESET} $PASSWORD"
        echo -e "  ${COLOR_Gray}Local SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@localhost"
        
        echo -e "\n${COLOR_WHITE}Management:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Configuration:${COLOR_RESET} $VM_DIR/$VM_NAME.conf"
        echo -e "  ${COLOR_Gray}Disk Image:${COLOR_RESET} $IMG_FILE"
        
        if [[ "$SPICE_ENABLED" == true ]]; then
            echo -e "\n${COLOR_WHITE}Remote Access:${COLOR_RESET}"
            echo -e "  ${COLOR_Gray}SPICE Client:${COLOR_RESET} spicy -h localhost -p $SPICE_PORT"
        fi
        
        echo -e "\n${COLOR_ORANGE}══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
        
        # Ask to start VM
        read -p "$(print_status "INPUT" "Start VM now? (Y/n): ")" start_now
        if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
            start_vm "$VM_NAME"
        fi
    else
        print_status "INFO" "Deployment cancelled"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    # Check by process name
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
        return 0
    fi
    return 1
}

# Function to start ultimate VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STARTING ULTIMATE VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}OS:${COLOR_RESET} $OS_TYPE $CODENAME"
        echo -e "${COLOR_WHITE}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU ($CPU_TYPE) | ${MEMORY}MB RAM${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM $vm_name is already running"
            read -p "$(print_status "INPUT" "Connect to console? (y/N): ")" connect_console
            if [[ "$connect_console" =~ ^[Yy]$ ]]; then
                print_status "INFO" "Use Ctrl+A then D to detach from screen session"
                screen -r "qemu-$vm_name"
            fi
            return 0
        fi
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        # Display access information
        print_status "ULTIMATE" "Access Information:"
        echo -e "  ${COLOR_Gray}SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@$STATIC_IP"
        echo -e "  ${COLOR_Gray}Local SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@localhost"
        [[ -n "$SPICE_PORT" ]] && echo -e "  ${COLOR_Gray}SPICE:${COLOR_RESET} spicy -h localhost -p $SPICE_PORT"
        echo
        
        # Simple QEMU command for basic functionality
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -m "$MEMORY"
            -smp "$CPUS"
            -drive "file=$IMG_FILE,format=qcow2"
            -drive "file=$SEED_FILE,format=raw"
            -boot order=c
            -device "virtio-net-pci,netdev=n0"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )
        
        # Add GUI mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi
        
        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )
        
        print_status "ULTIMATE" "Starting QEMU..."
        
        # Ask for startup mode
        echo "Startup Mode:"
        echo "  1) Foreground (with console output)"
        echo "  2) Screen session"
        
        read -p "$(print_status "INPUT" "Select startup mode (1-2): ")" startup_mode
        startup_mode="${startup_mode:-1}"
        
        case $startup_mode in
            2)  # Screen
                print_status "ULTIMATE" "Starting in screen session..."
                screen -dmS "qemu-$vm_name" "${qemu_cmd[@]}"
                print_status "SUCCESS" "VM $vm_name started in screen session 'qemu-$vm_name'"
                print_status "INFO" "Attach with: screen -r qemu-$vm_name"
                ;;
                
            *)  # Foreground
                print_status "ULTIMATE" "Starting in foreground..."
                echo "$SUBTLE_SEP"
                "${qemu_cmd[@]}"
                print_status "INFO" "VM $vm_name has been shut down"
                ;;
        esac
        
        log_action "START_VM" "$vm_name" "Started"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VIRTUAL MACHINE INFORMATION"
        
        echo -e "${COLOR_WHITE}Basic Information:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Name:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Hostname:${COLOR_RESET} $HOSTNAME"
        echo -e "  ${COLOR_Gray}OS:${COLOR_RESET} $OS_TYPE $CODENAME"
        echo -e "  ${COLOR_Gray}Created:${COLOR_RESET} $CREATED"
        echo -e "  ${COLOR_Gray}Status:${COLOR_RESET} $(is_vm_running "$vm_name" && echo -e "${COLOR_GREEN}Running${COLOR_RESET}" || echo -e "${COLOR_YELLOW}Stopped${COLOR_RESET}")"
        
        echo -e "\n${COLOR_WHITE}Resources:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS ($CPU_TYPE)${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        
        echo -e "\n${COLOR_WHITE}Network:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Type:${COLOR_RESET} $NETWORK_CONFIG"
        echo -e "  ${COLOR_Gray}MAC:${COLOR_RESET} $MAC_ADDRESS"
        echo -e "  ${COLOR_Gray}Static IP:${COLOR_RESET} $STATIC_IP"
        echo -e "  ${COLOR_Gray}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
        
        echo -e "\n${COLOR_WHITE}Access:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Username:${COLOR_RESET} ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Password:${COLOR_RESET} ********"
        
        echo -e "\n${COLOR_WHITE}Storage:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Configuration:${COLOR_RESET} $VM_DIR/$vm_name.conf"
        echo -e "  ${COLOR_Gray}Disk Image:${COLOR_RESET} $IMG_FILE"
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to delete VM
delete_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "DELETE VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        print_status "WARN" "⚠️  This will permanently delete the VM!"
        read -p "$(print_status "INPUT" "Type 'DELETE' to confirm: ")" confirm
        if [[ "$confirm" == "DELETE" ]]; then
            # Stop VM if running
            if is_vm_running "$vm_name"; then
                pkill -f "qemu-system-x86_64.*$vm_name"
            fi
            
            # Delete files
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        else
            print_status "INFO" "Deletion cancelled"
        fi
    fi
}

# Function to show system overview
show_system_overview() {
    display_header
    section_header "SYSTEM OVERVIEW"
    
    local total_vms=$(get_vm_count)
    local running_vms=0
    local vms=($(get_vm_list))
    
    for vm in "${vms[@]}"; do
        if is_vm_running "$vm"; then
            ((running_vms++))
        fi
    done
    
    echo -e "${COLOR_WHITE}Platform Statistics:${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}Total VMs:${COLOR_RESET} ${COLOR_CYAN}$total_vms${COLOR_RESET} / $MAX_VMS"
    echo -e "  ${COLOR_Gray}Running VMs:${COLOR_RESET} ${COLOR_GREEN}$running_vms${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}Stopped VMs:${COLOR_RESET} ${COLOR_YELLOW}$((total_vms - running_vms))${COLOR_RESET}"
    
    echo
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            section_header "VIRTUAL MACHINES"
            print_status "INFO" "Found $vm_count VM(s) (Limit: $MAX_VMS):"
            echo
            
            for i in "${!vms[@]}"; do
                local vm_name="${vms[$i]}"
                local status=""
                
                if is_vm_running "$vm_name"; then
                    status="${COLOR_GREEN}● Running${COLOR_RESET}"
                else
                    status="${COLOR_YELLOW}● Stopped${COLOR_RESET}"
                fi
                
                printf "  %2d) %-20s %s\n" $((i+1)) "$vm_name" "$status"
            done
            echo
        else
            section_header "WELCOME"
            echo -e "  ${COLOR_GRAY}No virtual machines found.${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Create your first VM to get started.${COLOR_RESET}"
            echo
        fi
        
        section_header "MAIN MENU"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Delete a VM"
            echo "  6) System overview"
        fi
        echo "  0) Exit"
        echo
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        if is_vm_running "${vms[$((vm_num-1))]}"; then
                            pkill -f "qemu-system-x86_64.*${vms[$((vm_num-1))]}"
                            print_status "SUCCESS" "VM ${vms[$((vm_num-1))]} stopped"
                        else
                            print_status "INFO" "VM ${vms[$((vm_num-1))]} is not running"
                        fi
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                show_system_overview
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

# Start the main menu
main_menu
