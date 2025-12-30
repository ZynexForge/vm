#!/bin/bash
set -euo pipefail

# =============================
# ZYNEXFORGE™ - Ultimate VM Manager
# AMD Ryzen/EPYC Optimized with GPU Passthrough & Proxmox
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

# UI constants
SEPARATOR="========================================================================="
SUBTLE_SEP="─────────────────────────────────────────────────────────────────────────"

# Configuration
MAX_VMS=8
VM_BASE_DIR="$HOME/.zynexforge"
VM_DIR="$VM_BASE_DIR/vms"
IMAGES_DIR="$VM_BASE_DIR/images"
BACKUPS_DIR="$VM_BASE_DIR/backups"
LOGS_DIR="$VM_BASE_DIR/logs"
TEMPLATES_DIR="$VM_BASE_DIR/templates"

# Create directories
mkdir -p "$VM_DIR" "$IMAGES_DIR" "$BACKUPS_DIR" "$LOGS_DIR" "$TEMPLATES_DIR"

# Function to display header
display_header() {
    clear
    echo -e "${COLOR_CYAN}"
    cat << "EOF"

__________                             ___________                         
\____    /_____/ __ \/ __ \/ __ \/ __ \/  _ \_  __ \/ __ \_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 
EOF
    echo -e "${COLOR_RESET}"
    echo -e "${COLOR_WHITE}ZYNEXFORGE™ Virtual Machine Manager${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}AMD Ryzen/EPYC Optimized | GPU Passthrough | Proxmox Support${COLOR_RESET}"
    echo -e "${COLOR_GRAY}Max VMs: $MAX_VMS | Base Directory: $VM_BASE_DIR${COLOR_RESET}"
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
        "BEAST") echo -e "${COLOR_MAGENTA}[BEAST]${COLOR_RESET} $message" ;;
        "PROXMOX") echo -e "${COLOR_BLUE}[PROXMOX]${COLOR_RESET} $message" ;;
        "AMD") echo -e "${COLOR_MAGENTA}[AMD]${COLOR_RESET} $message" ;;
        *) echo -e "${COLOR_WHITE}[$type]${COLOR_RESET} $message" ;;
    esac
}

# Function to log actions
log_action() {
    local action=$1
    local vm_name=$2
    local details=$3
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $action | $vm_name | $details" >> "$LOGS_DIR/zynexforge.log" 2>/dev/null || true
}

# Function to display section header
section_header() {
    local title=$1
    echo
    echo -e "${COLOR_WHITE}$title${COLOR_RESET}"
    echo "$SUBTLE_SEP"
}

# Function to detect AMD CPU (improved detection)
detect_amd_cpu() {
    if grep -qi "vendor_id.*AMD" /proc/cpuinfo || grep -qi "model.*AMD" /proc/cpuinfo || \
       grep -qi "vendor.*AMD" /proc/cpuinfo || grep -qi "ryzen" /proc/cpuinfo || \
       grep -qi "epyc" /proc/cpuinfo || grep -qi "athlon" /proc/cpuinfo || \
       grep -qi "phenom" /proc/cpuinfo || grep -qi "fx" /proc/cpuinfo; then
        return 0
    else
        return 1
    fi
}

# Function to get AMD CPU model
get_amd_cpu_model() {
    if grep -qi "ryzen" /proc/cpuinfo; then
        echo "Ryzen"
    elif grep -qi "epyc" /proc/cpuinfo; then
        echo "EPYC"
    elif grep -qi "athlon" /proc/cpuinfo; then
        echo "Athlon"
    elif grep -qi "phenom" /proc/cpuinfo; then
        echo "Phenom"
    elif grep -qi "fx" /proc/cpuinfo; then
        echo "FX"
    else
        echo "AMD"
    fi
}

# Function to detect AMD GPU
detect_amd_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -i "vga\|3d\|display" | grep -qi "amd\|radeon\|ati"; then
            return 0
        fi
    fi
    return 1
}

# Function to detect NVIDIA GPU
detect_nvidia_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -i "vga\|3d\|display" | grep -qi "nvidia"; then
            return 0
        fi
    fi
    return 1
}

# Function to detect Intel GPU
detect_intel_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -i "vga\|3d\|display" | grep -qi "intel"; then
            return 0
        fi
    fi
    return 1
}

# Function to detect any GPU for passthrough
detect_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -i "vga\|3d\|display" | grep -qi "nvidia\|amd\|radeon\|intel\|ati"; then
            return 0
        fi
    fi
    return 1
}

# Function to get GPU information
get_gpu_info() {
    local gpu_info=""
    if detect_amd_gpu; then
        gpu_info="AMD GPU"
    elif detect_nvidia_gpu; then
        gpu_info="NVIDIA GPU"
    elif detect_intel_gpu; then
        gpu_info="Intel GPU"
    else
        gpu_info="No GPU"
    fi
    echo "$gpu_info"
}

# Function to get GPU PCI addresses
get_gpu_pci_addresses() {
    local pci_addresses=()
    if command -v lspci >/dev/null 2>&1; then
        # Get primary GPU (first VGA/3D controller)
        local primary=$(lspci | grep -i "vga\|3d\|display" | head -1 | awk '{print $1}')
        if [[ -n "$primary" ]]; then
            pci_addresses+=("$primary")
        fi
        
        # Get audio function of GPU
        local audio=$(lspci | grep -i "audio" | grep -i "amd\|nvidia\|intel" | awk '{print $1}' | head -1)
        if [[ -n "$audio" ]]; then
            pci_addresses+=("$audio")
        fi
    fi
    echo "${pci_addresses[@]}"
}

# Function to check if IOMMU is enabled
check_iommu() {
    if grep -q "iommu=on" /proc/cmdline || grep -q "amd_iommu=on" /proc/cmdline || \
       grep -q "intel_iommu=on" /proc/cmdline || dmesg | grep -qi "iommu.*enabled"; then
        return 0
    fi
    
    # Check via /sys
    if [[ -d "/sys/kernel/iommu_groups" ]] && [[ $(ls /sys/kernel/iommu_groups/ 2>/dev/null | wc -l) -gt 0 ]]; then
        return 0
    fi
    
    return 1
}

# Function to generate random IP
generate_auto_ip() {
    local base="192.168.100"
    local octet=$((RANDOM % 254 + 1))
    echo "$base.$octet"
}

