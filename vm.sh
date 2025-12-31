#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager
# Advanced Virtualization Platform
# =============================

# Function to display header
display_header() {
    clear
    cat << "EOF"
__________                           ___________                         
\____    /___.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 

========================================================================
               ZYNEXFORGE ADVANCED VM MANAGEMENT SYSTEM
               With AMD CPU Optimization & Smart Networking
========================================================================
EOF
    echo
}

# Function to display colored output with better UI
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[ℹ]\033[0m \033[1;37m$message\033[0m" ;;
        "WARN") echo -e "\033[1;33m[⚠]\033[0m \033[1;33m$message\033[0m" ;;
        "ERROR") echo -e "\033[1;31m[✗]\033[0m \033[1;31m$message\033[0m" ;;
        "SUCCESS") echo -e "\033[1;32m[✓]\033[0m \033[1;32m$message\033[0m" ;;
        "INPUT") echo -e "\033[1;36m[?]\033[0m \033[1;36m$message\033[0m" ;;
        "MENU") echo -e "\033[1;35m[→]\033[0m \033[1;37m$message\033[0m" ;;
        "CPU") echo -e "\033[1;38;5;208m[⚡]\033[0m \033[1;38;5;208m$message\033[0m" ;;
        "NET") echo -e "\033[1;38;5;51m[🌐]\033[0m \033[1;38;5;51m$message\033[0m" ;;
        *) echo "[$type] $message" ;;
    esac
}

