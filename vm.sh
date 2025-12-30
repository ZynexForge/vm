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
    echo -e "${COLOR_WHITE}ZYNEXFORGE™ Virtual Machine Manager v5.0${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Max VMs: $MAX_VMS | Auto IP | All Features${COLOR_RESET}"
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
        print_status "INFO" "Install with: nix-shell -p qemu_kvm cloud-utils"
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
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD SSH_KEYS
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset NETWORK_CONFIG MAC_ADDRESS STATIC_IP BACKUP_SCHEDULE SNAPSHOT_COUNT CPU_TYPE GPU_PASSTHROUGH
        
        source "$config_file"
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

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Setting up VM storage..."
    
    # Create cache directory
    mkdir -p "$IMAGES_DIR"
    
    # Extract filename from URL
    local image_filename=$(basename "$IMG_URL")
    local cached_image="$IMAGES_DIR/$image_filename"
    
    # Download or use cached image
    if [[ ! -f "$cached_image" ]]; then
        print_status "INFO" "Downloading OS image..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$cached_image.tmp" 2>/dev/null; then
            print_status "ERROR" "Failed to download image"
            exit 1
        fi
        mv "$cached_image.tmp" "$cached_image"
    fi
    
    # Copy to VM location
    cp "$cached_image" "$IMG_FILE"
    
    # Resize disk
    qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null || \
    qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    
    # Create cloud-init config
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(echo "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null | tr -d '\n')
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create seed image"
        exit 1
    fi
    
    # Create initial snapshot
    if [[ "$SNAPSHOT_COUNT" -gt 0 ]]; then
        qemu-img snapshot -c "initial" "$IMG_FILE" 2>/dev/null || true
    fi
}

# Function to create new VM
create_new_vm() {
    if ! check_vm_limit; then
        return 1
    fi
    
    display_header
    section_header "CREATE NEW VIRTUAL MACHINE"
    
    # OS Selection
    section_header "OPERATING SYSTEM SELECTION"
    
    declare -A OS_OPTIONS=(
        ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
        ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
        ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
        ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
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
        read -p "$(print_status "INPUT" "Select OS (1-${#OS_OPTIONS[@]}): ")" choice
        
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

    # Resource Allocation
    section_header "RESOURCE ALLOCATION"
    
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 50G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-50G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 4096): ")" MEMORY
        MEMORY="${MEMORY:-4096}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 4): ")" CPUS
        CPUS="${CPUS:-4}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    # CPU Features
    section_header "ADVANCED CPU FEATURES"
    echo "CPU Types:"
    echo "  1) host (best performance)"
    echo "  2) EPYC-v4 (AMD optimized)"
    echo "  3) kvm64 (compatibility)"
    
    read -p "$(print_status "INPUT" "Select CPU type (default: 1): ")" cpu_choice
    case $cpu_choice in
        1) CPU_TYPE="host" ;;
        2) CPU_TYPE="EPYC-v4" ;;
        3) CPU_TYPE="kvm64" ;;
        *) CPU_TYPE="host" ;;
    esac

    # GPU passthrough
    read -p "$(print_status "INPUT" "Enable GPU passthrough? (y/N): ")" gpu_choice
    if [[ "$gpu_choice" =~ ^[Yy]$ ]]; then
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
    
    echo "Network Configuration:"
    echo "  1) Tap networking (bridged) [RECOMMENDED]"
    echo "  2) User mode networking (NAT)"
    
    read -p "$(print_status "INPUT" "Select network type (default: 1): ")" net_choice
    case $net_choice in
        1) NETWORK_CONFIG="tap" ;;
        2) NETWORK_CONFIG="user" ;;
        *) NETWORK_CONFIG="tap" ;;
    esac

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
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

    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80): ")" PORT_FORWARDS

    # Backup & Snapshot
    section_header "BACKUP & SNAPSHOT"
    
    echo "Backup Schedule:"
    echo "  1) Daily"
    echo "  2) Weekly"
    echo "  3) Monthly"
    echo "  4) None"
    
    read -p "$(print_status "INPUT" "Select backup schedule (default: 1): ")" backup_choice
    case $backup_choice in
        1) BACKUP_SCHEDULE="daily" ;;
        2) BACKUP_SCHEDULE="weekly" ;;
        3) BACKUP_SCHEDULE="monthly" ;;
        4) BACKUP_SCHEDULE="none" ;;
        *) BACKUP_SCHEDULE="daily" ;;
    esac

    read -p "$(print_status "INPUT" "Maximum snapshots to keep (default: 5): ")" SNAPSHOT_COUNT
    SNAPSHOT_COUNT="${SNAPSHOT_COUNT:-5}"

    # Final configuration
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    section_header "DEPLOYMENT SUMMARY"
    echo -e "${COLOR_WHITE}VM Configuration:${COLOR_RESET}"
    echo -e "  Name: ${COLOR_CYAN}$VM_NAME${COLOR_RESET}"
    echo -e "  OS: ${COLOR_GREEN}$os${COLOR_RESET}"
    echo -e "  Resources: ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM | $DISK_SIZE disk${COLOR_RESET}"
    echo -e "  Network: ${COLOR_CYAN}$NETWORK_CONFIG${COLOR_RESET} (IP: $STATIC_IP)"
    echo -e "  SSH Port: ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
    echo
    
    read -p "$(print_status "INPUT" "Proceed with deployment? (Y/n): ")" confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        setup_vm_image
        save_vm_config
        
        section_header "DEPLOYMENT COMPLETE"
        print_status "SUCCESS" "VM '$VM_NAME' deployed successfully"
        log_action "CREATE_VM" "$VM_NAME" "Created with $OS_TYPE"
        
        echo -e "  ${COLOR_GRAY}SSH: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}IP: $STATIC_IP${COLOR_RESET}"
        
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

