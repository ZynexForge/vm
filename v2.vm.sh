#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge V2 - Production VPS Platform
# =============================

# Configuration - all in user space
readonly CONFIG_DIR="$HOME/.zynexforge"
readonly VM_BASE_DIR="$HOME/zynexforge/vms"
readonly LOG_DIR="$HOME/.zynexforge/logs"
readonly LOG_FILE="$LOG_DIR/zynexforge.log"

# Function to display header
display_header() {
    clear
    cat << "EOF"
__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 

                    ⚡ ZynexForge V2 ⚡
              Production VPS/VM Management Platform
========================================================================
EOF
    echo
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
    # Log to file
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$type] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Safe function to check sudo
check_sudo() {
    if command_exists sudo && sudo -n true 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check dependencies from your list
check_dependencies() {
    print_status "INFO" "Checking for required packages..."
    
    # Essential packages that must be present
    local essential_packages=("qemu-system-x86_64" "qemu-img" "wget" "curl" "git" "unzip")
    
    for pkg in "${essential_packages[@]}"; do
        if ! command_exists "$pkg"; then
            print_status "ERROR" "Essential package not found: $pkg"
            print_status "INFO" "Please install using your package manager"
            exit 1
        fi
    done
    
    # Check for cloud-utils (for cloud-localds)
    if ! command_exists cloud-localds; then
        print_status "WARN" "cloud-localds not found, some features may be limited"
    fi
    
    # Check for virtualization support
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        print_status "SUCCESS" "KVM acceleration available"
    else
        print_status "WARN" "KVM not available, will use software emulation"
    fi
}

# Function to initialize platform
initialize_platform() {
    print_status "INFO" "Initializing ZynexForge V2 platform..."
    
    # Create directories
    mkdir -p "$CONFIG_DIR"/{profiles,scripts,networks} 2>/dev/null || true
    mkdir -p "$VM_BASE_DIR"/{images,configs,disks,isos} 2>/dev/null || true
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    
    # Create log file
    touch "$LOG_FILE" 2>/dev/null || true
    
    # Initialize VM profiles
    initialize_vm_profiles
    
    print_status "SUCCESS" "Platform initialized in user space"
}

# Function to initialize VM profiles
initialize_vm_profiles() {
    cat << 'EOF' > "$CONFIG_DIR/profiles/default.yaml"
profiles:
  web:
    description: "Optimized for HTTP/HTTPS hosting"
    cpu_type: "host"
    memory: 2048
    cpus: 2
    disk: "20G"
    network: "virtio"
    ports: [22, 80, 443]
    
  backend:
    description: "APIs, databases, workers"
    cpu_type: "host"
    memory: 4096
    cpus: 4
    disk: "50G"
    network: "virtio"
    ports: [22, 3306, 5432, 6379]
    
  llm-ai:
    description: "High CPU/Memory for AI workloads"
    cpu_type: "host"
    memory: 16384
    cpus: 8
    disk: "100G"
    network: "virtio"
    ports: [22, 7860, 8000, 8080]
    
  game-server:
    description: "Low-latency game servers"
    cpu_type: "host"
    memory: 8192
    cpus: 4
    disk: "100G"
    network: "virtio"
    ports: [22, 25565, 27015]
    
  desktop:
    description: "XRDP-ready desktop VM"
    cpu_type: "host"
    memory: 4096
    cpus: 4
    disk: "50G"
    network: "virtio"
    ports: [22, 3389]
    graphics: true
    
  heavy-task:
    description: "High CPU/Memory/Disk workloads"
    cpu_type: "host"
    memory: 32768
    cpus: 16
    disk: "500G"
    network: "virtio"
    ports: [22]
EOF
    print_status "SUCCESS" "VM profiles initialized"
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_BASE_DIR/configs" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_BASE_DIR/configs/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file" 2>/dev/null
        return 0
    else
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_BASE_DIR/configs/$VM_NAME.conf"
    
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" << EOF
VM_NAME="$VM_NAME"
VM_PROFILE="$VM_PROFILE"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
PUBLIC_IP="$PUBLIC_IP"
MAC_ADDRESS="$MAC_ADDRESS"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
XRDP_ENABLED="$XRDP_ENABLED"
XRDP_PORT="$XRDP_PORT"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved"
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

    # VM Profile Selection
    print_status "INFO" "Select VM Profile:"
    echo "  1) WEB - Website hosting (HTTP/HTTPS)"
    echo "  2) BACKEND - APIs, databases, workers"
    echo "  3) LLM/AI - High CPU/Memory for AI workloads"
    echo "  4) GAME SERVER - Low-latency game servers"
    echo "  5) DESKTOP - XRDP-ready desktop"
    echo "  6) HEAVY TASK - High CPU/Memory/Disk workloads"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter profile choice (1-6): ")" profile_choice
        case $profile_choice in
            1) VM_PROFILE="web" ;;
            2) VM_PROFILE="backend" ;;
            3) VM_PROFILE="llm-ai" ;;
            4) VM_PROFILE="game-server" ;;
            5) VM_PROFILE="desktop" ;;
            6) VM_PROFILE="heavy-task" ;;
            *) print_status "ERROR" "Invalid selection. Try again."; continue ;;
        esac
        break
    done

    # VM Name
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if [[ "$VM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            if [[ -f "$VM_BASE_DIR/configs/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        else
            print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
        fi
    done

    # Hostname
    read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
    HOSTNAME="${HOSTNAME:-$VM_NAME}"

    # Username
    read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

    # Password
    read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
    PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
    echo

    # Network Configuration
    print_status "INFO" "Network Configuration:"
    echo "Note: You can use NAT networking for testing or configure bridged networking later"
    
    # Simple IP assignment
    local ip_base="192.168.100"
    local ip_num=100
    
    # Find next available IP
    for i in {100..254}; do
        if ! grep -r "$ip_base.$i" "$VM_BASE_DIR/configs/" >/dev/null 2>&1; then
            ip_num=$i
            break
        fi
    done
    
    PUBLIC_IP="$ip_base.$ip_num/24"
    print_status "INFO" "Auto-assigned IP: $PUBLIC_IP"
    
    read -p "$(print_status "INPUT" "Press Enter to use $PUBLIC_IP or enter custom IP (e.g., 192.168.1.10/24): ")" custom_ip
    if [ -n "$custom_ip" ]; then
        if [[ "$custom_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            PUBLIC_IP="$custom_ip"
        else
            print_status "ERROR" "Invalid IP format, using $PUBLIC_IP"
        fi
    fi

    # MAC Address
    MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//' 2>/dev/null || echo "12:34:56")"
    print_status "INFO" "Auto-generated MAC: $MAC_ADDRESS"

    # Resource allocation based on profile
    load_profile_settings "$VM_PROFILE"
    
    # Show proposed resources
    print_status "INFO" "Profile '$VM_PROFILE' settings:"
    echo "  Memory: ${MEMORY}MB"
    echo "  CPUs: ${CPUS}"
    echo "  Disk: ${DISK_SIZE}"
    
    read -p "$(print_status "INPUT" "Press Enter to accept or 'c' to customize: ")" custom_choice
    if [[ "$custom_choice" == "c" ]]; then
        while true; do
            read -p "$(print_status "INPUT" "Memory in MB (default: ${MEMORY}): ")" custom_memory
            if [[ "$custom_memory" =~ ^[0-9]+$ ]]; then
                MEMORY="$custom_memory"
                break
            elif [ -z "$custom_memory" ]; then
                break
            else
                print_status "ERROR" "Must be a number"
            fi
        done

        while true; do
            read -p "$(print_status "INPUT" "Number of CPUs (default: ${CPUS}): ")" custom_cpus
            if [[ "$custom_cpus" =~ ^[0-9]+$ ]]; then
                CPUS="$custom_cpus"
                break
            elif [ -z "$custom_cpus" ]; then
                break
            else
                print_status "ERROR" "Must be a number"
            fi
        done

        while true; do
            read -p "$(print_status "INPUT" "Disk size (default: ${DISK_SIZE}): ")" custom_disk
            if [[ "$custom_disk" =~ ^[0-9]+[GgMm]$ ]]; then
                DISK_SIZE="$custom_disk"
                break
            elif [ -z "$custom_disk" ]; then
                break
            else
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M)"
            fi
        done
    fi

    # SSH Port
    SSH_PORT="22"
    
    # XRDP option
    if [[ "$VM_PROFILE" == "desktop" ]]; then
        XRDP_ENABLED="true"
        XRDP_PORT="3389"
        print_status "INFO" "XRDP will be enabled for desktop VM"
    else
        XRDP_ENABLED="false"
        XRDP_PORT="3389"
    fi

    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # Create VM
    print_status "INFO" "Creating VM '$VM_NAME'..."
    if create_vm_image && create_vm_configuration; then
        save_vm_config
        
        print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
        print_status "INFO" "IP Address: ${PUBLIC_IP%/*}"
        print_status "INFO" "SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
        
        if [[ "$XRDP_ENABLED" == "true" ]]; then
            print_status "INFO" "XRDP: Available at ${PUBLIC_IP%/*}:$XRDP_PORT"
        fi
        
        print_status "INFO" "Start VM with: $VM_BASE_DIR/configs/${VM_NAME}-start.sh"
    else
        print_status "ERROR" "Failed to create VM '$VM_NAME'"
        return 1
    fi
}

# Function to load profile settings
load_profile_settings() {
    local profile=$1
    
    case $profile in
        "web")
            MEMORY=2048
            CPUS=2
            DISK_SIZE="20G"
            ;;
        "backend")
            MEMORY=4096
            CPUS=4
            DISK_SIZE="50G"
            ;;
        "llm-ai")
            MEMORY=16384
            CPUS=8
            DISK_SIZE="100G"
            ;;
        "game-server")
            MEMORY=8192
            CPUS=4
            DISK_SIZE="100G"
            ;;
        "desktop")
            MEMORY=4096
            CPUS=4
            DISK_SIZE="50G"
            ;;
        "heavy-task")
            MEMORY=32768
            CPUS=16
            DISK_SIZE="500G"
            ;;
        *)
            MEMORY=1024
            CPUS=1
            DISK_SIZE="10G"
            ;;
    esac
}