# Function to display progress bar
show_progress() {
    local current=$1
    local total=$2
    local msg=$3
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r\033[1;36m[%3d%%]\033[0m \033[1;37m%s: [\033[1;32m" "$percentage" "$msg"
    printf "%${filled}s" "" | tr ' ' '█'
    printf "\033[1;37m%${empty}s\033[0m]" ""
    
    if [ $current -eq $total ]; then
        echo
    fi
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
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 23 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (23-65535)"
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
        "mac")
            if ! [[ "$value" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                print_status "ERROR" "Invalid MAC address format (use: XX:XX:XX:XX:XX:XX)"
                return 1
            fi
            ;;
        "ip")
            if ! [[ "$value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                print_status "ERROR" "Invalid IP address format"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "bridge-utils" "dnsmasq")
    local missing_deps=()
    
    print_status "INFO" "Checking system dependencies..."
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Installing required packages..."
        
        if command -v apt &> /dev/null; then
            sudo apt update
            sudo apt install -y qemu-system cloud-image-utils wget bridge-utils dnsmasq libvirt-daemon-system virt-manager
        elif command -v yum &> /dev/null; then
            sudo yum install -y qemu-kvm qemu-img wget bridge-utils dnsmasq libvirt virt-install
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y qemu-kvm qemu-img wget bridge-utils dnsmasq libvirt virt-install
        else
            print_status "ERROR" "Please install the missing packages manually"
            exit 1
        fi
    fi
    
    # Check for AMD CPU optimizations
    if grep -q "AMD" /proc/cpuinfo; then
        print_status "CPU" "AMD CPU detected - Enabling optimizations"
        AMD_CPU=true
    else
        AMD_CPU=false
    fi
    
    # Check for virtualization support
    if grep -q -E "vmx|svm" /proc/cpuinfo; then
        print_status "SUCCESS" "Hardware virtualization support detected"
    else
        print_status "WARN" "Hardware virtualization not detected - Performance may be limited"
    fi
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
    if [ -f "network-data" ]; then rm -f "network-data"; fi
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
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset NETWORK_TYPE BRIDGE_INTERFACE MAC_ADDRESS STATIC_IP NETMASK GATEWAY DNS_SERVERS
        unset ENABLE_VIRTIO NETWORK_QUEUES BANDWIDTH_LIMIT CPU_MODEL ACCELERATOR THREADS
        unset ENABLE_HUGE_PAGES CACHE_MODE IO_THREADS ENABLE_TPM ENABLE_SECURE_BOOT
        
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
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
NETWORK_TYPE="$NETWORK_TYPE"
BRIDGE_INTERFACE="${BRIDGE_INTERFACE:-}"
MAC_ADDRESS="${MAC_ADDRESS:-}"
STATIC_IP="${STATIC_IP:-}"
NETMASK="${NETMASK:-}"
GATEWAY="${GATEWAY:-}"
DNS_SERVERS="${DNS_SERVERS:-}"
ENABLE_VIRTIO="${ENABLE_VIRTIO:-true}"
NETWORK_QUEUES="${NETWORK_QUEUES:-4}"
BANDWIDTH_LIMIT="${BANDWIDTH_LIMIT:-}"
CPU_MODEL="${CPU_MODEL:-host}"
ACCELERATOR="${ACCELERATOR:-kvm}"
THREADS="${THREADS:-2}"
ENABLE_HUGE_PAGES="${ENABLE_HUGE_PAGES:-false}"
CACHE_MODE="${CACHE_MODE:-writeback}"
IO_THREADS="${IO_THREADS:-4}"
ENABLE_TPM="${ENABLE_TPM:-false}"
ENABLE_SECURE_BOOT="${ENABLE_SECURE_BOOT:-false}"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to setup advanced network
setup_network() {
    print_status "NET" "Configuring advanced network options"
    
    # Network type selection
    print_status "INFO" "Select network type:"
    echo "  1) User-mode Networking (NAT) - Default"
    echo "  2) Bridge Networking - For direct LAN access"
    echo "  3) MacVTap - Best performance"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter choice (1-3): ")" net_choice
        case $net_choice in
            1)
                NETWORK_TYPE="user"
                print_status "INFO" "Using user-mode networking (NAT)"
                break
                ;;
            2)
                NETWORK_TYPE="bridge"
                # Get available bridge interfaces
                local bridges=$(brctl show 2>/dev/null | awk 'NR>1 {print $1}')
                if [ -z "$bridges" ]; then
                    print_status "WARN" "No bridge interfaces found. Creating default bridge..."
                    sudo brctl addbr br0 2>/dev/null || true
                    bridges="br0"
                fi
                
                echo "Available bridge interfaces:"
                echo "$bridges" | cat -n
                read -p "$(print_status "INPUT" "Select bridge interface: ")" bridge_num
                BRIDGE_INTERFACE=$(echo "$bridges" | sed -n "${bridge_num}p")
                if [ -z "$BRIDGE_INTERFACE" ]; then
                    BRIDGE_INTERFACE="br0"
                fi
                break
                ;;
            3)
                NETWORK_TYPE="macvtap"
                print_status "INFO" "Using MacVTap networking"
                break
                ;;
            *)
                print_status "ERROR" "Invalid selection"
                ;;
        esac
    done
    
    # MAC Address
    if [ "$NETWORK_TYPE" != "user" ]; then
        read -p "$(print_status "INPUT" "Enter custom MAC address (press Enter for auto-generate): ")" MAC_ADDRESS
        if [ -z "$MAC_ADDRESS" ]; then
            # Generate random MAC
            MAC_ADDRESS="52:54:00:$(dd if=/dev/urandom bs=3 count=1 2>/dev/null | hexdump -e '/1 ":%02x"' | cut -c2-)"
        else
            validate_input "mac" "$MAC_ADDRESS" || MAC_ADDRESS="52:54:00:$(dd if=/dev/urandom bs=3 count=1 2>/dev/null | hexdump -e '/1 ":%02x"' | cut -c2-)"
        fi
        print_status "INFO" "MAC Address: $MAC_ADDRESS"
    fi
    
    # Network performance options
    print_status "INFO" "Network performance options:"
    while true; do
        read -p "$(print_status "INPUT" "Enable VirtIO network driver? (y/n, default: y): ")" virtio_input
        virtio_input="${virtio_input:-y}"
        if [[ "$virtio_input" =~ ^[Yy]$ ]]; then 
            ENABLE_VIRTIO=true
            break
        elif [[ "$virtio_input" =~ ^[Nn]$ ]]; then
            ENABLE_VIRTIO=false
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Number of network queues (1-8, default: 4): ")" queues_input
        queues_input="${queues_input:-4}"
        if validate_input "number" "$queues_input" && [ "$queues_input" -ge 1 ] && [ "$queires_input" -le 8 ]; then
            NETWORK_QUEUES="$queues_input"
            break
        fi
    done
    
    read -p "$(print_status "INPUT" "Bandwidth limit in MB/s (press Enter for unlimited): ")" bw_limit
    if [ -n "$bw_limit" ]; then
        BANDWIDTH_LIMIT="$bw_limit"
    fi
}

# Function to setup AMD CPU optimizations
setup_cpu() {
    print_status "CPU" "Configuring CPU optimizations"
    
    # CPU model selection
    print_status "INFO" "Select CPU model:"
    echo "  1) host (passthrough) - Best performance"
    echo "  2) EPYC - AMD Server CPU profile"
    echo "  3) Ryzen - AMD Desktop CPU profile"
    echo "  4) qemu64 - Generic 64-bit"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter choice (1-4): ")" cpu_choice
        case $cpu_choice in
            1)
                CPU_MODEL="host"
                print_status "CPU" "Using host CPU passthrough"
                break
                ;;
            2)
                CPU_MODEL="EPYC"
                print_status "CPU" "Using AMD EPYC CPU profile"
                break
                ;;
            3)
                CPU_MODEL="Ryzen"
                print_status "CPU" "Using AMD Ryzen CPU profile"
                break
                ;;
            4)
                CPU_MODEL="qemu64"
                print_status "CPU" "Using generic qemu64 CPU"
                break
                ;;
            *)
                print_status "ERROR" "Invalid selection"
                ;;
        esac
    done
    
    # Thread configuration
    local total_cores=$(nproc)
    local max_threads=$((total_cores * 2))
    
    while true; do
        read -p "$(print_status "INPUT" "Number of CPU threads (1-$max_threads, default: 2): ")" threads_input
        threads_input="${threads_input:-2}"
        if validate_input "number" "$threads_input" && [ "$threads_input" -ge 1 ] && [ "$threads_input" -le "$max_threads" ]; then
            THREADS="$threads_input"
            break
        fi
    done
    
    # Advanced CPU features
    if $AMD_CPU; then
        print_status "CPU" "AMD-specific optimizations available:"
        
        while true; do
            read -p "$(print_status "INPUT" "Enable nested virtualization? (y/n, default: n): ")" nested_input
            nested_input="${nested_input:-n}"
            if [[ "$nested_input" =~ ^[Yy]$ ]]; then 
                ACCELERATOR="kvm,kernel_irqchip=on,nested=on"
                break
            elif [[ "$nested_input" =~ ^[Nn]$ ]]; then
                ACCELERATOR="kvm"
                break
            fi
        done
        
        while true; do
            read -p "$(print_status "INPUT" "Enable huge pages? (y/n, default: n): ")" hp_input
            hp_input="${hp_input:-n}"
            if [[ "$hp_input" =~ ^[Yy]$ ]]; then 
                ENABLE_HUGE_PAGES=true
                break
            elif [[ "$hp_input" =~ ^[Nn]$ ]]; then
                ENABLE_HUGE_PAGES=false
                break
            fi
        done
    fi
    
    # Cache mode
    print_status "INFO" "Select disk cache mode:"
    echo "  1) writeback (default) - Good performance"
    echo "  2) writethrough - Safer, slower"
    echo "  3) none - Direct I/O"
    echo "  4) unsafe - Best performance, risk of data loss"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter choice (1-4): ")" cache_choice
        case $cache_choice in
            1) CACHE_MODE="writeback"; break ;;
            2) CACHE_MODE="writethrough"; break ;;
            3) CACHE_MODE="none"; break ;;
            4) CACHE_MODE="unsafe"; break ;;
            *) print_status "ERROR" "Invalid selection" ;;
        esac
    done
    
    # I/O Threads
    while true; do
        read -p "$(print_status "INPUT" "Number of I/O threads (1-8, default: 4): ")" io_threads_input
        io_threads_input="${io_threads_input:-4}"
        if validate_input "number" "$io_threads_input" && [ "$io_threads_input" -ge 1 ] && [ "$io_threads_input" -le 8 ]; then
            IO_THREADS="$io_threads_input"
            break
        fi
    done
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM with ZynexForge"
    
    # OS Selection with better UI
    print_status "INFO" "Select an OS to set up:"
    echo "┌─────────────────────────────────────────────────────────────┐"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        printf "│ %2d) %-55s │\n" $i "$os"
        os_options[$i]="$os"
        ((i++))
    done
    echo "└─────────────────────────────────────────────────────────────┘"
    
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
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Password cannot be empty"
        fi
    done

    # Hardware configuration
    print_status "INFO" "Hardware Configuration"
    echo "─────────────────────────────────────────────"
    
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 40G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-40G}"
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
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,443:443, press Enter for none): ")" PORT_FORWARDS

    # Setup advanced features
    setup_cpu
    setup_network
    
    # Security features
    while true; do
        read -p "$(print_status "INPUT" "Enable TPM 2.0 emulation? (y/n, default: n): ")" tpm_input
        tpm_input="${tpm_input:-n}"
        if [[ "$tpm_input" =~ ^[Yy]$ ]]; then 
            ENABLE_TPM=true
            break
        elif [[ "$tpm_input" =~ ^[Nn]$ ]]; then
            ENABLE_TPM=false
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enable UEFI Secure Boot? (y/n, default: n): ")" sb_input
        sb_input="${sb_input:-n}"
        if [[ "$sb_input" =~ ^[Yy]$ ]]; then 
            ENABLE_SECURE_BOOT=true
            break
        elif [[ "$sb_input" =~ ^[Nn]$ ]]; then
            ENABLE_SECURE_BOOT=false
            break
        fi
    done

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Setting up VM image..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check if image already exists
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Skipping download."
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! wget --progress=bar:force:noscroll "$IMG_URL" -O "$IMG_FILE.tmp"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
        print_status "SUCCESS" "Image downloaded successfully"
    fi
    
    # Resize the disk image
    print_status "INFO" "Resizing disk to $DISK_SIZE..."
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Failed to resize disk image. Creating new image..."
        rm -f "$IMG_FILE"
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    fi

    # Advanced cloud-init configuration
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
preserve_hostname: false
manage_etc_hosts: true
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
    ssh_authorized_keys:
      - $(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "# No SSH key found")