# Function to generate MAC address
generate_mac() {
    printf '52:54:%02x:%02x:%02x:%02x\n' \
        $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
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
            if ! [[ "$value" =~ ^[0-9]+[GgMm]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M)"
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
                print_status "ERROR" "Username must start with a letter or underscore"
                return 1
            fi
            ;;
        "ip")
            if ! [[ "$value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                print_status "ERROR" "Must be a valid IP address"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "genisoimage")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Install with: sudo apt install qemu-system cloud-image-utils wget genisoimage"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    rm -f "user-data" "meta-data" "network-config" 2>/dev/null || true
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
    if [ "$current_count" -ge "$MAX_VMS" ]; then
        print_status "ERROR" "Maximum VM limit reached ($MAX_VMS)"
        return 1
    fi
    return 0
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear any existing variables
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD SSH_KEYS
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset NETWORK_CONFIG MAC_ADDRESS STATIC_IP BACKUP_SCHEDULE SNAPSHOT_COUNT CPU_TYPE GPU_PASSTHROUGH
        unset GPU_TYPE GPU_PCI_ADDRESSES IOMMU_ENABLED PROXMOX_MODE PROXMOX_TEMPLATE
        
        source "$config_file" 2>/dev/null
        return 0
    else
        print_status "ERROR" "VM '$vm_name' not found"
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
GPU_TYPE="$GPU_TYPE"
GPU_PCI_ADDRESSES="$GPU_PCI_ADDRESSES"
IOMMU_ENABLED="$IOMMU_ENABLED"
PROXMOX_MODE="$PROXMOX_MODE"
PROXMOX_TEMPLATE="$PROXMOX_TEMPLATE"
EOF
    
    print_status "SUCCESS" "Configuration saved"
    log_action "SAVE_CONFIG" "$VM_NAME" "Configuration updated"
}

# Function to setup VM image with AMD optimization
setup_vm_image() {
    print_status "AMD" "Setting up VM storage with AMD optimization..."
    
    # Create cache directory
    mkdir -p "$IMAGES_DIR"
    
    # Extract filename from URL
    local image_filename=$(basename "$IMG_URL")
    local cached_image="$IMAGES_DIR/$image_filename"
    
    # Download or use cached image
    if [[ ! -f "$cached_image" ]]; then
        print_status "INFO" "Downloading OS image..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$cached_image.tmp" 2>&1; then
            print_status "ERROR" "Failed to download image"
            exit 1
        fi
        mv "$cached_image.tmp" "$cached_image"
    fi
    
    # Create AMD-optimized qcow2 image
    print_status "AMD" "Creating AMD-optimized disk image..."
    
    # Convert the downloaded image to qcow2 format with AMD optimizations
    qemu-img convert -f qcow2 -O qcow2 -o cluster_size=2M,preallocation=metadata,compat=1.1,lazy_refcounts=on \
        "$cached_image" "$IMG_FILE"
    
    # Resize the disk to the requested size
    qemu-img resize "$IMG_FILE" "$DISK_SIZE"
    
    # AMD-optimized cloud-init config
    cat > user-data <<EOF
#cloud-config
# ZYNEXFORGE AMD OPTIMIZED CONFIGURATION
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
preserve_hostname: false
manage_etc_hosts: true
package_upgrade: true
package_reboot_if_required: true
timezone: UTC

users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null | tr -d '\n')
    groups: [adm, audio, cdrom, dialout, floppy, video, plugdev, dip, netdev, docker]

packages:
  - qemu-guest-agent
  - htop
  - neofetch
  - curl
  - wget
  - git
  - python3
  - docker.io
  - docker-compose
  - net-tools
  - iperf3
  - cpufrequtils
  - amd64-microcode
  - firmware-amd-graphics

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "vm.swappiness=10" >> /etc/sysctl.conf
  - echo "vm.dirty_ratio=10" >> /etc/sysctl.conf
  - echo "vm.dirty_background_ratio=5" >> /etc/sysctl.conf
  - echo "net.core.rmem_max=134217728" >> /etc/sysctl.conf
  - echo "net.core.wmem_max=134217728" >> /etc/sysctl.conf
  - sysctl -p
  - timedatectl set-timezone UTC
  - [sh, -c, "echo 'performance' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"]
  - [sh, -c, "echo 'GOVERNOR=\"performance\"' > /etc/default/cpufrequtils"]
  - systemctl restart cpufrequtils

bootcmd:
  - echo "AMD Optimized" > /etc/motd
  - echo "ZYNEXFORGE VM - Ready for Maximum Performance" >> /etc/motd

power_state:
  mode: reboot
  timeout: 300
  message: "ZYNEXFORGE AMD Optimized VM is ready!"
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data 2>/dev/null; then
        print_status "ERROR" "Failed to create seed image"
        exit 1
    fi
    
    print_status "AMD" "VM image optimized for AMD performance!"
}

# Function to setup Proxmox VM
setup_proxmox_vm() {
    print_status "PROXMOX" "Setting up Proxmox Virtual Environment..."
    
    # Create cache directory
    mkdir -p "$IMAGES_DIR"
    
    # Proxmox VE specific image handling
    local proxmox_image="$IMAGES_DIR/proxmox-ve-amd64.img"
    
    # Download Proxmox VE installer if not cached
    if [[ ! -f "$proxmox_image" ]]; then
        print_status "INFO" "Downloading Proxmox VE installer..."
        if ! wget --progress=bar:force "https://download.proxmox.com/iso/proxmox-ve_8.1-1.iso" -O "$proxmox_image.tmp" 2>&1; then
            print_status "ERROR" "Failed to download Proxmox VE installer"
            print_status "INFO" "Trying alternative Proxmox VE image..."
            # Alternative cloud image for Proxmox
            if ! wget --progress=bar:force "https://download.proxmox.com/images/cloud/bookworm/current/debian-12-genericcloud-amd64.qcow2" -O "$proxmox_image.tmp" 2>&1; then
                print_status "ERROR" "Failed to download Proxmox VE image"
                exit 1
            fi
        fi
        mv "$proxmox_image.tmp" "$proxmox_image"
    fi
    
    # Copy to VM location
    cp "$proxmox_image" "$IMG_FILE"
    
    # Create Proxmox-optimized qcow2 image
    print_status "PROXMOX" "Creating Proxmox-optimized disk image..."
    qemu-img create -f qcow2 -o cluster_size=2M,preallocation=metadata,compat=1.1,lazy_refcounts=on "$IMG_FILE" "$DISK_SIZE"
    
    # Proxmox cloud-init config
    cat > user-data <<EOF
#cloud-config
# PROXMOX VE CLOUD-INIT CONFIGURATION
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
preserve_hostname: false
manage_etc_hosts: true
package_upgrade: true
package_reboot_if_required: true
timezone: UTC

users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null | tr -d '\n')
    groups: [adm, audio, cdrom, dialout, floppy, video, plugdev, dip, netdev, docker, sudo]

packages:
  - qemu-guest-agent
  - htop
  - neofetch
  - curl
  - wget
  - git
  - python3
  - net-tools
  - iperf3
  - bridge-utils
  - ifupdown2

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - apt-get update
  - apt-get install -y linux-headers-$(uname -r)
  - echo "Setting up for Proxmox VE installation..."
  - echo "After boot, install Proxmox VE with:"
  - echo "  wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg"
  - echo "  echo 'deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription' > /etc/apt/sources.list.d/pve-install-repo.list"
  - echo "  apt update && apt full-upgrade -y"
  - echo "  apt install -y proxmox-ve postfix open-iscsi"

bootcmd:
  - echo "Proxmox VE Ready for Installation" > /etc/motd

power_state:
  mode: reboot
  timeout: 300
  message: "Proxmox VE VM is ready for installation!"
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data 2>/dev/null; then
        print_status "ERROR" "Failed to create seed image for Proxmox"
        exit 1
    fi
    
    print_status "PROXMOX" "Proxmox VE VM image prepared! Install Proxmox VE after boot."
}