# Function to create VM image
create_vm_image() {
    local image_file="$VM_BASE_DIR/images/${VM_NAME}.qcow2"
    
    print_status "INFO" "Preparing VM image..."
    
    # Create directories
    mkdir -p "$VM_BASE_DIR/images" "$VM_BASE_DIR/disks" "$VM_BASE_DIR/isos" "$VM_BASE_DIR/configs"
    
    # Check if image already exists
    if [[ -f "$image_file" ]]; then
        print_status "INFO" "Reusing existing base image"
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! wget --progress=bar:force -q --show-progress "$IMG_URL" -O "${image_file}.tmp"; then
            print_status "ERROR" "Failed to download image"
            return 1
        fi
        mv "${image_file}.tmp" "$image_file"
    fi
    
    # Create disk with specified size
    local disk_file="$VM_BASE_DIR/disks/${VM_NAME}.qcow2"
    if ! qemu-img create -f qcow2 -F qcow2 -b "$image_file" "$disk_file" "$DISK_SIZE" 2>/dev/null; then
        print_status "ERROR" "Failed to create disk image"
        return 1
    fi
    
    # Create cloud-init ISO
    create_cloud_init_iso
    
    return 0
}

# Function to create cloud-init ISO
create_cloud_init_iso() {
    local seed_dir="$VM_BASE_DIR/configs/${VM_NAME}-seed"
    mkdir -p "$seed_dir"
    
    # Create user-data
    cat > "$seed_dir/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null | tr -d '\n' || echo "$PASSWORD")
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
runcmd:
  - echo "vm_name=$VM_NAME" >> /etc/environment
  - echo "vm_profile=$VM_PROFILE" >> /etc/environment
EOF
    
    # Create meta-data
    cat > "$seed_dir/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF
    
    # Create network-config
    cat > "$seed_dir/network-config" <<EOF
version: 2
ethernets:
  ens3:
    match:
      macaddress: "$MAC_ADDRESS"
    addresses:
      - $PUBLIC_IP
    gateway4: $(echo $PUBLIC_IP | cut -d'/' -f1 | sed 's/[0-9]*$/1/')
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF
    
    # Create ISO if cloud-localds is available
    if command_exists cloud-localds; then
        if cloud-localds "$VM_BASE_DIR/isos/${VM_NAME}-seed.iso" \
            "$seed_dir/user-data" \
            "$seed_dir/meta-data" \
            --network-config "$seed_dir/network-config" 2>/dev/null; then
            print_status "SUCCESS" "Cloud-init ISO created"
        else
            print_status "WARN" "Failed to create cloud-init ISO"
        fi
    else
        print_status "WARN" "cloud-localds not available, using simple config"
        # Create a simple config drive
        mkdir -p "$seed_dir/openstack/latest"
        cp "$seed_dir/user-data" "$seed_dir/openstack/latest/user_data"
        cp "$seed_dir/meta-data" "$seed_dir/openstack/latest/meta_data.json"
        cp "$seed_dir/network-config" "$seed_dir/openstack/latest/network_data.json"
        
        # Create ISO using mkisofs if available
        if command_exists mkisofs; then
            mkisofs -o "$VM_BASE_DIR/isos/${VM_NAME}-seed.iso" -R -V config-2 "$seed_dir" 2>/dev/null && \
            print_status "SUCCESS" "Config ISO created"
        fi
    fi
    
    # Cleanup
    rm -rf "$seed_dir"
    return 0
}