ssh_deletekeys: false
ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - wget
  - net-tools
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "ZynexForge VM $HOSTNAME ready" > /etc/motd
final_message: "ZynexForge VM setup completed in \$UPTIME seconds"
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    # Network configuration if static IP is set
    if [ -n "${STATIC_IP}" ] && [ -n "${NETMASK}" ] && [ -n "${GATEWAY}" ]; then
        cat > network-data <<EOF
version: 2
ethernets:
  eth0:
    match:
      macaddress: ${MAC_ADDRESS}
    addresses:
      - ${STATIC_IP}/${NETMASK}
    gateway4: ${GATEWAY}
    nameservers:
      addresses: ${DNS_SERVERS:-8.8.8.8,8.8.4.4}
EOF
        if ! cloud-localds -H "$HOSTNAME" -N network-data "$SEED_FILE" user-data meta-data; then
            print_status "ERROR" "Failed to create cloud-init seed image"
            exit 1
        fi
    else
        if ! cloud-localds -H "$HOSTNAME" "$SEED_FILE" user-data meta-data; then
            print_status "ERROR" "Failed to create cloud-init seed image"
            exit 1
        fi
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
}

# Function to start a VM with advanced features
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        # Check if seed file exists
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Base QEMU command with AMD optimizations
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -cpu "$CPU_MODEL"
            -smp "$CPUS,sockets=1,cores=$CPUS,threads=$THREADS"
            -m "$MEMORY"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=$CACHE_MODE"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot "order=c,menu=on"
            -device "virtio-net-pci,netdev=n0,mac=$MAC_ADDRESS"
            -object "rng-random,filename=/dev/urandom,id=rng0"
            -device "virtio-rng-pci,rng=rng0"
        )
        
        # Add CPU optimizations for AMD
        if $AMD_CPU; then
            qemu_cmd+=(-machine "type=pc,accel=$ACCELERATOR")
            if $ENABLE_HUGE_PAGES; then
                qemu_cmd+=(-mem-path "/dev/hugepages")
            fi
        fi
        
        # Add I/O threads
        qemu_cmd+=(-object "iothread,id=iothread0")
        qemu_cmd+=(-device "virtio-blk-pci,drive=drive0,iothread=iothread0")
        
        # Network configuration based on type
        case $NETWORK_TYPE in
            "user")
                qemu_cmd+=(-netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22")
                ;;
            "bridge")
                qemu_cmd+=(-netdev "bridge,id=n0,br=$BRIDGE_INTERFACE")
                ;;
            "macvtap")
                qemu_cmd+=(-netdev "tap,id=n0,ifname=tap0,script=no,downscript=no")
                ;;
        esac
        
        # Add port forwards if specified
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi
        
        # Add network performance optimizations
        if $ENABLE_VIRTIO; then
            qemu_cmd+=(-device "virtio-net-pci,mq=on,vectors=$((NETWORK_QUEUES * 2 + 2))")
        fi
        
        if [ -n "$BANDWIDTH_LIMIT" ]; then
            qemu_cmd+=(-device "virtio-net-pci,netdev=n0,br=$BRIDGE_INTERFACE,rate=${BANDWIDTH_LIMIT}m")
        fi
        
        # Add GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
            qemu_cmd+=(-usb -device usb-tablet)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi
        
        # Add security features
        if $ENABLE_TPM; then
            qemu_cmd+=(-chardev "socket,id=chrtpm,path=/tmp/tpm0.sock")
            qemu_cmd+=(-tpmdev "emulator,id=tpm0,chardev=chrtpm")
            qemu_cmd+=(-device "tpm-tis,tpmdev=tpm0")
        fi
        
        if $ENABLE_SECURE_BOOT; then
            qemu_cmd+=(-bios "/usr/share/OVMF/OVMF_CODE.fd")
            qemu_cmd+=(-drive "file=/usr/share/OVMF/OVMF_VARS.fd,format=raw,if=pflash")
        fi
        
        # Add monitoring
        qemu_cmd+=(-monitor "telnet:localhost:4444,server,nowait")
        qemu_cmd+=(-qmp "unix:/tmp/qmp-$VM_NAME.sock,server,nowait")
        
        print_status "INFO" "Starting QEMU with advanced optimizations..."
        print_status "CPU" "CPU: $CPU_MODEL, Cores: $CPUS, Threads: $THREADS"
        print_status "NET" "Network: $NETWORK_TYPE, Queues: $NETWORK_QUEUES"
        
        # Run QEMU in background
        "${qemu_cmd[@]}" &
        local qemu_pid=$!
        
        # Wait for VM to start
        sleep 3
        if ps -p $qemu_pid > /dev/null; then
            print_status "SUCCESS" "VM $vm_name started successfully (PID: $qemu_pid)"
            echo "Monitor: telnet localhost 4444"
            echo "QMP: /tmp/qmp-$VM_NAME.sock"
        else
            print_status "ERROR" "Failed to start VM"
        fi
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                     ⚠  WARNING  ⚠                         │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  This action cannot be undone!                              │"
    echo "│  All VM data including disk images will be deleted.         │"
    echo "└─────────────────────────────────────────────────────────────┘"
    
    read -p "$(print_status "INPUT" "Type 'DELETE' to confirm: ")" confirm
    if [[ "$confirm" == "DELETE" ]]; then
        if load_vm_config "$vm_name"; then
            # Stop VM if running
            if is_vm_running "$vm_name"; then
                stop_vm "$vm_name"
            fi
            
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to show VM info with better formatting
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "┌─────────────────────────────────────────────────────────────┐"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "OS" "$OS_TYPE"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Hostname" "$HOSTNAME"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Username" "$USERNAME"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "SSH Port" "$SSH_PORT"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Memory" "$MEMORY MB"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "CPUs" "$CPUS"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Disk" "$DISK_SIZE"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "CPU Model" "$CPU_MODEL"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Network Type" "$NETWORK_TYPE"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "GUI Mode" "$GUI_MODE"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Created" "$CREATED"
        echo "└─────────────────────────────────────────────────────────────┘"
        
        if is_vm_running "$vm_name"; then
            print_status "SUCCESS" "Status: Running"
        else
            print_status "INFO" "Status: Stopped"
        fi
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            
            # Try graceful shutdown via monitor
            if [ -S "/tmp/qmp-$VM_NAME.sock" ]; then
                echo '{"execute":"qmp_capabilities"}' | socat - UNIX-CONNECT:/tmp/qmp-$VM_NAME.sock >/dev/null 2>&1
                echo '{"execute":"system_powerdown"}' | socat - UNIX-CONNECT:/tmp/qmp-$VM_NAME.sock >/dev/null 2>&1
                sleep 5
            fi
            
            # Force stop if still running
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM did not stop gracefully, forcing termination..."
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
            fi
            
            # Cleanup sockets
            rm -f "/tmp/qmp-$VM_NAME.sock" "/tmp/tpm0.sock" 2>/dev/null
            
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to edit VM configuration with advanced options
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo
            print_status "MENU" "Edit Configuration"
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  1) Basic Settings  │  2) Hardware  │  3) Network          │"
            echo "│  4) CPU/Performance │  5) Security  │  0) Back to Menu     │"
            echo "└─────────────────────────────────────────────────────────────┘"
            
            read -p "$(print_status "INPUT" "Select category: ")" category
            
            case $category in
                1) edit_basic_settings ;;
                2) edit_hardware_settings ;;
                3) edit_network_settings ;;
                4) edit_performance_settings ;;
                5) edit_security_settings ;;
                0) return 0 ;;
                *) print_status "ERROR" "Invalid selection" ;;
            esac
            
            # Save configuration
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