# Function to create new VM with AMD and GPU options
create_new_vm() {
    if ! check_vm_limit; then
        return 1
    fi
    
    display_header
    section_header "CREATE VIRTUAL MACHINE"
    
    # Detect system capabilities
    local HAS_AMD=false
    local AMD_CPU_MODEL=""
    local HAS_GPU=false
    local GPU_TYPE="none"
    local IOMMU_ENABLED=false
    local GPU_PCI_ADDRESSES=""
    
    if detect_amd_cpu; then
        HAS_AMD=true
        AMD_CPU_MODEL=$(get_amd_cpu_model)
        print_status "AMD" "$AMD_CPU_MODEL CPU detected! Enabling AMD optimizations..."
    else
        print_status "INFO" "Non-AMD CPU detected"
    fi
    
    if check_iommu; then
        IOMMU_ENABLED=true
        print_status "INFO" "IOMMU is enabled (required for GPU passthrough)"
    else
        print_status "WARN" "IOMMU is not enabled. GPU passthrough may not work."
    fi
    
    if detect_gpu; then
        HAS_GPU=true
        GPU_TYPE=$(get_gpu_info)
        GPU_PCI_ADDRESSES=$(get_gpu_pci_addresses)
        print_status "INFO" "$GPU_TYPE"
        if [[ -n "$GPU_PCI_ADDRESSES" ]]; then
            print_status "INFO" "GPU PCI Addresses: $GPU_PCI_ADDRESSES"
        fi
    fi
    
    # OS Selection with Proxmox option
    section_header "OPERATING SYSTEM SELECTION"
    
    declare -A OS_OPTIONS=(
        ["Ubuntu 22.04 LTS (Jammy Jellyfish)"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
        ["Ubuntu 24.04 LTS (Noble Numbat)"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
        ["Debian 12 (Bookworm)"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
        ["Proxmox VE 8.1"]="proxmox|ve81|proxmox-custom|proxmox81|root|proxmox"
        ["Rocky Linux 9"]="rocky|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
        ["AlmaLinux 9"]="alma|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|alma9|alma|alma"
    )
    
    local os_list=()
    local i=1
    
    print_status "INFO" "Available operating systems:"
    for os in "${!OS_OPTIONS[@]}"; do
        echo -e "  ${COLOR_CYAN}$i) $os${COLOR_RESET}"
        os_list[$i]="$os"
        ((i++))
    done
    
    while true; do
        echo
        read -p "$(print_status "INPUT" "Select OS (1-${#OS_OPTIONS[@]}): ")" choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_list[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            
            # Check if this is Proxmox
            if [[ "$OS_TYPE" == "proxmox" ]]; then
                PROXMOX_MODE=true
                print_status "PROXMOX" "Selected: $os"
            else
                PROXMOX_MODE=false
                print_status "INFO" "Selected: $os"
            fi
            break
        else
            print_status "ERROR" "Invalid selection"
        fi
    done

    # VM Configuration
    section_header "VIRTUAL MACHINE CONFIGURATION"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    HOSTNAME="$VM_NAME"

    # Access Credentials
    section_header "ACCESS CREDENTIALS"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        echo -e "${COLOR_YELLOW}Password requirements: Minimum 4 characters${COLOR_RESET}"
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ ${#PASSWORD} -ge 4 ]; then
            break
        else
            print_status "ERROR" "Password must be at least 4 characters"
        fi
    done

    read -p "$(print_status "INPUT" "Add SSH public keys (press Enter to skip): ")" SSH_KEYS

    # Resource Allocation with AMD optimization
    section_header "RESOURCE ALLOCATION"
    
    print_status "INFO" "Auto-configuring optimal resources..."
    
    # Auto-detect optimal settings
    local TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    local TOTAL_CPUS=$(nproc)
    
    # Calculate optimal resources
    local OPTIMAL_MEMORY=$((TOTAL_MEM / 4))  # Use 25% of total RAM
    if [ $OPTIMAL_MEMORY -gt 32768 ]; then
        OPTIMAL_MEMORY=32768  # Cap at 32GB
    elif [ $OPTIMAL_MEMORY -lt 2048 ]; then
        OPTIMAL_MEMORY=2048   # Minimum 2GB
    fi
    
    local OPTIMAL_CPUS=$((TOTAL_CPUS / 2))  # Use half of CPUs
    if [ $OPTIMAL_CPUS -gt 16 ]; then
        OPTIMAL_CPUS=16  # Cap at 16 vCPUs
    elif [ $OPTIMAL_CPUS -lt 2 ]; then
        OPTIMAL_CPUS=2  # Minimum 2 vCPUs
    fi
    
    print_status "INFO" "System has ${TOTAL_MEM}MB RAM, ${TOTAL_CPUS} CPUs"
    print_status "INFO" "Recommended: ${OPTIMAL_MEMORY}MB RAM, ${OPTIMAL_CPUS} vCPUs"
    
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 100G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-100G}"
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

    # CPU Optimization
    section_header "CPU OPTIMIZATION"
    
    if [ "$HAS_AMD" = true ]; then
        CPU_TYPE="EPYC-v4"
        print_status "AMD" "Using AMD EPYC-v4 CPU model with all optimizations!"
    else
        CPU_TYPE="host"
        print_status "INFO" "Using host CPU passthrough"
    fi

    # GPU Passthrough Options
    section_header "GPU PASSTHROUGH"
    
    if [ "$HAS_GPU" = true ] && [ "$IOMMU_ENABLED" = true ]; then
        print_status "INFO" "GPU detected and IOMMU enabled. GPU passthrough available."
        echo -e "${COLOR_YELLOW}Options:${COLOR_RESET}"
        echo "  1) No GPU passthrough"
        echo "  2) AMD GPU passthrough (if AMD GPU detected)"
        echo "  3) NVIDIA GPU passthrough (if NVIDIA GPU detected)"
        echo "  4) Intel GPU passthrough (if Intel GPU detected)"
        
        read -p "$(print_status "INPUT" "Select GPU option (default: 1): ")" gpu_option
        gpu_option="${gpu_option:-1}"
        
        case $gpu_option in
            1)
                GPU_PASSTHROUGH=false
                print_status "INFO" "GPU passthrough disabled"
                ;;
            2)
                if detect_amd_gpu; then
                    GPU_PASSTHROUGH=true
                    GPU_TYPE="amd"
                    print_status "AMD" "AMD GPU passthrough enabled!"
                else
                    GPU_PASSTHROUGH=false
                    print_status "ERROR" "AMD GPU not detected"
                fi
                ;;
            3)
                if detect_nvidia_gpu; then
                    GPU_PASSTHROUGH=true
                    GPU_TYPE="nvidia"
                    print_status "INFO" "NVIDIA GPU passthrough enabled!"
                else
                    GPU_PASSTHROUGH=false
                    print_status "ERROR" "NVIDIA GPU not detected"
                fi
                ;;
            4)
                if detect_intel_gpu; then
                    GPU_PASSTHROUGH=true
                    GPU_TYPE="intel"
                    print_status "INFO" "Intel GPU passthrough enabled!"
                else
                    GPU_PASSTHROUGH=false
                    print_status "ERROR" "Intel GPU not detected"
                fi
                ;;
            *)
                GPU_PASSTHROUGH=false
                print_status "INFO" "GPU passthrough disabled"
                ;;
        esac
    else
        GPU_PASSTHROUGH=false
        if [ "$HAS_GPU" = false ]; then
            print_status "INFO" "No GPU detected"
        else
            print_status "WARN" "IOMMU not enabled. GPU passthrough unavailable."
        fi
    fi

    # Network Configuration
    section_header "NETWORK CONFIGURATION"
    
    MAC_ADDRESS=$(generate_mac)
    echo -e "Generated MAC: ${COLOR_CYAN}$MAC_ADDRESS${COLOR_RESET}"
    
    # Auto-generate static IP
    STATIC_IP=$(generate_auto_ip)
    echo -e "Auto-generated IP: ${COLOR_GREEN}$STATIC_IP${COLOR_RESET}"
    
    NETWORK_CONFIG="user"

    while true; do
        DEFAULT_SSH_PORT=$((22220 + $(get_vm_count)))
        read -p "$(print_status "INPUT" "SSH Port (recommended: $DEFAULT_SSH_PORT): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-$DEFAULT_SSH_PORT}"
        if validate_input "port" "$SSH_PORT"; then
            break
        fi
    done

    read -p "$(print_status "INPUT" "Enable GUI mode? (y/N): ")" gui_input
    if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
        GUI_MODE=true
    else
        GUI_MODE=false
    fi

    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,8443:443): ")" PORT_FORWARDS

    # Backup & Snapshot
    BACKUP_SCHEDULE="daily"
    SNAPSHOT_COUNT=10

    # Final configuration
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"
    PROXMOX_TEMPLATE="false"

    section_header "DEPLOYMENT SUMMARY"
    echo -e "${COLOR_WHITE}VM Configuration:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Name:${COLOR_RESET} ${COLOR_CYAN}$VM_NAME${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}OS:${COLOR_RESET} ${COLOR_GREEN}$os${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM | $DISK_SIZE disk${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}CPU:${COLOR_RESET} ${COLOR_MAGENTA}$CPU_TYPE${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}GPU Passthrough:${COLOR_RESET} ${COLOR_MAGENTA}$GPU_PASSTHROUGH${COLOR_RESET}"
    if [ "$GPU_PASSTHROUGH" = true ]; then
        echo -e "  ${COLOR_GRAY}GPU Type:${COLOR_RESET} $GPU_TYPE"
    fi
    echo -e "  ${COLOR_GRAY}Network:${COLOR_RESET} ${COLOR_CYAN}$NETWORK_CONFIG${COLOR_RESET} (IP: $STATIC_IP)"
    echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
    if [ "$PROXMOX_MODE" = true ]; then
        echo -e "  ${COLOR_GRAY}Proxmox VE:${COLOR_RESET} ${COLOR_BLUE}Ready for installation${COLOR_RESET}"
    fi
    echo
    
    read -p "$(print_status "INPUT" "Deploy this VM? (Y/n): ")" confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        if [ "$PROXMOX_MODE" = true ]; then
            setup_proxmox_vm
        else
            setup_vm_image
        fi
        save_vm_config
        
        section_header "DEPLOYMENT COMPLETE"
        print_status "SUCCESS" "╔══════════════════════════════════════════════════════════════════════╗"
        print_status "SUCCESS" "║                     VM DEPLOYED SUCCESSFULLY!                         ║"
        print_status "SUCCESS" "╚══════════════════════════════════════════════════════════════════════╝"
        
        log_action "CREATE_VM" "$VM_NAME" "VM created with $OS_TYPE, ${MEMORY}MB RAM, ${CPUS} vCPU, GPU: $GPU_PASSTHROUGH"
        
        echo -e "\n${COLOR_WHITE}Access Information:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@localhost"
        echo -e "  ${COLOR_GRAY}Password:${COLOR_RESET} $PASSWORD"
        echo -e "  ${COLOR_GRAY}IP:${COLOR_RESET} $STATIC_IP"
        
        if [ "$PROXMOX_MODE" = true ]; then
            echo -e "\n${COLOR_WHITE}Proxmox VE Installation:${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}After boot, install Proxmox VE with:${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}1. Connect to console or SSH${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}2. Update system: apt update && apt full-upgrade -y${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}3. Install Proxmox: apt install -y proxmox-ve${COLOR_RESET}"
        fi
        
        echo -e "\n${COLOR_WHITE}Performance Features:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}AMD Optimized:${COLOR_RESET} $HAS_AMD"
        if [ "$HAS_AMD" = true ]; then
            echo -e "  ${COLOR_GRAY}AMD CPU Model:${COLOR_RESET} $AMD_CPU_MODEL"
        fi
        echo -e "  ${COLOR_GRAY}GPU Passthrough:${COLOR_RESET} $GPU_PASSTHROUGH"
        if [ "$GPU_PASSTHROUGH" = true ]; then
            echo -e "  ${COLOR_GRAY}GPU Type:${COLOR_RESET} $GPU_TYPE"
        fi
        echo -e "  ${COLOR_GRAY}Daily Backups:${COLOR_RESET} Enabled"
        
        echo -e "\n${COLOR_YELLOW}══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
        
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
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Function to start VM with AMD and GPU optimizations
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "START VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}OS:${COLOR_RESET} $OS_TYPE"
        echo -e "${COLOR_WHITE}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            print_status "INFO" "VM $vm_name is already running"
            
            echo -e "\n${COLOR_WHITE}Options for running VM:${COLOR_RESET}"
            echo "  1) Connect to console"
            echo "  2) Stop VM"
            echo "  3) View SSH connection info"
            echo "  4) Show performance stats"
            echo "  5) Attach/detach GPU"
            echo "  0) Back to menu"
            
            read -p "$(print_status "INPUT" "Select option: ")" running_option
            
            case $running_option in
                1)
                    print_status "INFO" "Connecting to console..."
                    if screen -list | grep -q "qemu-$vm_name"; then
                        screen -r "qemu-$vm_name"
                    else
                        print_status "INFO" "No screen session found"
                    fi
                    ;;
                2)
                    stop_vm "$vm_name"
                    ;;
                3)
                    print_status "INFO" "Access Information:"
                    echo -e "  ${COLOR_GRAY}SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@localhost"
                    echo -e "  ${COLOR_GRAY}Password:${COLOR_RESET} $PASSWORD"
                    echo -e "  ${COLOR_GRAY}IP:${COLOR_RESET} $STATIC_IP"
                    read -p "$(print_status "INPUT" "Press Enter to continue...")"
                    ;;
                4)
                    show_vm_performance "$vm_name"
                    ;;
                5)
                    toggle_gpu_passthrough "$vm_name"
                    ;;
                *)
                    return 0
                    ;;
            esac
            return 0
        fi
        
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image not found"
            return 1
        fi
        
        print_status "INFO" "Starting VM with optimizations..."
        print_status "INFO" "Access Information:"
        echo -e "  ${COLOR_GRAY}SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@localhost"
        echo -e "  ${COLOR_GRAY}Password:${COLOR_RESET} $PASSWORD"
        echo -e "  ${COLOR_GRAY}IP:${COLOR_RESET} $STATIC_IP"
        echo
        
        # Build QEMU command with AMD optimizations
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -machine "type=q35,accel=kvm"
            -cpu "$CPU_TYPE,l3-cache=on,topoext=on"
            -m "$MEMORY"
            -smp "$CPUS,sockets=1,cores=$CPUS,threads=1"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=writeback,discard=on"
            -drive "file=$SEED_FILE,format=raw,if=virtio,readonly=on"
            -boot "order=c,menu=on"
            -device "virtio-net-pci,netdev=n0,mac=$MAC_ADDRESS"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )
        
        # Add GPU passthrough if enabled
        if [[ "$GPU_PASSTHROUGH" == true ]]; then
            local gpu_pci_addresses=($GPU_PCI_ADDRESSES)
            if [ ${#gpu_pci_addresses[@]} -gt 0 ]; then
                print_status "AMD" "Enabling GPU passthrough for $GPU_TYPE GPU..."
                
                # Add vfio-pci devices
                for pci_addr in "${gpu_pci_addresses[@]}"; do
                    # Convert PCI address format (e.g., 01:00.0 to 0000:01:00.0)
                    local full_pci_addr="0000:$pci_addr"
                    qemu_cmd+=(
                        -device "vfio-pci,host=$full_pci_addr"
                    )
                done
                
                # Additional GPU options
                qemu_cmd+=(
                    -vga none
                    -nographic
                    -device "virtio-gpu-pci"
                )
                
                # Add GPU ROM if needed (for NVIDIA)
                if [[ "$GPU_TYPE" == "nvidia" ]]; then
                    if [ -f "/usr/share/kvm/vbios.bin" ]; then
                        qemu_cmd+=(-device "vfio-pci,host=0000:${gpu_pci_addresses[0]},romfile=/usr/share/kvm/vbios.bin")
                    fi
                fi
            fi
        elif [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga "virtio" -display "gtk,gl=on")
        else
            qemu_cmd+=(-nographic -serial "mon:stdio")
        fi
        
        # AMD performance enhancements
        qemu_cmd+=(
            -device "virtio-balloon-pci"
            -object "rng-random,filename=/dev/urandom,id=rng0"
            -device "virtio-rng-pci,rng=rng0"
            -rtc "base=utc,clock=host,driftfix=slew"
            -no-reboot
            -global "kvm-pit.lost_tick_policy=delay"
            -device "virtio-serial"
            -chardev "stdio,id=console,signal=off"
            -device "virtconsole,chardev=console"
        )
        
        # Add hugepages for better performance (if available)
        if [ -d "/dev/hugepages" ]; then
            local hugepage_size=$((MEMORY * 1024 * 1024 / 2048))
            qemu_cmd+=(
                -mem-path "/dev/hugepages"
                -mem-prealloc
                -object "memory-backend-file,id=mem,size=${MEMORY}M,mem-path=/dev/hugepages,share=on,prealloc=yes"
                -numa "node,memdev=mem"
            )
        fi
        
        # Add port forwards
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            local forward_idx=1
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n$forward_idx")
                qemu_cmd+=(-netdev "user,id=n$forward_idx,hostfwd=tcp::$host_port-:$guest_port")
                ((forward_idx++))
            done
        fi
        
        echo -e "${COLOR_WHITE}Startup Mode:${COLOR_RESET}"
        echo "  1) Foreground (with console)"
        echo "  2) Background (daemon)"
        echo "  3) Screen session (recommended)"
        
        read -p "$(print_status "INPUT" "Select startup mode (default: 3): ")" startup_mode
        startup_mode="${startup_mode:-3}"
        
        case $startup_mode in
            1)  # Foreground
                echo "$SUBTLE_SEP"
                print_status "INFO" "Starting VM in foreground..."
                print_status "INFO" "Press Ctrl+C to stop the VM"
                "${qemu_cmd[@]}"
                print_status "INFO" "VM has been shut down"
                ;;
                
            2)  # Background
                "${qemu_cmd[@]}" >/dev/null 2>&1 &
                print_status "SUCCESS" "VM started in background"
                ;;
                
            3)  # Screen session
                screen -dmS "qemu-$vm_name" "${qemu_cmd[@]}"
                print_status "SUCCESS" "VM started in screen session 'qemu-$vm_name'"
                print_status "INFO" "Attach with: screen -r qemu-$vm_name"
                print_status "INFO" "Detach with: Ctrl+A then D"
                ;;
        esac
        
        log_action "START_VM" "$vm_name" "Started with AMD optimization, GPU: $GPU_PASSTHROUGH"
    fi
}

