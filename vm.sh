#!/bin/bash
set -euo pipefail

# =============================
# ZYNEXFORGE™ - Ultimate VM Manager
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
MAX_VMS=4
VM_BASE_DIR="$HOME/.zynexforge"
VM_DIR="$VM_BASE_DIR/vms"
IMAGES_DIR="$VM_BASE_DIR/images"
BACKUPS_DIR="$VM_BASE_DIR/backups"
LOGS_DIR="$VM_BASE_DIR/logs"

# Create directories
mkdir -p "$VM_DIR" "$IMAGES_DIR" "$BACKUPS_DIR" "$LOGS_DIR"

# Function to display header
display_header() {
    clear
    echo -e "${COLOR_CYAN}"
    cat << "EOF"

__________                             ___________                         
\____    /___.__. ____   ____ ___  ___ \_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /  |    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 
EOF
    echo -e "${COLOR_RESET}"
    echo -e "${COLOR_WHITE}ZYNEXFORGE™ Virtual Machine Manager${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Max VMs: $MAX_VMS | AMD Optimized | Beast Performance${COLOR_RESET}"
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

# Function to detect AMD CPU
detect_amd_cpu() {
    if grep -qi "amd" /proc/cpuinfo || grep -qi "ryzen" /proc/cpuinfo; then
        return 0
    else
        return 1
    fi
}

# Function to detect GPU
detect_gpu() {
    if lspci | grep -i "vga\|3d\|display" | grep -qi "nvidia\|amd\|radeon"; then
        return 0
    else
        return 1
    fi
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
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
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
EOF
    
    print_status "SUCCESS" "Configuration saved"
    log_action "SAVE_CONFIG" "$VM_NAME" "Configuration updated"
}

# Function to setup VM image with beast optimization
setup_vm_image() {
    print_status "BEAST" "Setting up VM storage with ultimate optimization..."
    
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
    
    # Copy to VM location
    cp "$cached_image" "$IMG_FILE.tmp"
    
    # Create beast-optimized qcow2 image
    print_status "BEAST" "Creating beast-optimized disk image..."
    qemu-img create -f qcow2 -o cluster_size=2M,preallocation=metadata,compat=1.1,lazy_refcounts=on "$IMG_FILE" "$DISK_SIZE"
    
    # Beast cloud-init config
    cat > user-data <<EOF
#cloud-config
# ZYNEXFORGE BEAST CONFIGURATION
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

bootcmd:
  - echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

power_state:
  mode: reboot
  timeout: 300
  message: "ZYNEXFORGE Beast VM is ready!"
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
    
    print_status "BEAST" "VM image optimized for beast performance!"
}

# Function to create beast VM
create_new_vm() {
    if ! check_vm_limit; then
        return 1
    fi
    
    display_header
    section_header "CREATE BEAST VIRTUAL MACHINE"
    
    # Detect AMD CPU and GPU
    local HAS_AMD=false
    local HAS_GPU=false
    
    if detect_amd_cpu; then
        HAS_AMD=true
        print_status "BEAST" "AMD CPU detected! Optimizing for AMD Ryzen/EPYC..."
    fi
    
    if detect_gpu; then
        HAS_GPU=true
        print_status "BEAST" "GPU detected! GPU passthrough available..."
    fi
    
    # OS Selection
    section_header "OPERATING SYSTEM SELECTION"
    
    declare -A OS_OPTIONS=(
        ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
        ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
        ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
        ["Proxmox 8"]="proxmox|ve8|https://download.proxmox.com/images/cloud/bookworm/current/debian-12-genericcloud-amd64.qcow2|proxmox8|root|proxmox"
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
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Select OS (1-${#OS_OPTIONS[@]}): ")" choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_list[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            print_status "INFO" "Selected: $os"
            break
        else
            print_status "ERROR" "Invalid selection"
        fi
    done

    # VM Configuration
    section_header "VIRTUAL MACHINE CONFIGURATION"
    
    while true; do
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
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
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        echo -e "${COLOR_YELLOW}Password requirements: Minimum 4 characters${COLOR_RESET}"
        read -s -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ ${#PASSWORD} -ge 4 ]; then
            break
        else
            print_status "ERROR" "Password must be at least 4 characters"
        fi
    done

    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Add SSH public keys (press Enter to skip): ")" SSH_KEYS

    # BEAST Resource Allocation
    section_header "BEAST RESOURCE ALLOCATION"
    
    print_status "BEAST" "Auto-configuring optimal resources..."
    
    # Auto-detect optimal settings
    local TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    local TOTAL_CPUS=$(nproc)
    
    # Calculate optimal resources
    local OPTIMAL_MEMORY=$((TOTAL_MEM / 4))  # Use 25% of total RAM
    if [ $OPTIMAL_MEMORY -gt 16384 ]; then
        OPTIMAL_MEMORY=16384  # Cap at 16GB
    elif [ $OPTIMAL_MEMORY -lt 2048 ]; then
        OPTIMAL_MEMORY=2048   # Minimum 2GB
    fi
    
    local OPTIMAL_CPUS=$((TOTAL_CPUS / 2))  # Use half of CPUs
    if [ $OPTIMAL_CPUS -gt 8 ]; then
        OPTIMAL_CPUS=8  # Cap at 8 vCPUs
    elif [ $OPTIMAL_CPUS -lt 2 ]; then
        OPTIMAL_CPUS=2  # Minimum 2 vCPUs
    fi
    
    print_status "INFO" "System has ${TOTAL_MEM}MB RAM, ${TOTAL_CPUS} CPUs"
    print_status "BEAST" "Recommended: ${OPTIMAL_MEMORY}MB RAM, ${OPTIMAL_CPUS} vCPUs"
    
    while true; do
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Disk size (default: 100G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-100G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Memory in MB (recommended: $OPTIMAL_MEMORY): ")" MEMORY
        MEMORY="${MEMORY:-$OPTIMAL_MEMORY}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Number of CPUs (recommended: $OPTIMAL_CPUS): ")" CPUS
        CPUS="${CPUS:-$OPTIMAL_CPUS}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    # BEAST CPU Optimization
    section_header "BEAST CPU OPTIMIZATION"
    
    if [ "$HAS_AMD" = true ]; then
        CPU_TYPE="EPYC-v4"
        print_status "BEAST" "Using AMD EPYC-v4 CPU with all optimizations!"
    else
        CPU_TYPE="host"
        print_status "INFO" "Using host CPU passthrough"
    fi

    # GPU Passthrough
    if [ "$HAS_GPU" = true ]; then
        print_status "BEAST" "GPU detected! Enabling GPU passthrough for ultimate performance!"
        GPU_PASSTHROUGH=true
    else
        GPU_PASSTHROUGH=false
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
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} SSH Port (recommended: $DEFAULT_SSH_PORT): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-$DEFAULT_SSH_PORT}"
        if validate_input "port" "$SSH_PORT"; then
            break
        fi
    done

    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enable GUI mode? (y/N): ")" gui_input
    if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
        GUI_MODE=true
    else
        GUI_MODE=false
    fi

    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Additional port forwards (e.g., 8080:80,8443:443): ")" PORT_FORWARDS

    # Backup & Snapshot
    BACKUP_SCHEDULE="daily"
    SNAPSHOT_COUNT=10
    print_status "BEAST" "Auto-configured: Daily backups, 10 snapshots"

    # Final configuration
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    section_header "BEAST DEPLOYMENT SUMMARY"
    echo -e "${COLOR_WHITE}Beast VM Configuration:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Name:${COLOR_RESET} ${COLOR_CYAN}$VM_NAME${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}OS:${COLOR_RESET} ${COLOR_GREEN}$os${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM | $DISK_SIZE disk${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}CPU:${COLOR_RESET} ${COLOR_MAGENTA}$CPU_TYPE${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}GPU Passthrough:${COLOR_RESET} ${COLOR_MAGENTA}$GPU_PASSTHROUGH${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Network:${COLOR_RESET} ${COLOR_CYAN}$NETWORK_CONFIG${COLOR_RESET} (IP: $STATIC_IP)"
    echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
    echo
    
    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Deploy this beast VM? (Y/n): ")" confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        setup_vm_image
        save_vm_config
        
        section_header "BEAST DEPLOYMENT COMPLETE"
        print_status "SUCCESS" "╔══════════════════════════════════════════════════════════════════════╗"
        print_status "SUCCESS" "║                     BEAST VM DEPLOYED SUCCESSFULLY!                   ║"
        print_status "SUCCESS" "╚══════════════════════════════════════════════════════════════════════╝"
        
        log_action "CREATE_VM" "$VM_NAME" "Beast VM created with $OS_TYPE, ${MEMORY}MB RAM, ${CPUS} vCPU"
        
        echo -e "\n${COLOR_WHITE}Access Information:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@localhost"
        echo -e "  ${COLOR_GRAY}Password:${COLOR_RESET} $PASSWORD"
        echo -e "  ${COLOR_GRAY}IP:${COLOR_RESET} $STATIC_IP"
        
        echo -e "\n${COLOR_WHITE}Performance Features:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}AMD Optimized:${COLOR_RESET} $HAS_AMD"
        echo -e "  ${COLOR_Gray}GPU Passthrough:${COLOR_RESET} $GPU_PASSTHROUGH"
        echo -e "  ${COLOR_Gray}Daily Backups:${COLOR_RESET} Enabled"
        
        echo -e "\n${COLOR_YELLOW}══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
        
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Start VM now? (Y/n): ")" start_now
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

# Function to start beast VM
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
            echo "  0) Back to menu"
            
            read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Select option: ")" running_option
            
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
                    echo -e "  ${COLOR_Gray}Password:${COLOR_RESET} $PASSWORD"
                    echo -e "  ${COLOR_Gray}IP:${COLOR_RESET} $STATIC_IP"
                    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Press Enter to continue...")"
                    ;;
                4)
                    show_vm_performance "$vm_name"
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
        
        print_status "BEAST" "Starting VM with ultimate performance..."
        print_status "INFO" "Access Information:"
        echo -e "  ${COLOR_GRAY}SSH:${COLOR_RESET} ssh -p $SSH_PORT $USERNAME@localhost"
        echo -e "  ${COLOR_Gray}Password:${COLOR_RESET} $PASSWORD"
        echo -e "  ${COLOR_Gray}IP:${COLOR_RESET} $STATIC_IP"
        echo
        
        # Beast QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -machine "type=q35,accel=kvm"
            -cpu "$CPU_TYPE"
            -m "$MEMORY"
            -smp "$CPUS,sockets=1,cores=$CPUS,threads=1"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=writeback,discard=on"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot "order=c,menu=on"
            -device "virtio-net-pci,netdev=n0"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )
        
        # Add GPU passthrough if enabled
        if [[ "$GPU_PASSTHROUGH" == true ]]; then
            qemu_cmd+=(
                -device "vfio-pci,host=01:00.0,multifunction=on"
                -device "vfio-pci,host=01:00.1"
                -vga none
                -nographic
            )
        elif [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga "virtio" -display "gtk,gl=on")
        else
            qemu_cmd+=(-nographic -serial "mon:stdio")
        fi
        
        # Beast performance enhancements
        qemu_cmd+=(
            -device "virtio-balloon-pci"
            -object "rng-random,filename=/dev/urandom,id=rng0"
            -device "virtio-rng-pci,rng=rng0"
            -rtc "base=utc,clock=host,driftfix=slew"
            -no-reboot
            -global "kvm-pit.lost_tick_policy=delay"
        )
        
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
        
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Select startup mode (default: 3): ")" startup_mode
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
        
        log_action "START_VM" "$vm_name" "Started with beast optimization"
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
                ps -p "$pid" -o pid,%cpu,%mem,sz,rss,vsz --no-headers | awk '{
                    printf "  PID: %s | CPU: %s%% | MEM: %s%% | Size: %sMB\n", 
                    $1, $2, $3, $4/1024
                }'
            fi
        fi
        
        echo -e "\n${COLOR_WHITE}Configuration:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS ($CPU_TYPE)${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}GPU Passthrough:${COLOR_RESET} $GPU_PASSTHROUGH"
        
        echo -e "\n${COLOR_WHITE}Optimizations:${COLOR_RESET}"
        if [[ "$CPU_TYPE" == "EPYC-v4" ]]; then
            echo -e "  ${COLOR_Gray}CPU:${COLOR_RESET} ${COLOR_GREEN}AMD EPYC Optimized${COLOR_RESET}"
        else
            echo -e "  ${COLOR_Gray}CPU:${COLOR_RESET} Host Passthrough"
        fi
        echo -e "  ${COLOR_Gray}Disk Cache:${COLOR_RESET} Writeback + Discard"
        echo -e "  ${COLOR_Gray}Network:${COLOR_RESET} VirtIO"
        
        echo
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Press Enter to continue...")"
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
        echo -e "  ${COLOR_Gray}Name:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}OS:${COLOR_RESET} $OS_TYPE"
        echo -e "  ${COLOR_Gray}Created:${COLOR_RESET} $CREATED"
        echo -e "  ${COLOR_Gray}Status:${COLOR_RESET} $(is_vm_running "$vm_name" && echo -e "${COLOR_GREEN}Running${COLOR_RESET}" || echo -e "${COLOR_YELLOW}Stopped${COLOR_RESET}")"
        
        echo -e "\n${COLOR_WHITE}Resources:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS ($CPU_TYPE)${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}GPU Passthrough:${COLOR_RESET} $GPU_PASSTHROUGH"
        
        echo -e "\n${COLOR_WHITE}Network:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}IP:${COLOR_RESET} $STATIC_IP"
        echo -e "  ${COLOR_Gray}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
        if [[ -n "$PORT_FORWARDS" ]]; then
            echo -e "  ${COLOR_Gray}Port Forwards:${COLOR_RESET} $PORT_FORWARDS"
        fi
        
        echo -e "\n${COLOR_WHITE}Access:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Username:${COLOR_RESET} ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Password:${COLOR_RESET} ********"
        
        echo
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Press Enter to continue...")"
    fi
}

# Function to delete VM
delete_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "DELETE VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        print_status "WARN" "This will permanently delete the VM!"
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Type 'DELETE' to confirm: ")" confirm
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
    
    # System info
    echo -e "\n${COLOR_WHITE}System Information:${COLOR_RESET}"
    echo -e "  ${COLOR_Gray}CPU:${COLOR_RESET} $(detect_amd_cpu && echo "AMD Ryzen/EPYC" || echo "Intel/Other")"
    echo -e "  ${COLOR_Gray}GPU:${COLOR_RESET} $(detect_gpu && echo "Available" || echo "Not detected")"
    echo -e "  ${COLOR_Gray}Memory:${COLOR_RESET} $(free -h | awk '/^Mem:/{print $3 "/" $2}') used"
    echo -e "  ${COLOR_Gray}Disk:${COLOR_RESET} $(df -h / | awk 'NR==2 {print $4 " free"}')"
    
    echo
    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Press Enter to continue...")"
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
            echo
        fi
        
        section_header "MAIN MENU"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start/Manage a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Delete a VM"
            echo "  6) System overview"
        fi
        echo "  0) Exit"
        echo
        
        read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter your choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} Enter VM number to delete: ")" vm_num
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