# Function to create VM configuration
create_vm_configuration() {
    print_status "INFO" "Creating VM configuration..."
    
    # Create a startup script
    local startup_script="$VM_BASE_DIR/configs/${VM_NAME}-start.sh"
    local disk_file="$VM_BASE_DIR/disks/${VM_NAME}.qcow2"
    local seed_file="$VM_BASE_DIR/isos/${VM_NAME}-seed.iso"
    
    # Check if KVM is available
    local kvm_opt=""
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        kvm_opt="-enable-kvm"
        print_status "INFO" "Using KVM acceleration"
    else
        print_status "WARN" "KVM not available, using software emulation"
    fi
    
    # Create startup script
    cat > "$startup_script" <<EOF
#!/bin/bash
# ZynexForge VM Startup Script
# VM: $VM_NAME
# Profile: $VM_PROFILE

set -e

VM_NAME="$VM_NAME"
DISK_FILE="$disk_file"
SEED_FILE="$seed_file"
MEMORY="$MEMORY"
CPUS="$CPUS"
MAC_ADDR="$MAC_ADDRESS"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\${GREEN}Starting ZynexForge VM: \$VM_NAME\${NC}"
echo "Profile: $VM_PROFILE"
echo "Memory: \${MEMORY}MB"
echo "CPUs: \$CPUS"
echo "IP Address: ${PUBLIC_IP%/*}"
echo "MAC Address: \$MAC_ADDR"
echo ""
echo -e "\${YELLOW}Connection Information:\${NC}"
echo "SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
echo "Password: $PASSWORD"
EOF

    # Add XRDP info if enabled
    if [[ "$XRDP_ENABLED" == "true" ]]; then
        cat >> "$startup_script" <<EOF
echo "XRDP: Connect to ${PUBLIC_IP%/*}:$XRDP_PORT"
EOF
    fi

    cat >> "$startup_script" <<EOF
echo ""
echo -e "\${YELLOW}To stop the VM, press: Ctrl+A, then X\${NC}"
echo ""

# Check if files exist
if [ ! -f "\$DISK_FILE" ]; then
    echo -e "\${RED}Error: Disk image not found: \$DISK_FILE\${NC}"
    exit 1
fi

if [ ! -f "\$SEED_FILE" ]; then
    echo -e "\${YELLOW}Warning: Seed file not found, using network configuration\${NC}"
    SEED_OPT=""
else
    SEED_OPT="-drive file=\$SEED_FILE,format=raw,if=virtio"
fi

# Start QEMU
echo "Starting QEMU..."
exec qemu-system-x86_64 \$kvm_opt \\
  -m \$MEMORY \\
  -smp \$CPUS \\
  -cpu host \\
  -drive file=\$DISK_FILE,format=qcow2,if=virtio \\
  \$SEED_OPT \\
  -netdev user,id=n0,hostfwd=tcp::${SSH_PORT}-:22 \\
  -device virtio-net-pci,netdev=n0,mac=\$MAC_ADDR \\
  -nographic \\
  -serial mon:stdio
EOF

    chmod +x "$startup_script"
    
    # Create a simple service file template
    local service_file="$VM_BASE_DIR/configs/${VM_NAME}.service"
    
    cat > "$service_file" <<EOF
[Unit]
Description=ZynexForge VM: $VM_NAME
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$startup_script
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    print_status "SUCCESS" "VM configuration created"
    return 0
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        
        local startup_script="$VM_BASE_DIR/configs/${vm_name}-start.sh"
        
        if [ -f "$startup_script" ]; then
            # Check if already running
            if pgrep -f "qemu.*$vm_name" >/dev/null; then
                print_status "WARN" "VM $vm_name is already running"
                return 0
            fi
            
            print_status "INFO" "IP Address: ${PUBLIC_IP%/*}"
            print_status "INFO" "SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
            
            if [[ "$XRDP_ENABLED" == "true" ]]; then
                print_status "INFO" "XRDP: Connect to ${PUBLIC_IP%/*}:$XRDP_PORT"
            fi
            
            # Run in background with screen for detachment
            if command_exists screen; then
                screen -dmS "zynexforge-$vm_name" "$startup_script"
                print_status "SUCCESS" "VM $vm_name started in screen session: zynexforge-$vm_name"
                print_status "INFO" "Attach to screen: screen -r zynexforge-$vm_name"
                print_status "INFO" "Detach from screen: Ctrl+A, then D"
            elif command_exists tmux; then
                tmux new-session -d -s "zynexforge-$vm_name" "$startup_script"
                print_status "SUCCESS" "VM $vm_name started in tmux session: zynexforge-$vm_name"
                print_status "INFO" "Attach to tmux: tmux attach-session -t zynexforge-$vm_name"
                print_status "INFO" "Detach from tmux: Ctrl+B, then D"
            else
                # Run in background
                "$startup_script" &
                local pid=$!
                print_status "SUCCESS" "VM $vm_name started with PID: $pid"
                print_status "INFO" "To stop: kill $pid"
            fi
        else
            print_status "ERROR" "Startup script not found: $startup_script"
        fi
    else
        print_status "ERROR" "VM configuration not found: $vm_name"
    fi
}