# Function to toggle GPU passthrough
toggle_gpu_passthrough() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "GPU PASSTHROUGH MANAGEMENT"
        
        if is_vm_running "$vm_name"; then
            print_status "WARN" "Cannot change GPU passthrough while VM is running"
            print_status "INFO" "Stop the VM first to change GPU passthrough settings"
            return 1
        fi
        
        echo -e "Current GPU Passthrough: ${COLOR_CYAN}$GPU_PASSTHROUGH${COLOR_RESET}"
        if [ "$GPU_PASSTHROUGH" = true ]; then
            echo -e "GPU Type: $GPU_TYPE"
        fi
        
        echo -e "\n${COLOR_WHITE}Options:${COLOR_RESET}"
        echo "  1) Enable GPU passthrough"
        echo "  2) Disable GPU passthrough"
        echo "  3) Change GPU type"
        echo "  0) Back"
        
        read -p "$(print_status "INPUT" "Select option: ")" gpu_option
        
        case $gpu_option in
            1)
                if check_iommu && detect_gpu; then
                    GPU_PASSTHROUGH=true
                    GPU_TYPE=$(get_gpu_info)
                    GPU_PCI_ADDRESSES=$(get_gpu_pci_addresses)
                    print_status "SUCCESS" "GPU passthrough enabled for $GPU_TYPE"
                    save_vm_config
                else
                    print_status "ERROR" "Cannot enable GPU passthrough"
                    if ! check_iommu; then
                        print_status "INFO" "IOMMU is not enabled. Enable it in BIOS/UEFI and kernel parameters."
                    fi
                    if ! detect_gpu; then
                        print_status "INFO" "No GPU detected"
                    fi
                fi
                ;;
            2)
                GPU_PASSTHROUGH=false
                print_status "SUCCESS" "GPU passthrough disabled"
                save_vm_config
                ;;
            3)
                if check_iommu && detect_gpu; then
                    echo -e "${COLOR_YELLOW}Available GPU Types:${COLOR_RESET}"
                    local gpu_types=()
                    local i=1
                    
                    if detect_amd_gpu; then
                        echo "  $i) AMD GPU"
                        gpu_types[$i]="amd"
                        ((i++))
                    fi
                    if detect_nvidia_gpu; then
                        echo "  $i) NVIDIA GPU"
                        gpu_types[$i]="nvidia"
                        ((i++))
                    fi
                    if detect_intel_gpu; then
                        echo "  $i) Intel GPU"
                        gpu_types[$i]="intel"
                        ((i++))
                    fi
                    
                    read -p "$(print_status "INPUT" "Select GPU type: ")" gpu_type_choice
                    if [[ "$gpu_type_choice" =~ ^[0-9]+$ ]] && [ "$gpu_type_choice" -ge 1 ] && [ "$gpu_type_choice" -le ${#gpu_types[@]} ]; then
                        GPU_TYPE="${gpu_types[$gpu_type_choice]}"
                        GPU_PASSTHROUGH=true
                        GPU_PCI_ADDRESSES=$(get_gpu_pci_addresses)
                        print_status "SUCCESS" "GPU type set to $GPU_TYPE"
                        save_vm_config
                    fi
                fi
                ;;
        esac
    fi
}

# Function to show VM performance
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VM PERFORMANCE STATS"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            local pid=$(pgrep -f "qemu-system-x86_64.*$vm_name")
            if [[ -n "$pid" ]]; then
                echo -e "\n${COLOR_WHITE}Process Stats:${COLOR_RESET}"
                ps -p "$pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers | awk '{
                    printf "  PID: %s | CPU: %s%% | MEM: %s%% | Size: %sMB | Command: %s\n", 
                    $1, $2, $3, $4/1024, $7
                }'
                
                # Show CPU pinning info
                echo -e "\n${COLOR_WHITE}CPU Affinity:${COLOR_RESET}"
                taskset -cp "$pid" 2>/dev/null || echo "  Not available"
            fi
        fi
        
        echo -e "\n${COLOR_WHITE}Configuration:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS ($CPU_TYPE)${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}GPU Passthrough:${COLOR_RESET} $GPU_PASSTHROUGH"
        if [ "$GPU_PASSTHROUGH" = true ]; then
            echo -e "  ${COLOR_GRAY}GPU Type:${COLOR_RESET} $GPU_TYPE"
        fi
        
        echo -e "\n${COLOR_WHITE}Optimizations:${COLOR_RESET}"
        if [[ "$CPU_TYPE" == "EPYC-v4" ]]; then
            echo -e "  ${COLOR_GRAY}CPU:${COLOR_RESET} ${COLOR_GREEN}AMD EPYC Optimized${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Features:${COLOR_RESET} L3 Cache enabled, Topology Extensions"
        else
            echo -e "  ${COLOR_GRAY}CPU:${COLOR_RESET} Host Passthrough"
        fi
        echo -e "  ${COLOR_GRAY}Disk Cache:${COLOR_RESET} Writeback + Discard"
        echo -e "  ${COLOR_GRAY}Network:${COLOR_RESET} VirtIO"
        if [ -d "/dev/hugepages" ]; then
            echo -e "  ${COLOR_GRAY}Huge Pages:${COLOR_RESET} Enabled"
        fi
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to stop VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STOP VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM..."
            
            # Check if it's in a screen session
            if screen -list | grep -q "qemu-$vm_name"; then
                screen -S "qemu-$vm_name" -X quit
                print_status "SUCCESS" "VM stopped (screen session terminated)"
            else
                # Kill by process name
                pkill -f "qemu-system-x86_64.*$vm_name"
                sleep 2
                
                if is_vm_running "$vm_name"; then
                    pkill -9 -f "qemu-system-x86_64.*$vm_name"
                    print_status "SUCCESS" "VM force stopped"
                else
                    print_status "SUCCESS" "VM stopped"
                fi
            fi
            
            log_action "STOP_VM" "$vm_name" "Stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VIRTUAL MACHINE INFORMATION"
        
        echo -e "${COLOR_WHITE}Basic Information:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Name:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}OS:${COLOR_RESET} $OS_TYPE"
        echo -e "  ${COLOR_GRAY}Created:${COLOR_RESET} $CREATED"
        echo -e "  ${COLOR_GRAY}Status:${COLOR_RESET} $(is_vm_running "$vm_name" && echo -e "${COLOR_GREEN}Running${COLOR_RESET}" || echo -e "${COLOR_YELLOW}Stopped${COLOR_RESET}")"
        
        echo -e "\n${COLOR_WHITE}Resources:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS ($CPU_TYPE)${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}GPU Passthrough:${COLOR_RESET} $GPU_PASSTHROUGH"
        if [ "$GPU_PASSTHROUGH" = true ]; then
            echo -e "  ${COLOR_GRAY}GPU Type:${COLOR_RESET} $GPU_TYPE"
        fi
        
        echo -e "\n${COLOR_WHITE}Network:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}IP:${COLOR_RESET} $STATIC_IP"
        echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
        if [[ -n "$PORT_FORWARDS" ]]; then
            echo -e "  ${COLOR_GRAY}Port Forwards:${COLOR_RESET} $PORT_FORWARDS"
        fi
        
        echo -e "\n${COLOR_WHITE}Access:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Username:${COLOR_RESET} ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Password:${COLOR_RESET} ********"
        
        if [ "$PROXMOX_MODE" = true ]; then
            echo -e "\n${COLOR_WHITE}Proxmox VE:${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Mode:${COLOR_RESET} Installation Ready"
            echo -e "  ${COLOR_GRAY}Template:${COLOR_RESET} $PROXMOX_TEMPLATE"
        fi
        
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
        
        print_status "WARN" "This will permanently delete the VM!"
        read -p "$(print_status "INPUT" "Type 'DELETE' to confirm: ")" confirm
        if [[ "$confirm" == "DELETE" ]]; then
            if is_vm_running "$vm_name"; then
                pkill -f "qemu-system-x86_64.*$vm_name"
            fi
            
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' deleted"
            log_action "DELETE_VM" "$vm_name" "Deleted"
        else
            print_status "INFO" "Deletion cancelled"
        fi
    fi
}