edit_basic_settings() {
    echo "Basic Settings:"
    while true; do
        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
        new_hostname="${new_hostname:-$HOSTNAME}"
        if validate_input "name" "$new_hostname"; then
            HOSTNAME="$new_hostname"
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
        new_username="${new_username:-$USERNAME}"
        if validate_input "username" "$new_username"; then
            USERNAME="$new_username"
            break
        fi
    done
    
    while true; do
        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
        new_password="${new_password:-$PASSWORD}"
        echo
        if [ -n "$new_password" ]; then
            PASSWORD="$new_password"
            break
        fi
    done
}

edit_hardware_settings() {
    echo "Hardware Settings:"
    while true; do
        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
        new_memory="${new_memory:-$MEMORY}"
        if validate_input "number" "$new_memory"; then
            MEMORY="$new_memory"
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
        new_cpus="${new_cpus:-$CPUS}"
        if validate_input "number" "$new_cpus"; then
            CPUS="$new_cpus"
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
        new_disk_size="${new_disk_size:-$DISK_SIZE}"
        if validate_input "size" "$new_disk_size"; then
            DISK_SIZE="$new_disk_size"
            break
        fi
    done
}

edit_network_settings() {
    echo "Network Settings:"
    read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
    new_ssh_port="${new_ssh_port:-$SSH_PORT}"
    if validate_input "port" "$new_ssh_port"; then
        SSH_PORT="$new_ssh_port"
    fi
    
    read -p "$(print_status "INPUT" "Port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
    
    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, current: $GUI_MODE): ")" gui_input
        gui_input="${gui_input:-}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            GUI_MODE=false
            break
        elif [ -z "$gui_input" ]; then
            break
        fi
    done
}

