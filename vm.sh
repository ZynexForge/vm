#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager
# =============================

# Global variables
VERSION="2.0.0"
VM_DIR="${VM_DIR:-$HOME/.zynexforge/vms}"
LOG_DIR="${LOG_DIR:-$HOME/.zynexforge/logs}"
CACHE_DIR="${CACHE_DIR:-$HOME/.zynexforge/cache}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.zynexforge/config}"
SCRIPT_URL="https://raw.githubusercontent.com/yourusername/zynexforge-vm-manager/main/vm.sh"

# Function to display header
display_header() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║    ███████ ██    ██ ███    ██ ███████ ███    ██ ███████ ██████   ██████      ║
║    ██      ██    ██ ████   ██ ██      ████   ██ ██      ██   ██ ██    ██     ║
║    ██      ██    ██ ██ ██  ██ █████   ██ ██  ██ █████   ██████  ██    ██     ║
║    ██      ██    ██ ██  ██ ██ ██      ██  ██ ██ ██      ██   ██ ██    ██     ║
║    ███████  ██████  ██   ████ ███████ ██   ████ ███████ ██   ██  ██████      ║
║                                                                               ║
║    ⚡ ZynexForge VM Manager v2.0 ⚡                                            ║
║    Advanced Virtualization Management Platform                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[ℹ]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[⚠]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[✗]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[✓]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[?]\033[0m $message" ;;
        "DEBUG") echo -e "\033[1;35m[🐛]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

# Function to initialize directories
init_directories() {
    mkdir -p "$VM_DIR" "$LOG_DIR" "$CACHE_DIR" "$CONFIG_DIR"
}

# Function to check and setup KVM
setup_kvm() {
    print_status "INFO" "Checking KVM virtualization support..."
    
    # Check CPU virtualization support
    if grep -q -E 'vmx|svm' /proc/cpuinfo; then
        print_status "SUCCESS" "CPU virtualization extensions detected"
    else
        print_status "ERROR" "CPU virtualization extensions not found"
        print_status "INFO" "Enable virtualization in BIOS/UEFI settings"
        return 1
    fi
    
    # Check if KVM modules are loaded
    if lsmod | grep -q kvm; then
        print_status "SUCCESS" "KVM module is loaded"
    else
        print_status "WARN" "KVM module not loaded. Attempting to load..."
        
        # Try to load KVM modules
        if command -v sudo &> /dev/null; then
            if [[ $(uname -m) == "x86_64" ]]; then
                sudo modprobe kvm
                sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null
            elif [[ $(uname -m) == "aarch64" ]]; then
                sudo modprobe kvm
            fi
            
            sleep 2
            
            if lsmod | grep -q kvm; then
                print_status "SUCCESS" "KVM modules loaded successfully"
            else
                print_status "ERROR" "Failed to load KVM modules"
                return 1
            fi
        else
            print_status "ERROR" "sudo not available. Load KVM modules manually:"
            print_status "INFO" "  sudo modprobe kvm"
            print_status "INFO" "  sudo modprobe kvm_intel  # for Intel CPUs"
            print_status "INFO" "  sudo modprobe kvm_amd    # for AMD CPUs"
            return 1
        fi
    fi
    
    # Check /dev/kvm permissions
    if [[ -e /dev/kvm ]]; then
        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
            print_status "SUCCESS" "/dev/kvm is readable and writable"
        else
            print_status "WARN" "/dev/kvm has insufficient permissions"
            
            # Try to fix permissions
            if command -v sudo &> /dev/null; then
                print_status "INFO" "Fixing /dev/kvm permissions..."
                sudo chmod 666 /dev/kvm 2>/dev/null || true
                
                if [[ -r /dev/kvm && -w /dev/kvm ]]; then
                    print_status "SUCCESS" "Permissions fixed"
                else
                    print_status "WARN" "Could not fix permissions automatically"
                    print_status "INFO" "Run manually: sudo chmod 666 /dev/kvm"
                fi
            fi
        fi
    else
        print_status "ERROR" "/dev/kvm device not found"
        print_status "INFO" "Ensure KVM modules are properly loaded"
        return 1
    fi
    
    # Add user to kvm group if needed
    if ! groups | grep -q kvm; then
        print_status "INFO" "Adding user to kvm group..."
        if command -v sudo &> /dev/null && command -v usermod &> /dev/null; then
            sudo usermod -aG kvm "$USER"
            print_status "INFO" "Please log out and back in for group changes to take effect"
        fi
    fi
    
    return 0
}