# Function to stop a VM
stop_vm() {
    local vm_name=$1
    
    print_status "INFO" "Stopping VM: $vm_name"
    
    # Try to stop via screen/tmux first
    if command_exists screen && screen -list | grep -q "zynexforge-$vm_name"; then
        screen -S "zynexforge-$vm_name" -X quit
        print_status "SUCCESS" "Stopped screen session: zynexforge-$vm_name"
        return 0
    fi
    
    if command_exists tmux && tmux has-session -t "zynexforge-$vm_name" 2>/dev/null; then
        tmux kill-session -t "zynexforge-$vm_name"
        print_status "SUCCESS" "Stopped tmux session: zynexforge-$vm_name"
        return 0
    fi
    
    # Find and kill QEMU process
    local pids=$(pgrep -f "qemu.*$vm_name" 2>/dev/null || true)
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill "$pid" 2>/dev/null && print_status "INFO" "Stopped process $pid"
        done
        print_status "SUCCESS" "VM $vm_name stopped"
    else
        print_status "INFO" "No running process found for VM $vm_name"
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Stop VM first
        stop_vm "$vm_name"
        
        # Remove all VM files
        rm -f "$VM_BASE_DIR/disks/${vm_name}.qcow2" \
              "$VM_BASE_DIR/isos/${vm_name}-seed.iso" \
              "$VM_BASE_DIR/configs/${vm_name}.conf" \
              "$VM_BASE_DIR/configs/${vm_name}-start.sh" \
              "$VM_BASE_DIR/configs/${vm_name}.service" \
              "$VM_BASE_DIR/images/${vm_name}.qcow2" 2>/dev/null || true
        
        # Clean up screen/tmux sessions
        if command_exists screen; then
            screen -wipe 2>/dev/null || true
        fi
        
        if command_exists tmux; then
            tmux kill-session -t "zynexforge-$vm_name" 2>/dev/null || true
        fi
        
        print_status "SUCCESS" "VM '$vm_name' has been deleted"
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to enable XRDP (one-click feature)
enable_xrdp() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Enabling XRDP for $vm_name..."
        
        local vm_ip="${PUBLIC_IP%/*}"
        
        # Check if VM is running
        if ! pgrep -f "qemu.*$vm_name" >/dev/null; then
            print_status "ERROR" "VM is not running. Please start the VM first."
            return 1
        fi
        
        # Create installation script
        local install_script="/tmp/install_xrdp_${vm_name}.sh"
        
        cat > "$install_script" <<'EOF'
#!/bin/bash
echo "Installing XRDP on VM..."
echo "This will install XRDP and configure it for remote desktop access"

# Detect OS and install XRDP
if [ -f /etc/os-release ]; then
    . /etc/os-release
    
    case $ID in
        ubuntu|debian)
            echo "Detected Ubuntu/Debian"
            sudo apt update
            sudo apt install -y xrdp xorgxrdp
            sudo systemctl enable xrdp
            sudo systemctl start xrdp
            echo "XRDP installed and started on port 3389"
            ;;
        fedora|centos|rhel)
            echo "Detected Fedora/CentOS/RHEL"
            if command -v dnf >/dev/null; then
                sudo dnf install -y xrdp xorgxrdp
            else
                sudo yum install -y xrdp xorgxrdp
            fi
            sudo systemctl enable xrdp
            sudo systemctl start xrdp
            sudo firewall-cmd --permanent --add-port=3389/tcp
            sudo firewall-cmd --reload
            echo "XRDP installed and started on port 3389"
            ;;
        *)
            echo "Unsupported OS: $ID"
            exit 1
            ;;
    esac
    
    # Create desktop session
    if [ -x /usr/bin/startxfce4 ]; then
        echo "startxfce4" > ~/.xsession
    elif [ -x /usr/bin/xfce4-session ]; then
        echo "xfce4-session" > ~/.xsession
    elif [ -x /usr/bin/gnome-session ]; then
        echo "gnome-session" > ~/.xsession
    else
        echo "xterm" > ~/.xsession
    fi
    
    echo ""
    echo "XRDP setup complete!"
    echo "Connect using: $(hostname -I | awk '{print $1}'):3389"