edit_performance_settings() {
    echo "Performance Settings:"
    while true; do
        read -p "$(print_status "INPUT" "Number of I/O threads (1-8, current: $IO_THREADS): ")" io_threads_input
        io_threads_input="${io_threads_input:-$IO_THREADS}"
        if validate_input "number" "$io_threads_input" && [ "$io_threads_input" -ge 1 ] && [ "$io_threads_input" -le 8 ]; then
            IO_THREADS="$io_threads_input"
            break
        fi
    done
    
    echo "Select disk cache mode (current: $CACHE_MODE):"
    echo "  1) writeback (default) - Good performance"
    echo "  2) writethrough - Safer, slower"
    echo "  3) none - Direct I/O"
    echo "  4) unsafe - Best performance, risk of data loss"
    
    read -p "$(print_status "INPUT" "Enter choice (1-4): ")" cache_choice
    case $cache_choice in
        1) CACHE_MODE="writeback" ;;
        2) CACHE_MODE="writethrough" ;;
        3) CACHE_MODE="none" ;;
        4) CACHE_MODE="unsafe" ;;
    esac
}

edit_security_settings() {
    echo "Security Settings:"
    while true; do
        read -p "$(print_status "INPUT" "Enable TPM 2.0? (y/n, current: $ENABLE_TPM): ")" tpm_input
        tpm_input="${tpm_input:-}"
        if [[ "$tpm_input" =~ ^[Yy]$ ]]; then 
            ENABLE_TPM=true
            break
        elif [[ "$tpm_input" =~ ^[Nn]$ ]]; then
            ENABLE_TPM=false
            break
        elif [ -z "$tpm_input" ]; then
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enable Secure Boot? (y/n, current: $ENABLE_SECURE_BOOT): ")" sb_input
        sb_input="${sb_input:-}"
        if [[ "$sb_input" =~ ^[Yy]$ ]]; then 
            ENABLE_SECURE_BOOT=true
            break
        elif [[ "$sb_input" =~ ^[Nn]$ ]]; then
            ENABLE_SECURE_BOOT=false
            break
        elif [ -z "$sb_input" ]; then
            break
        fi
    done
}