# Function to check dependencies
check_dependencies() {
    print_status "INFO" "Checking dependencies..."
    
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "openssl" "curl")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        
        # Auto-install for supported distributions
        if [[ -f /etc/debian_version ]]; then
            print_status "INFO" "Detected Debian/Ubuntu. Installing dependencies..."
            sudo apt update
            sudo apt install -y qemu-system qemu-utils cloud-image-utils wget openssl curl
        elif [[ -f /etc/redhat-release ]] || [[ -f /etc/centos-release ]]; then
            print_status "INFO" "Detected RHEL/CentOS/Fedora. Installing dependencies..."
            sudo dnf install -y qemu-kvm qemu-img cloud-utils wget openssl curl
        elif [[ -f /etc/arch-release ]]; then
            print_status "INFO" "Detected Arch Linux. Installing dependencies..."
            sudo pacman -S qemu cloud-utils wget openssl curl
        else
            print_status "INFO" "Install dependencies manually:"
            print_status "INFO" "  Debian/Ubuntu: sudo apt install qemu-system qemu-utils cloud-image-utils wget openssl curl"
            print_status "INFO" "  RHEL/CentOS: sudo dnf install qemu-kvm qemu-img cloud-utils wget openssl curl"
            exit 1
        fi
        
        # Verify installation
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                print_status "ERROR" "Failed to install $dep"
                exit 1
            fi
        done
    fi
    
    print_status "SUCCESS" "All dependencies installed"
    
    # Setup KVM
    if ! setup_kvm; then
        print_status "WARN" "KVM setup had issues. VM performance may be degraded."
        print_status "INFO" "You can still use QEMU without KVM acceleration"
    fi
}

# Function to validate input
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a positive number"
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
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (1-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]{1,50}$ ]]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores (max 50 chars)"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore, and contain only lowercase letters, numbers, hyphens, and underscores (max 32 chars)"
                return 1
            fi
            ;;
        "password")
            if [ -z "$value" ] || [ ${#value} -lt 4 ]; then
                print_status "ERROR" "Password must be at least 4 characters"
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

# Function to get all VM configurations
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear previous variables
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS
        unset IMG_FILE SEED_FILE CREATED NETWORK BRIDGE STATIC_IP
        
        # Source the config file
        source "$config_file"
        
        # Set derived paths if not already set
        IMG_FILE="${IMG_FILE:-$VM_DIR/$VM_NAME.img}"
        SEED_FILE="${SEED_FILE:-$VM_DIR/$VM_NAME-seed.iso}"
        
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
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
NETWORK="$NETWORK"
BRIDGE="$BRIDGE"
STATIC_IP="$STATIC_IP"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved"
}

# Function to download with retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if wget --progress=bar:force --timeout=30 --tries=1 "$url" -O "$output.tmp"; then
            mv "$output.tmp" "$output"
            return 0
        fi
        retry_count=$((retry_count + 1))
        print_status "WARN" "Download failed, retry $retry_count/$max_retries..."
        sleep 2
    done
    
    return 1
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Downloading and preparing image..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check cache first
    local cache_file="$CACHE_DIR/$(basename "$IMG_URL")"
    if [[ -f "$cache_file" ]]; then
        print_status "INFO" "Using cached image"
        cp "$cache_file" "$IMG_FILE"
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! download_with_retry "$IMG_URL" "$IMG_FILE"; then
            print_status "ERROR" "Failed to download image"
            exit 1
        fi
        # Cache the image
        cp "$IMG_FILE" "$cache_file"
    fi
    
    # Resize the disk image
    print_status "INFO" "Creating disk image of size $DISK_SIZE..."
    qemu-img create -f qcow2 -F qcow2 -b "$IMG_FILE" "$IMG_FILE.tmp" "$DISK_SIZE" 2>/dev/null || \
    qemu-img create -f qcow2 "$IMG_FILE.new" "$DISK_SIZE"
    
    if [[ -f "$IMG_FILE.tmp" ]]; then
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    elif [[ -f "$IMG_FILE.new" ]]; then
        mv "$IMG_FILE.new" "$IMG_FILE"
    fi

    # cloud-init configuration
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
    passwd: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    # OS Selection
    print_status "INFO" "Select an OS to set up:"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # Custom Inputs with validation
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            # Check if VM name already exists
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if validate_input "password" "$PASSWORD"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            # Check if port is already in use
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: n): ")" gui_input
        gui_input="${gui_input:-n}"
        GUI_MODE=false
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Network configuration
    print_status "INFO" "Network Configuration:"
    echo "  1) User Networking (NAT) - Recommended for most users"
    echo "  2) Bridge Networking - For direct LAN access"
    read -p "$(print_status "INPUT" "Select network type (1-2, default: 1): ")" network_choice
    network_choice="${network_choice:-1}"
    
    if [[ "$network_choice" == "2" ]]; then
        NETWORK="bridge"
        read -p "$(print_status "INPUT" "Enter bridge interface (default: br0): ")" BRIDGE
        BRIDGE="${BRIDGE:-br0}"
        read -p "$(print_status "INPUT" "Enter static IP (leave empty for DHCP): ")" STATIC_IP
    else
        NETWORK="user"
        BRIDGE=""
        STATIC_IP=""
    fi

    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
}