# Function to start VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STARTING VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM $vm_name is already running"
            return 0
        fi
        
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image not found"
            return 1
        fi
        
        print_status "INFO" "Access Information:"
        echo -e "  ${COLOR_GRAY}SSH: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Password: $PASSWORD${COLOR_RESET}"
        echo
        
        # QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -m "$MEMORY"
            -smp "$CPUS"
            -cpu "$CPU_TYPE"
            -drive "file=$IMG_FILE,format=qcow2"
            -drive "file=$SEED_FILE,format=raw"
            -boot order=c
            -device "virtio-net-pci,netdev=n0"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )

        # Add GPU passthrough if enabled
        if [[ "$GPU_PASSTHROUGH" == true ]]; then
            qemu_cmd+=(-vga none -nographic)
        elif [[ "$GUI_MODE" == true ]]; then
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

        echo "Startup Mode:"
        echo "  1) Foreground"
        echo "  2) Background"
        echo "  3) Screen session"
        
        read -p "$(print_status "INPUT" "Select startup mode (default: 1): ")" startup_mode
        startup_mode="${startup_mode:-1}"
        
        case $startup_mode in
            2)  # Background
                "${qemu_cmd[@]}" &
                print_status "SUCCESS" "VM started in background"
                ;;
                
            3)  # Screen
                screen -dmS "qemu-$vm_name" "${qemu_cmd[@]}"
                print_status "SUCCESS" "VM started in screen session"
                ;;
                
            *)  # Foreground
                echo "$SUBTLE_SEP"
                "${qemu_cmd[@]}"
                print_status "INFO" "VM has been shut down"
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
        echo -e "  ${COLOR_GRAY}Name:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}OS:${COLOR_RESET} $OS_TYPE"
        echo -e "  ${COLOR_GRAY}Created:${COLOR_RESET} $CREATED"
        echo -e "  ${COLOR_GRAY}Status:${COLOR_RESET} $(is_vm_running "$vm_name" && echo -e "${COLOR_GREEN}Running${COLOR_RESET}" || echo -e "${COLOR_YELLOW}Stopped${COLOR_RESET}")"
        
        echo -e "\n${COLOR_WHITE}Resources:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        
        echo -e "\n${COLOR_WHITE}Network:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}IP:${COLOR_RESET} $STATIC_IP"
        echo -e "  ${COLOR_Gray}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
        
        echo -e "\n${COLOR_WHITE}Access:${COLOR_RESET}"
        echo -e "  ${COLOR_Gray}Username:${COLOR_RESET} ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
        
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

# Function to stop VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STOP VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            pkill -f "qemu-system-x86_64.*$vm_name"
            print_status "SUCCESS" "VM $vm_name stopped"
            log_action "STOP_VM" "$vm_name" "Stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
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