# Function to resize VM disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current disk size: $DISK_SIZE"
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "New disk size is the same as current size. No changes made."
                    return 0
                fi
                
                # Check if VM is running
                if is_vm_running "$vm_name"; then
                    print_status "ERROR" "Cannot resize disk while VM is running. Stop the VM first."
                    return 1
                fi
                
                # Resize the disk
                print_status "INFO" "Resizing disk to $new_disk_size..."
                if qemu-img resize "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Disk resized successfully to $new_disk_size"
                else
                    print_status "ERROR" "Failed to resize disk"
                    return 1
                fi
                break
            fi
        done
    fi
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "Performance metrics for VM: $vm_name"
        echo "┌─────────────────────────────────────────────────────────────┐"
        
        if is_vm_running "$vm_name"; then
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                # Show process stats
                print_status "CPU" "Process Statistics:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers | awk '{printf "│ PID: %-5s CPU: %-4s MEM: %-4s SIZE: %-6s RSS: %-6s\n", $1, $2, $3, $4, $5}'
                echo "├─────────────────────────────────────────────────────────────┤"
                
                # Show system resources
                print_status "INFO" "System Resources:"
                free -h | awk 'NR<=2 {printf "│ %-15s %-10s %-10s %-10s %-10s\n", $1, $2, $3, $4, $5}'
                echo "├─────────────────────────────────────────────────────────────┤"
                
                # Show disk usage
                print_status "INFO" "Disk Usage:"
                df -h "$IMG_FILE" 2>/dev/null | awk 'NR==2 {printf "│ Used: %-6s Avail: %-6s Size: %-6s Use%%: %-4s\n", $3, $4, $2, $5}'
                echo "└─────────────────────────────────────────────────────────────┘"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "│ Configuration:"
            printf "│ %-20s: %-35s │\n" "Memory" "$MEMORY MB"
            printf "│ %-20s: %-35s │\n" "CPUs" "$CPUS"
            printf "│ %-20s: %-35s │\n" "Disk" "$DISK_SIZE"
            printf "│ %-20s: %-35s │\n" "CPU Model" "$CPU_MODEL"
            printf "│ %-20s: %-35s │\n" "I/O Threads" "$IO_THREADS"
            printf "│ %-20s: %-35s │\n" "Cache Mode" "$CACHE_MODE"
            echo "└─────────────────────────────────────────────────────────────┘"
        fi
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to backup VM
backup_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Backing up VM: $vm_name"
        
        # Stop VM if running
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM is running. Stopping for consistent backup..."
            stop_vm "$vm_name"
            sleep 2
        fi
        
        # Create backup directory
        local backup_dir="$VM_DIR/backups"
        mkdir -p "$backup_dir"
        
        # Create timestamp
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local backup_file="$backup_dir/${vm_name}_${timestamp}.tar.gz"
        
        # Create backup
        print_status "INFO" "Creating backup..."
        tar -czf "$backup_file" -C "$VM_DIR" "$vm_name.conf" "${vm_name}.img" "${vm_name}-seed.iso" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "Backup created: $backup_file"
            ls -lh "$backup_file"
        else
            print_status "ERROR" "Backup failed"
        fi
    fi
}