# Function to build QEMU command
build_qemu_command() {
    local vm_name=$1
    local qemu_cmd=()
    
    qemu_cmd=(
        qemu-system-x86_64
        -name "$vm_name"
        -m "$MEMORY"
        -smp "$CPUS"
        -boot order=c
        -drive "file=$IMG_FILE,format=qcow2,if=virtio"
        -drive "file=$SEED_FILE,format=raw,if=virtio"
    )
    
    # Add CPU optimization
    if [[ $(uname -m) == "x86_64" ]]; then
        qemu_cmd+=(-cpu host)
    else
        qemu_cmd+=(-cpu max)
    fi
    
    # Add KVM acceleration if available
    if [[ -e /dev/kvm ]] && lsmod | grep -q kvm; then
        qemu_cmd+=(-enable-kvm -machine q35,accel=kvm)
    else
        print_status "WARN" "KVM not available, using software emulation (slower)"
        qemu_cmd+=(-machine q35)
    fi
    
    # Network configuration
    if [[ "$NETWORK" == "bridge" && -n "$BRIDGE" ]]; then
        qemu_cmd+=(-netdev "bridge,id=net0,br=$BRIDGE")
        qemu_cmd+=(-device "virtio-net-pci,netdev=net0,mac=$(generate_mac)")
    else
        # User networking with port forwards
        qemu_cmd+=(-device "virtio-net-pci,netdev=net0")
        qemu_cmd+=(-netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22")
        
        # Additional port forwards
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            local net_index=1
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=net$net_index")
                qemu_cmd+=(-netdev "user,id=net$net_index,hostfwd=tcp::$host_port-:$guest_port")
                ((net_index++))
            done
        fi
    fi
    
    # Display configuration
    if [[ "$GUI_MODE" == true ]]; then
        qemu_cmd+=(-vga virtio -display gtk,gl=on)
    else
        qemu_cmd+=(-nographic -serial mon:stdio)
    fi
    
    # Performance optimizations
    qemu_cmd+=(
        -device virtio-balloon-pci
        -object rng-random,filename=/dev/urandom,id=rng0
        -device virtio-rng-pci,rng=rng0
        -usb -device usb-tablet
    )
    
    # Large memory support
    if [[ $MEMORY -gt 16384 ]]; then
        qemu_cmd+=(-mem-path /dev/hugepages)
    fi
    
    echo "${qemu_cmd[@]}"
}

# Generate MAC address
generate_mac() {
    printf '52:54:%02x:%02x:%02x:%02x\n' \
        $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256)) $((RANDOM % 256))
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        # Check if VM is already running
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "VM '$vm_name' is already running"
            return 1
        fi
        
        # Check required files
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "Disk image not found: $IMG_FILE"
            return 1
        fi
        
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Build and execute QEMU command
        local qemu_cmd=$(build_qemu_command "$vm_name")
        local log_file="$LOG_DIR/$vm_name-$(date '+%Y%m%d-%H%M%S').log"
        
        print_status "INFO" "Starting VM (logs: $log_file)..."
        
        # Start QEMU in background
        eval "$qemu_cmd" > "$log_file" 2>&1 &
        local qemu_pid=$!
        
        # Wait for VM to start
        sleep 5
        
        if ps -p $qemu_pid > /dev/null 2>&1; then
            print_status "SUCCESS" "VM '$vm_name' started with PID $qemu_pid"
            print_status "INFO" "VM is booting. SSH will be available in 30-60 seconds."
            
            # Show connection info
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                     Connection Information                   ║"
            echo "╠══════════════════════════════════════════════════════════════╣"
            echo "║ SSH:        ssh -p $SSH_PORT $USERNAME@localhost            ║"
            echo "║ Password:   $PASSWORD                                         ║"
            echo "║ Logs:       $log_file                                        ║"
            echo "║ PID:        $qemu_pid                                         ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
        else
            print_status "ERROR" "Failed to start VM"
            print_status "INFO" "Check log file for details: $log_file"
            
            # Show error from log
            if [[ -f "$log_file" ]]; then
                print_status "ERROR" "Last 10 lines of error log:"
                tail -n 10 "$log_file"
            fi
            return 1
        fi
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system.*name $vm_name" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if is_vm_running "$vm_name"; then
        print_status "INFO" "Stopping VM: $vm_name"
        
        # Get QEMU process ID
        local qemu_pid=$(pgrep -f "qemu-system.*name $vm_name")
        
        # Send SIGTERM (graceful shutdown)
        kill -TERM "$qemu_pid" 2>/dev/null
        sleep 3
        
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM did not stop gracefully, forcing termination..."
            kill -9 "$qemu_pid" 2>/dev/null
            sleep 1
        fi
        
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "Failed to stop VM '$vm_name'"
            return 1
        else
            print_status "SUCCESS" "VM '$vm_name' stopped"
        fi
    else
        print_status "INFO" "VM '$vm_name' is not running"
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            # Stop VM if running
            if is_vm_running "$vm_name"; then
                print_status "INFO" "Stopping running VM..."
                stop_vm "$vm_name"
            fi
            
            # Remove all VM files
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf" "$LOG_DIR/$vm_name"*.log 2>/dev/null
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                      VM Configuration                       ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        echo "║ OS:            $OS_TYPE"
        echo "║ Hostname:      $HOSTNAME"
        echo "║ Username:      $USERNAME"
        echo "║ Password:      $PASSWORD"
        echo "║ SSH Port:      $SSH_PORT"
        echo "║ Memory:        $MEMORY MB"
        echo "║ CPUs:          $CPUS"
        echo "║ Disk:          $DISK_SIZE"
        echo "║ GUI Mode:      $GUI_MODE"
        echo "║ Network:       $NETWORK"
        [[ -n "$BRIDGE" ]] && echo "║ Bridge:        $BRIDGE"
        [[ -n "$STATIC_IP" ]] && echo "║ Static IP:     $STATIC_IP"
        echo "║ Port Forwards: ${PORT_FORWARDS:-None}"
        echo "║ Created:       $CREATED"
        echo "╠══════════════════════════════════════════════════════════════╣"
        
        # Show VM status
        if is_vm_running "$vm_name"; then
            echo "║ Status:        Running"
            local pid=$(pgrep -f "qemu-system.*name $vm_name")
            echo "║ PID:           $pid"
        else
            echo "║ Status:        Stopped"
        fi
        echo "╚══════════════════════════════════════════════════════════════╝"
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to show VM performance
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Performance metrics for VM: $vm_name"
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                     Performance Metrics                      ║"
            echo "╠══════════════════════════════════════════════════════════════╣"
            
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system.*name $vm_name")
            if [[ -n "$qemu_pid" ]]; then
                # Show process stats
                echo "║ QEMU Process:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers | while read line; do
                    echo "║   $line"
                done
                echo "╠══════════════════════════════════════════════════════════════╣"
                
                # Show memory usage
                echo "║ System Memory:"
                free -h | while read line; do
                    echo "║   $line"
                done
                echo "╠══════════════════════════════════════════════════════════════╣"
                
                # Show disk usage
                echo "║ Disk Usage:"
                if [[ -f "$IMG_FILE" ]]; then
                    echo "║   $(du -h "$IMG_FILE" | cut -f1) used"
                    echo "║   Format: $(qemu-img info "$IMG_FILE" | grep -oP 'format: \K\w+')"
                fi
            fi
            echo "╚══════════════════════════════════════════════════════════════╝"
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                     Configuration                           ║"
            echo "╠══════════════════════════════════════════════════════════════╣"
            echo "║ Memory: $MEMORY MB"
            echo "║ CPUs:   $CPUS"
            echo "║ Disk:   $DISK_SIZE"
            echo "╚══════════════════════════════════════════════════════════════╝"
        fi
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to show VM logs
show_vm_logs() {
    local vm_name=$1
    
    local latest_log=$(ls -t "$LOG_DIR/$vm_name"-*.log 2>/dev/null | head -1)
    if [[ -f "$latest_log" ]]; then
        print_status "INFO" "Showing last 50 lines of logs for VM: $vm_name"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                          VM Logs                            ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        tail -n 50 "$latest_log" | while read line; do
            echo "║ $line"
        done
        echo "╚══════════════════════════════════════════════════════════════╝"
        
        # Check for common errors
        if grep -q "failed to initialize KVM" "$latest_log"; then
            print_status "ERROR" "KVM initialization failed"
            print_status "INFO" "Run: sudo modprobe kvm && sudo chmod 666 /dev/kvm"
        fi
    else
        print_status "INFO" "No log files found for VM: $vm_name"
    fi
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function to update script
update_script() {
    print_status "INFO" "Checking for updates..."
    
    if ! command -v curl &> /dev/null; then
        print_status "ERROR" "curl is required for updates"
        return 1
    fi
    
    local temp_file=$(mktemp)
    if curl -fsSL "$SCRIPT_URL" -o "$temp_file"; then
        local remote_version=$(grep -m1 '^VERSION=' "$temp_file" | cut -d'"' -f2)
        
        if [[ "$remote_version" != "$VERSION" ]]; then
            print_status "INFO" "New version available: $remote_version (current: $VERSION)"
            read -p "$(print_status "INPUT" "Update now? (y/N): ")" -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Replace current script
                cp "$temp_file" "$0"
                chmod +x "$0"
                print_status "SUCCESS" "Script updated to version $remote_version"
                print_status "INFO" "Please restart the script"
                exit 0
            fi
        else
            print_status "SUCCESS" "You have the latest version: $VERSION"
        fi
    else
        print_status "ERROR" "Failed to check for updates"
    fi
    
    rm -f "$temp_file"
}

# Function to show help
show_help() {
    display_header
    cat << "EOF"
Usage: bash <(curl -fsSL https://raw.githubusercontent.com/yourusername/zynexforge-vm-manager/main/vm.sh)

Commands available in the interactive menu:

1. Create a new VM      - Set up a new virtual machine with various OS options
2. Start a VM           - Launch an existing virtual machine
3. Stop a VM            - Gracefully shut down a running VM
4. Show VM info         - Display detailed configuration of a VM
5. Show VM performance  - View resource usage and metrics
6. Show VM logs         - Display log files for troubleshooting
7. Delete a VM          - Remove a VM and all its data

Features:
- KVM acceleration with automatic setup
- Multiple OS support (Ubuntu, Debian, CentOS, Fedora, etc.)
- Cloud-init integration for easy configuration
- Network options (NAT, Bridge)
- Port forwarding
- GUI and console modes
- Automatic dependency installation
- Update checker

Troubleshooting:
- If KVM fails, ensure virtualization is enabled in BIOS
- Run with sudo if you encounter permission issues
- Check logs for detailed error information

For support and issues, visit:
https://github.com/yourusername/zynexforge-vm-manager
EOF
    echo
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        # Show system info
        echo "┌──────────────────────────────────────────────────────────────┐"
        echo "│ System Information                                           │"
        echo "├──────────────────────────────────────────────────────────────┤"
        echo "│ Hostname: $(hostname)"
        echo "│ OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
        echo "│ Kernel: $(uname -r)"
        echo "│ KVM: $(if [[ -e /dev/kvm ]]; then echo "Available ✓"; else echo "Not available ✗"; fi)"
        echo "│ VMs: $vm_count"
        echo "└──────────────────────────────────────────────────────────────┘"
        echo
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Existing VMs ($vm_count):"
            echo "┌────┬──────────────────────────────┬──────────────┐"
            echo "│ #  │ Name                         │ Status       │"
            echo "├────┼──────────────────────────────┼──────────────┤"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if is_vm_running "${vms[$i]}"; then
                    status="Running"
                fi
                printf "│ %-2d │ %-28s │ %-12s │\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo "└────┴──────────────────────────────┴──────────────┘"
            echo
        fi
        
        echo "Main Menu:"
        echo "  1) 🚀 Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) ▶️  Start a VM"
            echo "  3) ⏹️  Stop a VM"
            echo "  4) ℹ️  Show VM info"
            echo "  5) 📊 Show VM performance"
            echo "  6) 📝 Show VM logs"
            echo "  7) 🗑️  Delete a VM"
        fi
        echo "  8) 🔄 Check for updates"
        echo "  9) ❓ Help"
        echo "  0) 👋 Exit"
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
                else
                    print_status "ERROR" "No VMs available"
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
                else
                    print_status "ERROR" "No VMs available"
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
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show logs: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_logs "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            8)
                update_script
                ;;
            9)
                show_help
                ;;
            0)
                print_status "INFO" "Thank you for using ZynexForge VM Manager! 👋"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Initialize script
init_directories
check_dependencies

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04 LTS (Jammy)"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04 LTS (Noble)"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11 (Bullseye)"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12 (Bookworm)"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
    ["OpenSUSE Leap 15.5"]="opensuse|leap15.5|https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-JeOS.x86_64-15.5-OpenStack.qcow2|opensuse15|opensuse|opensuse"
)

# Start the main menu
main_menu