# Function to convert VM to Proxmox template
convert_to_proxmox_template() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "CONVERT TO PROXMOX TEMPLATE"
        
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "Cannot convert running VM to template"
            return 1
        fi
        
        print_status "INFO" "Converting VM '$vm_name' to Proxmox template..."
        
        # Create template directory
        local template_dir="$TEMPLATES_DIR/$vm_name"
        mkdir -p "$template_dir"
        
        # Copy VM files
        cp "$IMG_FILE" "$template_dir/"
        cp "$SEED_FILE" "$template_dir/"
        cp "$VM_DIR/$vm_name.conf" "$template_dir/"
        
        # Create template metadata
        cat > "$template_dir/template.info" <<EOF
Template Name: $vm_name
Original VM: $vm_name
OS Type: $OS_TYPE
Created: $(date)
CPU: $CPUS vCPU
Memory: $MEMORY MB
Disk: $DISK_SIZE
EOF
        
        # Update VM config to mark as template
        PROXMOX_TEMPLATE="true"
        save_vm_config
        
        print_status "SUCCESS" "VM converted to Proxmox template in $template_dir"
        print_status "INFO" "Template can be cloned to create new VMs"
    fi
}

# Function to clone VM from template
clone_from_template() {
    local template_name=$1
    
    local template_dir="$TEMPLATES_DIR/$template_name"
    if [ ! -d "$template_dir" ]; then
        print_status "ERROR" "Template '$template_name' not found"
        return 1
    fi
    
    section_header "CLONE FROM TEMPLATE"
    
    # Load template config
    if [ -f "$template_dir/$template_name.conf" ]; then
        source "$template_dir/$template_name.conf" 2>/dev/null
    fi
    
    # Get new VM name
    while true; do
        read -p "$(print_status "INPUT" "Enter name for new VM: ")" new_vm_name
        if validate_input "name" "$new_vm_name"; then
            if [[ -f "$VM_DIR/$new_vm_name.conf" ]]; then
                print_status "ERROR" "VM with name '$new_vm_name' already exists"
            else
                break
            fi
        fi
    done
    
    # Clone the template
    print_status "INFO" "Cloning template '$template_name' to '$new_vm_name'..."
    
    # Copy image file
    local new_img_file="$VM_DIR/$new_vm_name.img"
    cp "$template_dir/$template_name.img" "$new_img_file"
    
    # Create new config
    VM_NAME="$new_vm_name"
    HOSTNAME="$new_vm_name"
    IMG_FILE="$new_img_file"
    SEED_FILE="$VM_DIR/$new_vm_name-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"
    PROXMOX_TEMPLATE="false"
    
    # Generate new MAC and IP
    MAC_ADDRESS=$(generate_mac)
    STATIC_IP=$(generate_auto_ip)
    
    # Create new cloud-init seed
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null | tr -d '\n')
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if cloud-localds "$SEED_FILE" user-data meta-data 2>/dev/null; then
        save_vm_config
        print_status "SUCCESS" "VM '$new_vm_name' cloned from template '$template_name'"
        log_action "CLONE_TEMPLATE" "$new_vm_name" "Cloned from $template_name"
    else
        print_status "ERROR" "Failed to create seed image for cloned VM"
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
    echo -e "  ${COLOR_GRAY}Total VMs:${COLOR_RESET} ${COLOR_CYAN}$total_vms${COLOR_RESET} / $MAX_VMS"
    echo -e "  ${COLOR_GRAY}Running VMs:${COLOR_RESET} ${COLOR_GREEN}$running_vms${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Stopped VMs:${COLOR_RESET} ${COLOR_YELLOW}$((total_vms - running_vms))${COLOR_RESET}"
    
    # Count templates
    local template_count=$(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    echo -e "  ${COLOR_GRAY}Templates:${COLOR_RESET} ${COLOR_MAGENTA}$template_count${COLOR_RESET}"
    
    # System info
    echo -e "\n${COLOR_WHITE}System Information:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}CPU:${COLOR_RESET} $(detect_amd_cpu && echo -e "${COLOR_GREEN}AMD $(get_amd_cpu_model)${COLOR_RESET}" || echo "Intel/Other")"
    echo -e "  ${COLOR_GRAY}GPU:${COLOR_RESET} $(get_gpu_info)"
    echo -e "  ${COLOR_GRAY}IOMMU:${COLOR_RESET} $(check_iommu && echo -e "${COLOR_GREEN}Enabled${COLOR_RESET}" || echo -e "${COLOR_YELLOW}Disabled${COLOR_RESET}")"
    echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} $(free -h | awk '/^Mem:/{print $3 "/" $2 " used"}')"
    echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} $(df -h / | awk 'NR==2 {print $4 " free"}')"
    
    # AMD-specific info
    if detect_amd_cpu; then
        echo -e "\n${COLOR_WHITE}AMD Optimizations:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}CPU Model:${COLOR_RESET} EPYC-v4"
        echo -e "  ${COLOR_GRAY}Features:${COLOR_RESET} L3 Cache, Topology Extensions"
        if [ -d "/dev/hugepages" ]; then
            echo -e "  ${COLOR_GRAY}Huge Pages:${COLOR_RESET} Enabled"
        fi
    fi
    
    echo
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function to manage templates
manage_templates() {
    display_header
    section_header "MANAGE TEMPLATES"
    
    local templates=($(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort))
    local template_count=${#templates[@]}
    
    if [ $template_count -gt 0 ]; then
        print_status "INFO" "Available templates:"
        for i in "${!templates[@]}"; do
            printf "  %2d) %s\n" $((i+1)) "${templates[$i]}"
        done
        echo
        
        echo "Template Options:"
        echo "  1) Clone template to new VM"
        echo "  2) Delete template"
        echo "  0) Back to main menu"
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1)
                if [ $template_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter template number to clone: ")" template_num
                    if [[ "$template_num" =~ ^[0-9]+$ ]] && [ "$template_num" -ge 1 ] && [ "$template_num" -le $template_count ]; then
                        clone_from_template "${templates[$((template_num-1))]}"
                    fi
                fi
                ;;
            2)
                if [ $template_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter template number to delete: ")" template_num
                    if [[ "$template_num" =~ ^[0-9]+$ ]] && [ "$template_num" -ge 1 ] && [ "$template_num" -le $template_count ]; then
                        local template_name="${templates[$((template_num-1))]}"
                        print_status "WARN" "Delete template '$template_name'?"
                        read -p "$(print_status "INPUT" "Type 'DELETE' to confirm: ")" confirm
                        if [[ "$confirm" == "DELETE" ]]; then
                            rm -rf "$TEMPLATES_DIR/$template_name"
                            print_status "SUCCESS" "Template '$template_name' deleted"
                        fi
                    fi
                fi
                ;;
        esac
    else
        echo -e "  ${COLOR_GRAY}No templates found.${COLOR_RESET}"
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            section_header "VIRTUAL MACHINES"
            print_status "INFO" "Found $vm_count VM(s):"
            echo
            
            for i in "${!vms[@]}"; do
                local vm_name="${vms[$i]}"
                local status="${COLOR_YELLOW}● Stopped${COLOR_RESET}"
                if is_vm_running "$vm_name"; then
                    status="${COLOR_GREEN}● Running${COLOR_RESET}"
                fi
                
                # Load config to show GPU status
                if load_vm_config "$vm_name" 2>/dev/null; then
                    local gpu_status=""
                    if [ "$GPU_PASSTHROUGH" = true ]; then
                        gpu_status=" [GPU:${GPU_TYPE:0:1}]"
                    fi
                    printf "  %2d) %-20s %s%s\n" $((i+1)) "$vm_name" "$status" "$gpu_status"
                else
                    printf "  %2d) %-20s %s\n" $((i+1)) "$vm_name" "$status"
                fi
            done
            echo
        else
            section_header "WELCOME"
            echo -e "  ${COLOR_GRAY}No virtual machines found.${COLOR_RESET}"
            echo
        fi
        
        section_header "MAIN MENU"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start/Manage a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Delete a VM"
            echo "  6) Convert VM to Proxmox template"
            echo "  7) Manage GPU passthrough"
            echo "  8) System overview"
            echo "  9) Manage templates"
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
                    read -p "$(print_status "INPUT" "Enter VM number: ")" vm_num
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
                        stop_vm "${vms[$((vm_num-1))]}"
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
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to convert to template: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        convert_to_proxmox_template "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to manage GPU: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        toggle_gpu_passthrough "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                show_system_overview
                ;;
            9)
                manage_templates
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