else
    echo "Cannot detect OS"
    exit 1
fi
EOF
        
        # Copy script to VM and execute
        print_status "INFO" "Setting up XRDP on $vm_name ($vm_ip)..."
        
        # Try to copy script to VM using SSH
        if command_exists sshpass; then
            if sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                "$install_script" "$USERNAME@$vm_ip:/tmp/install_xrdp.sh" 2>/dev/null; then
                
                if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                    "$USERNAME@$vm_ip" "bash /tmp/install_xrdp.sh" 2>/dev/null; then
                    
                    # Update config
                    XRDP_ENABLED="true"
                    save_vm_config
                    
                    print_status "SUCCESS" "XRDP enabled for $vm_name"
                    print_status "INFO" "Connect using: $vm_ip:3389"
                    print_status "INFO" "Username: $USERNAME"
                    print_status "INFO" "Password: $PASSWORD"
                else
                    print_status "ERROR" "Failed to execute XRDP installation on VM"
                    print_status "INFO" "You can manually install XRDP:"
                    echo "  1. ssh $USERNAME@$vm_ip"
                    echo "  2. Run: sudo apt install xrdp xorgxrdp"
                    echo "  3. Run: sudo systemctl enable --now xrdp"
                fi
            else
                print_status "ERROR" "Failed to copy installation script to VM"
                print_status "INFO" "Make sure VM is running and SSH is accessible"
            fi
        else
            print_status "WARN" "sshpass not available"
            print_status "INFO" "To enable XRDP manually:"
            echo "  1. Connect to VM: ssh $USERNAME@$vm_ip"
            echo "  2. Install XRDP:"
            echo "     Ubuntu/Debian: sudo apt install xrdp xorgxrdp"
            echo "     CentOS/RHEL: sudo yum install xrdp xorgxrdp"
            echo "  3. Start XRDP: sudo systemctl enable --now xrdp"
            echo "  4. Connect to: $vm_ip:3389"
        fi
        
        rm -f "$install_script"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "Profile: $VM_PROFILE"
        echo "Status: $(pgrep -f "qemu.*$vm_name" >/dev/null && echo "Running" || echo "Stopped")"
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "IP Address: ${PUBLIC_IP%/*}"
        echo "MAC Address: $MAC_ADDRESS"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "XRDP Enabled: $XRDP_ENABLED"
        echo "Created: $CREATED"
        echo "=========================================="
        
        # Show startup command
        local startup_script="$VM_BASE_DIR/configs/${vm_name}-start.sh"
        if [ -f "$startup_script" ]; then
            echo "Start script: $startup_script"
        fi
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    else
        print_status "ERROR" "VM not found: $vm_name"
    fi
}