# Function to restore VM from backup
restore_vm() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        print_status "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    print_status "INFO" "Restoring VM from backup: $backup_file"
    
    # Extract backup
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find config file
    local config_file=$(find "$temp_dir" -name "*.conf" | head -1)
    if [ -z "$config_file" ]; then
        print_status "ERROR" "No configuration file found in backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Load config to get VM name
    source "$config_file"
    local vm_name="$VM_NAME"
    
    # Check if VM already exists
    if [ -f "$VM_DIR/$vm_name.conf" ]; then
        print_status "WARN" "VM '$vm_name' already exists. Overwrite? (y/N): "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_status "INFO" "Restore cancelled"
            rm -rf "$temp_dir"
            return 0
        fi
        # Delete existing VM
        delete_vm "$vm_name"
    fi
    
    # Restore files
    cp "$temp_dir"/* "$VM_DIR/" 2>/dev/null
    rm -rf "$temp_dir"
    
    print_status "SUCCESS" "VM '$vm_name' restored from backup"
    return 0
}

# Main menu function with enhanced UI
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        # Display VM status
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Virtual Machines ($vm_count total):"
            echo "┌─────┬──────────────────────┬────────────┬──────────────────────┐"
            echo "│ No. │ Name                 │ Status     │ IP/Port             │"
            echo "├─────┼──────────────────────┼────────────┼──────────────────────┤"
            
            for i in "${!vms[@]}"; do
                local vm="${vms[$i]}"
                local status="\033[1;31mStopped\033[0m"
                local port=""
                
                if load_vm_config "$vm" 2>/dev/null; then
                    port="$SSH_PORT"
                    if is_vm_running "$vm"; then
                        status="\033[1;32mRunning\033[0m"
                    fi
                fi
                
                printf "│ \033[1;36m%2d\033[0m │ %-20s │ %b │ %-20s │\n" \
                    $((i+1)) "$vm" "$status" "SSH: $port"
            done
            echo "└─────┴──────────────────────┴────────────┴──────────────────────┘"
            echo
        else
            print_status "INFO" "No VMs found. Create your first VM to get started."
            echo
        fi
        
        # Display main menu
        print_status "MENU" "Main Menu"
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│ 1) Create New VM       │ 2) Start VM      │ 3) Stop VM     │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│ 4) VM Information      │ 5) Edit Config   │ 6) Delete VM   │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│ 7) Resize Disk         │ 8) Performance   │ 9) Backup      │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│ 0) Exit                │ B) Restore       │                │"
        echo "└─────────────────────────────────────────────────────────────┘"
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
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            9)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to backup: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        backup_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            b|B)
                read -p "$(print_status "INPUT" "Enter backup file path: ")" backup_file
                restore_vm "$backup_file"
                ;;
            0)
                print_status "INFO" "Thank you for using ZynexForge VM Manager!"
                echo
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/ZynexForge-VMs}"
mkdir -p "$VM_DIR"

# Supported OS list with AMD optimized images
declare -A OS_OPTIONS=(
    ["Ubuntu 24.04 LTS (Noble)"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Ubuntu 22.04 LTS (Jammy)"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Debian 12 (Bookworm)"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Debian 11 (Bullseye)"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
    ["OpenSUSE Tumbleweed"]="opensuse|tumbleweed|https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed.x86_64-Cloud.qcow2|opensuse|opensuse|opensuse"
    ["Arch Linux"]="arch|latest|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|archlinux|arch|arch"
)

# Start the main menu
main_menu