# Function to show VM performance
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "Performance for VM: $vm_name"
        echo "=========================================="
        
        # Check if running
        local pid=$(pgrep -f "qemu.*$vm_name" | head -1)
        if [ -n "$pid" ]; then
            echo "Status: Running (PID: $pid)"
            echo ""
            
            # Show process info
            if command_exists htop; then
                echo "Use 'htop' to monitor process $pid"
            elif command_exists top; then
                echo "Use 'top -p $pid' to monitor"
            fi
            
            # Show resource usage
            if command_exists ps; then
                echo ""
                echo "Process Stats:"
                ps -p "$pid" -o pid,%cpu,%mem,vsz,rss,cmd --no-headers 2>/dev/null || true
            fi
        else
            echo "Status: Stopped"
        fi
        
        echo ""
        echo "Allocated Resources:"
        echo "  Memory: $MEMORY MB"
        echo "  CPUs: $CPUS"
        echo "  Disk: $DISK_SIZE"
        
        # Show disk usage
        local disk_file="$VM_BASE_DIR/disks/${vm_name}.qcow2"
        if [ -f "$disk_file" ]; then
            echo ""
            echo "Disk Usage:"
            ls -lh "$disk_file"
        fi
        
        echo "=========================================="
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to setup bridged networking
setup_bridged_networking() {
    print_status "INFO" "Bridged Networking Setup"
    echo ""
    echo "For production use with public IPs, you need to setup bridged networking."
    echo ""
    echo "Option 1: Manual Setup"
    echo "----------------------"
    echo "1. Install bridge utilities:"
    echo "   sudo apt install bridge-utils"
    echo ""
    echo "2. Create bridge configuration (/etc/netplan/00-zynexforge.yaml):"
    cat << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
  bridges:
    br0:
      interfaces: [eth0]
      addresses: [YOUR_PUBLIC_IP/24]
      gateway4: YOUR_GATEWAY
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
    echo ""
    echo "3. Apply: sudo netplan apply"
    echo ""
    echo "Option 2: Use macvtap (for cloud/VPS environments)"
    echo "--------------------------------------------------"
    echo "Modify VM startup script to use:"
    echo "  -netdev tap,id=n0 -device virtio-net-pci,netdev=n0"
    echo ""
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function to repair platform
repair_platform() {
    print_status "INFO" "Repairing platform..."
    
    # Recreate directories
    mkdir -p "$CONFIG_DIR" "$VM_BASE_DIR" "$LOG_DIR"
    mkdir -p "$CONFIG_DIR"/{profiles,scripts,networks}
    mkdir -p "$VM_BASE_DIR"/{images,configs,disks,isos}
    
    # Reinitialize profiles
    initialize_vm_profiles
    
    print_status "SUCCESS" "Platform repaired"
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if pgrep -f "qemu.*${vms[$i]}" >/dev/null; then
                    status="Running"
                fi
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Main Menu:"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Show VM performance"
            echo "  6) Enable XRDP (one-click)"
            echo "  7) Edit VM configuration"
            echo "  8) Delete a VM"
        fi
        echo "  9) Setup Bridged Networking"
        echo " 10) Repair Platform"
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
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to enable XRDP: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        enable_xrdp "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    # Simple edit - just show config file location
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        local vm="${vms[$((vm_num-1))]}"
                        local config_file="$VM_BASE_DIR/configs/$vm.conf"
                        print_status "INFO" "Edit configuration file: $config_file"
                        print_status "INFO" "After editing, you may need to recreate the VM"
                        read -p "$(print_status "INPUT" "Press Enter to continue...")"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            9)
                setup_bridged_networking
                ;;
            10)
                repair_platform
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# Main execution
check_dependencies
initialize_platform
main_menu
