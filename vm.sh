#!/bin/bash
set -euo pipefail

# =============================
# ZYNEXFORGE™ - Advanced VM Virtualization Platform
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
TEMPLATES_DIR="$VM_BASE_DIR/templates"
NETWORKS_DIR="$VM_BASE_DIR/networks"
BACKUPS_DIR="$VM_BASE_DIR/backups"
LOGS_DIR="$VM_BASE_DIR/logs"

# Create necessary directories
mkdir -p "$VM_DIR" "$IMAGES_DIR" "$TEMPLATES_DIR" "$NETWORKS_DIR" "$BACKUPS_DIR" "$LOGS_DIR"

# Function to display header
display_header() {
    clear
    cat << "EOF"

__________                             ___________                         
\____    /___.__. ____   ____ ___  ___ \_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /  |    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 
EOF
    echo -e "${COLOR_CYAN}ZYNEXFORGE™${COLOR_RESET}"
    echo -e "${COLOR_WHITE}Enterprise Virtualization Platform v4.0${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Max VMs: $MAX_VMS${COLOR_RESET}"
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
EOF
    
    print_status "SUCCESS" "Configuration saved"
    log_action "SAVE_CONFIG" "$VM_NAME" "Configuration updated"
}

# Function to generate MAC address
generate_mac() {
    printf '52:54:%02x:%02x:%02x:%02x\n' \
        $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

# Function to setup VM image with caching
setup_vm_image() {
    print_status "INFO" "Initializing VM storage..."
    
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
        print_status "INFO" "Downloading OS image..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$cached_image.tmp"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$cached_image.tmp" "$cached_image"
        cp "$cached_image" "$IMG_FILE"
    fi
    
    # Resize the disk image if needed
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Failed to resize disk image. Creating new image with specified size..."
        rm -f "$IMG_FILE"
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    fi
    
    # Create advanced cloud-init configuration
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
preserve_hostname: false
manage_etc_hosts: true
package_upgrade: true
package_reboot_if_required: true
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
    ssh_authorized_keys:
$(echo "$SSH_KEYS" | sed 's/^/      - /')
packages:
  - qemu-guest-agent
  - fail2ban
  - htop
  - neofetch
  - curl
  - wget
  - git
  - python3
  - docker.io
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - echo "vm.swappiness=10" >> /etc/sysctl.conf
  - sysctl -p
  - timedatectl set-timezone UTC
power_state:
  mode: reboot
  timeout: 300
EOF

    # Network configuration if static IP is set
    if [[ -n "$STATIC_IP" ]]; then
        cat > network-config <<EOF
version: 2
ethernets:
  eth0:
    match:
      macaddress: "$MAC_ADDRESS"
    addresses: [$STATIC_IP/24]
    gateway4: 10.0.2.2
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF
        if ! cloud-localds -N network-config "$SEED_FILE" user-data meta-data; then
            print_status "ERROR" "Failed to create cloud-init seed image with network config"
            exit 1
        fi
    else
        cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF
        if ! cloud-localds "$SEED_FILE" user-data meta-data; then
            print_status "ERROR" "Failed to create cloud-init seed image"
            exit 1
        fi
    fi
    
    # Create snapshot if enabled
    if [[ "$SNAPSHOT_COUNT" -gt 0 ]]; then
        qemu-img snapshot -c "initial" "$IMG_FILE"
    fi
}

# Function to create new VM with advanced options
create_new_vm() {
    if ! check_vm_limit; then
        return 1
    fi
    
    display_header
    section_header "CREATE NEW VIRTUAL MACHINE"
    
    # OS Selection
    section_header "OPERATING SYSTEM SELECTION"
    print_status "INFO" "Available operating systems:"
    
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
            print_status "INFO" "Selected: $os"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # VM Configuration
    section_header "VIRTUAL MACHINE CONFIGURATION"
    
    # Name and hostname
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

    # Advanced credentials
    section_header "ACCESS CREDENTIALS"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        echo -e "${COLOR_YELLOW}Password requirements:${COLOR_RESET} Minimum 8 characters with uppercase, lowercase, and number"
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ ${#PASSWORD} -ge 8 ] && [[ "$PASSWORD" =~ [A-Z] ]] && [[ "$PASSWORD" =~ [a-z] ]] && [[ "$PASSWORD" =~ [0-9] ]]; then
            break
        else
            print_status "ERROR" "Password must be at least 8 characters with uppercase, lowercase, and number"
        fi
    done

    # SSH keys
    read -p "$(print_status "INPUT" "Add SSH public keys (press Enter to skip): ")" SSH_KEYS

    # Advanced resources
    section_header "RESOURCE ALLOCATION"
    
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 50G, supports G/T/M): ")" DISK_SIZE
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

    # CPU type selection
    section_header "ADVANCED CPU FEATURES"
    echo "CPU Types:"
    echo "  1) host (best performance)"
    echo "  2) kvm64 (compatibility)"
    echo "  3) qemu64 (legacy)"
    echo "  4) custom"
    
    read -p "$(print_status "INPUT" "Select CPU type (1-4, default: 1): ")" cpu_choice
    case $cpu_choice in
        1) CPU_TYPE="host" ;;
        2) CPU_TYPE="kvm64" ;;
        3) CPU_TYPE="qemu64" ;;
        4) read -p "$(print_status "INPUT" "Enter custom CPU type: ")" CPU_TYPE ;;
        *) CPU_TYPE="host" ;;
    esac

    # GPU passthrough
    read -p "$(print_status "INPUT" "Enable GPU passthrough? (y/N): ")" gpu_choice
    if [[ "$gpu_choice" =~ ^[Yy]$ ]]; then
        GPU_PASSTHROUGH=true
    else
        GPU_PASSTHROUGH=false
    fi

    # Advanced networking
    section_header "NETWORK CONFIGURATION"
    
    # Generate MAC address
    MAC_ADDRESS=$(generate_mac)
    echo -e "Generated MAC: ${COLOR_CYAN}$MAC_ADDRESS${COLOR_RESET}"
    
    # Network type
    echo "Network Configuration:"
    echo "  1) User mode networking (NAT)"
    echo "  2) Tap networking (bridged)"
    echo "  3) Macvtap"
    
    read -p "$(print_status "INPUT" "Select network type (1-3, default: 1): ")" net_choice
    case $net_choice in
        2) NETWORK_CONFIG="tap" ;;
        3) NETWORK_CONFIG="macvtap" ;;
        *) NETWORK_CONFIG="user" ;;
    esac

    # Static IP configuration
    read -p "$(print_status "INPUT" "Set static IP? (y/N): ")" static_ip_choice
    if [[ "$static_ip_choice" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "$(print_status "INPUT" "Enter static IP (e.g., 10.0.2.100): ")" STATIC_IP
            if validate_input "ip" "$STATIC_IP"; then
                break
            fi
        done
    fi

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

    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,8443:443, press Enter for none): ")" PORT_FORWARDS

    # Backup and snapshot configuration
    section_header "BACKUP & SNAPSHOT"
    
    echo "Backup Schedule:"
    echo "  1) Daily"
    echo "  2) Weekly"
    echo "  3) Monthly"
    echo "  4) None"
    
    read -p "$(print_status "INPUT" "Select backup schedule (1-4, default: 4): ")" backup_choice
    case $backup_choice in
        1) BACKUP_SCHEDULE="daily" ;;
        2) BACKUP_SCHEDULE="weekly" ;;
        3) BACKUP_SCHEDULE="monthly" ;;
        *) BACKUP_SCHEDULE="none" ;;
    esac

    read -p "$(print_status "INPUT" "Maximum snapshots to keep (0 to disable, default: 5): ")" SNAPSHOT_COUNT
    SNAPSHOT_COUNT="${SNAPSHOT_COUNT:-5}"

    # Final configuration
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    section_header "DEPLOYMENT SUMMARY"
    echo -e "${COLOR_WHITE}VM Configuration:${COLOR_RESET}"
    echo -e "  Name: ${COLOR_CYAN}$VM_NAME${COLOR_RESET}"
    echo -e "  OS: ${COLOR_GREEN}$os${COLOR_RESET}"
    echo -e "  Resources: ${COLOR_YELLOW}$CPUS vCPU ($CPU_TYPE) | ${MEMORY}MB RAM | $DISK_SIZE disk${COLOR_RESET}"
    echo -e "  GPU Passthrough: ${COLOR_MAGENTA}$GPU_PASSTHROUGH${COLOR_RESET}"
    echo -e "  Network: ${COLOR_CYAN}$NETWORK_CONFIG${COLOR_RESET} (MAC: $MAC_ADDRESS)"
    [[ -n "$STATIC_IP" ]] && echo -e "  Static IP: ${COLOR_CYAN}$STATIC_IP${COLOR_RESET}"
    echo -e "  SSH Port: ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
    echo -e "  Access: ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
    echo -e "  Backup: ${COLOR_GRAY}$BACKUP_SCHEDULE${COLOR_RESET}"
    echo -e "  Snapshots: ${COLOR_GRAY}$SNAPSHOT_COUNT${COLOR_RESET}"
    echo
    
    read -p "$(print_status "INPUT" "Proceed with deployment? (y/N): ")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "INFO" "Deployment cancelled"
        return
    fi

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
    
    section_header "DEPLOYMENT COMPLETE"
    print_status "SUCCESS" "VM '$VM_NAME' deployed successfully"
    log_action "CREATE_VM" "$VM_NAME" "Created with $OS_TYPE, ${MEMORY}MB RAM, ${CPUS} vCPU, $DISK_SIZE disk"
    
    echo -e "  ${COLOR_GRAY}SSH Access: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Management: $VM_DIR/$VM_NAME.conf${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Image: $IMG_FILE${COLOR_RESET}"
    
    # Ask to start VM
    read -p "$(print_status "INPUT" "Start VM now? (y/N): ")" start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        start_vm "$VM_NAME"
    fi
}

# Function to start a VM with advanced options
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STARTING VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}OS:${COLOR_RESET} $OS_TYPE $CODENAME"
        echo -e "${COLOR_WHITE}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU ($CPU_TYPE) | ${MEMORY}MB RAM${COLOR_RESET}"
        echo
        
        # Check if VM is already running
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM $vm_name is already running"
            read -p "$(print_status "INPUT" "Connect to console? (y/N): ")" connect_console
            if [[ "$connect_console" =~ ^[Yy]$ ]]; then
                connect_vm_console "$vm_name"
            fi
            return 0
        fi
        
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
        
        # Display access information
        print_status "INFO" "Access Information:"
        echo -e "  ${COLOR_GRAY}SSH: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Password: $PASSWORD${COLOR_RESET}"
        [[ -n "$STATIC_IP" ]] && echo -e "  ${COLOR_GRAY}Static IP: $STATIC_IP${COLOR_RESET}"
        echo
        
        # Ask for startup mode
        echo "Startup Mode:"
        echo "  1) Foreground (with console output)"
        echo "  2) Background (daemon)"
        echo "  3) Screen session"
        echo "  4) Tmux session"
        
        read -p "$(print_status "INPUT" "Select startup mode (1-4, default: 1): ")" startup_mode
        startup_mode="${startup_mode:-1}"
        
        # Base QEMU command with advanced options
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -machine type=q35,accel=kvm
            -cpu "$CPU_TYPE"
            -m "$MEMORY"
            -smp "$CPUS,sockets=1,cores=$CPUS,threads=1"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,discard=on"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c
            -device virtio-net-pci,netdev=n0,mac="$MAC_ADDRESS"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )

        # Add GPU passthrough if enabled
        if [[ "$GPU_PASSTHROUGH" == true ]]; then
            qemu_cmd+=(
                -device vfio-pci,host=01:00.0,multifunction=on
                -device vfio-pci,host=01:00.1
                -vga none
                -nographic
            )
        # Add GUI or console mode
        elif [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(
                -vga virtio
                -display gtk,gl=on
                -full-screen
            )
        else
            qemu_cmd+=(
                -nographic
                -serial mon:stdio
            )
        fi

        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
            -device virtio-scsi-pci,id=scsi
            -device scsi-hd,bus=scsi.0,drive=drive0
            -drive if=none,id=drive0,file="$IMG_FILE",format=qcow2
            -chardev socket,id=charmonitor,path="$VM_DIR/$vm_name.monitor",server,nowait
            -mon chardev=charmonitor,id=monitor,mode=control
            -rtc base=utc,clock=host,driftfix=slew
            -no-reboot
            -global kvm-pit.lost_tick_policy=delay
        )

        # Add port forwards if specified
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

        # Add audio if GUI mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-device ich9-intel-hda -device hda-duplex)
        fi

        # Add USB support
        qemu_cmd+=(-device qemu-xhci,id=xhci -device usb-tablet,bus=xhci.0)

        case $startup_mode in
            2)  # Background
                print_status "INFO" "Starting QEMU in background..."
                "${qemu_cmd[@]}" &
                local qemu_pid=$!
                echo $qemu_pid > "$VM_DIR/$vm_name.pid"
                print_status "SUCCESS" "VM $vm_name started in background (PID: $qemu_pid)"
                log_action "START_VM" "$vm_name" "Started in background with PID $qemu_pid"
                ;;
                
            3)  # Screen
                print_status "INFO" "Starting QEMU in screen session..."
                screen -dmS "qemu-$vm_name" "${qemu_cmd[@]}"
                print_status "SUCCESS" "VM $vm_name started in screen session 'qemu-$vm_name'"
                print_status "INFO" "Attach with: screen -r qemu-$vm_name"
                log_action "START_VM" "$vm_name" "Started in screen session qemu-$vm_name"
                ;;
                
            4)  # Tmux
                print_status "INFO" "Starting QEMU in tmux session..."
                tmux new-session -d -s "qemu-$vm_name" "${qemu_cmd[@]}"
                print_status "SUCCESS" "VM $vm_name started in tmux session 'qemu-$vm_name'"
                print_status "INFO" "Attach with: tmux attach -t qemu-$vm_name"
                log_action "START_VM" "$vm_name" "Started in tmux session qemu-$vm_name"
                ;;
                
            *)  # Foreground (default)
                print_status "INFO" "Starting QEMU instance..."
                echo "$SUBTLE_SEP"
                log_action "START_VM" "$vm_name" "Started in foreground"
                "${qemu_cmd[@]}"
                print_status "INFO" "VM $vm_name has been shut down"
                log_action "STOP_VM" "$vm_name" "Shutdown from foreground"
                ;;
        esac
    fi
}

# Function to connect to VM console
connect_vm_console() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Connecting to $vm_name console..."
            
            # Try to connect via monitor socket
            if [[ -S "$VM_DIR/$vm_name.monitor" ]]; then
                echo "Use 'help' for commands, 'quit' to exit monitor"
                nc -U "$VM_DIR/$vm_name.monitor"
            else
                print_status "ERROR" "Monitor socket not available"
            fi
        else
            print_status "ERROR" "VM $vm_name is not running"
        fi
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "DELETE VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}Created:${COLOR_RESET} $CREATED"
        echo -e "${COLOR_WHITE}Disk Usage:${COLOR_RESET} $(du -sh "$IMG_FILE" 2>/dev/null | cut -f1 || echo "Unknown")"
        echo
        
        print_status "WARN" "⚠️  This will permanently delete the VM and all its data!"
        print_status "WARN" "The following will be deleted:"
        echo -e "  ${COLOR_RED}• VM configuration${COLOR_RESET}"
        echo -e "  ${COLOR_RED}• Disk image ($DISK_SIZE)${COLOR_RESET}"
        echo -e "  ${COLOR_RED}• Cloud-init seed${COLOR_RESET}"
        echo -e "  ${COLOR_RED}• Snapshots and backups${COLOR_RESET}"
        echo
        
        read -p "$(print_status "INPUT" "Type 'DELETE' to confirm: ")" confirm
        if [[ "$confirm" == "DELETE" ]]; then
            # Stop VM if running
            if is_vm_running "$vm_name"; then
                stop_vm "$vm_name"
            fi
            
            # Delete files
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf" \
                  "$VM_DIR/$vm_name.pid" "$VM_DIR/$vm_name.monitor" \
                  "$BACKUPS_DIR/$vm_name"* "$LOGS_DIR/$vm_name"*
            
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
            log_action "DELETE_VM" "$vm_name" "Permanently deleted"
        else
            print_status "INFO" "Deletion cancelled"
        fi
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VIRTUAL MACHINE INFORMATION"
        
        # Basic info
        echo -e "${COLOR_WHITE}Basic Information:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Name:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Hostname:${COLOR_RESET} $HOSTNAME"
        echo -e "  ${COLOR_GRAY}OS:${COLOR_RESET} $OS_TYPE $CODENAME"
        echo -e "  ${COLOR_GRAY}Created:${COLOR_RESET} $CREATED"
        echo -e "  ${COLOR_GRAY}Status:${COLOR_RESET} $(is_vm_running "$vm_name" && echo -e "${COLOR_GREEN}Running${COLOR_RESET}" || echo -e "${COLOR_YELLOW}Stopped${COLOR_RESET}")"
        
        # Resources
        echo
        echo -e "${COLOR_WHITE}Resources:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS ($CPU_TYPE)${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}GPU Passthrough:${COLOR_RESET} $GPU_PASSTHROUGH"
        echo -e "  ${COLOR_GRAY}GUI Mode:${COLOR_RESET} $GUI_MODE"
        
        # Network
        echo
        echo -e "${COLOR_WHITE}Network:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Type:${COLOR_RESET} $NETWORK_CONFIG"
        echo -e "  ${COLOR_GRAY}MAC:${COLOR_RESET} $MAC_ADDRESS"
        [[ -n "$STATIC_IP" ]] && echo -e "  ${COLOR_GRAY}Static IP:${COLOR_RESET} $STATIC_IP"
        echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
        if [[ -n "$PORT_FORWARDS" ]]; then
            echo -e "  ${COLOR_GRAY}Port Forwards:${COLOR_RESET} $PORT_FORWARDS"
        fi
        
        # Access
        echo
        echo -e "${COLOR_WHITE}Access:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Username:${COLOR_RESET} ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Password:${COLOR_RESET} ********"
        
        # Management
        echo
        echo -e "${COLOR_WHITE}Management:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Backup:${COLOR_RESET} $BACKUP_SCHEDULE"
        echo -e "  ${COLOR_GRAY}Snapshots:${COLOR_RESET} $SNAPSHOT_COUNT"
        
        # Storage
        echo
        echo -e "${COLOR_WHITE}Storage Paths:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Configuration:${COLOR_RESET} $VM_DIR/$vm_name.conf"
        echo -e "  ${COLOR_GRAY}Disk Image:${COLOR_RESET} $IMG_FILE"
        echo -e "  ${COLOR_GRAY}Seed Image:${COLOR_RESET} $SEED_FILE"
        
        # Disk usage
        if [[ -f "$IMG_FILE" ]]; then
            local disk_usage=$(du -h "$IMG_FILE" 2>/dev/null | cut -f1)
            echo -e "  ${COLOR_GRAY}Current Usage:${COLOR_RESET} $disk_usage"
        fi
        
        echo
        echo "$SUBTLE_SEP"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    # Check by PID file
    if [[ -f "$VM_DIR/$vm_name.pid" ]]; then
        local pid=$(cat "$VM_DIR/$vm_name.pid" 2>/dev/null)
        if ps -p "$pid" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Check by process name
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
        return 0
    fi
    
    return 1
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STOP VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM gracefully..."
            
            # Try ACPI shutdown via monitor
            if [[ -S "$VM_DIR/$vm_name.monitor" ]]; then
                echo "system_powerdown" | nc -U "$VM_DIR/$vm_name.monitor" >/dev/null 2>&1
                sleep 5
            fi
            
            # Check if still running
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM did not stop gracefully, forcing termination..."
                
                # Kill by PID file
                if [[ -f "$VM_DIR/$vm_name.pid" ]]; then
                    kill -9 "$(cat "$VM_DIR/$vm_name.pid")" 2>/dev/null
                    rm -f "$VM_DIR/$vm_name.pid"
                fi
                
                # Kill by process
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
            fi
            
            # Clean up monitor socket
            rm -f "$VM_DIR/$vm_name.monitor"
            
            print_status "SUCCESS" "VM $vm_name stopped"
            log_action "STOP_VM" "$vm_name" "Stopped forcefully"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to backup VM
backup_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "BACKUP VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        # Create backup directory with timestamp
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local backup_dir="$BACKUPS_DIR/$vm_name/$timestamp"
        mkdir -p "$backup_dir"
        
        print_status "INFO" "Creating backup..."
        
        # Stop VM if running
        local was_running=false
        if is_vm_running "$vm_name"; then
            was_running=true
            print_status "INFO" "Stopping VM for consistent backup..."
            stop_vm "$vm_name"
            sleep 2
        fi
        
        # Backup configuration
        cp "$VM_DIR/$vm_name.conf" "$backup_dir/"
        
        # Backup disk image (using qemu-img convert to reduce size)
        if [[ -f "$IMG_FILE" ]]; then
            print_status "INFO" "Backing up disk image..."
            qemu-img convert -c -O qcow2 "$IMG_FILE" "$backup_dir/disk.img"
        fi
        
        # Backup seed image
        if [[ -f "$SEED_FILE" ]]; then
            cp "$SEED_FILE" "$backup_dir/"
        fi
        
        # Create backup manifest
        cat > "$backup_dir/manifest.txt" <<EOF
Backup created: $(date)
VM: $vm_name
OS: $OS_TYPE $CODENAME
Resources: ${CPUS}vCPU, ${MEMORY}MB RAM, $DISK_SIZE disk
Backup size: $(du -sh "$backup_dir" | cut -f1)
EOF
        
        # Restart VM if it was running
        if [[ "$was_running" == true ]]; then
            print_status "INFO" "Restarting VM..."
            start_vm "$vm_name"
        fi
        
        # Clean up old backups if limit exceeded
        local backup_count=$(find "$BACKUPS_DIR/$vm_name" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        local max_backups=10
        
        if [[ $backup_count -gt $max_backups ]]; then
            print_status "INFO" "Cleaning up old backups (keeping $max_backups)..."
            find "$BACKUPS_DIR/$vm_name" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" | \
                sort -n | head -n -$max_backups | cut -d' ' -f2- | xargs rm -rf
        fi
        
        print_status "SUCCESS" "Backup created at: $backup_dir"
        log_action "BACKUP_VM" "$vm_name" "Backup created at $backup_dir"
        
        echo -e "  ${COLOR_GRAY}Backup size: $(du -sh "$backup_dir" | cut -f1)${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Total backups: $backup_count${COLOR_RESET}"
    fi
}

# Function to restore VM from backup
restore_vm() {
    local vm_name=$1
    
    section_header "RESTORE VIRTUAL MACHINE"
    
    # List available backups
    local backup_dirs=($(find "$BACKUPS_DIR/$vm_name" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r))
    
    if [[ ${#backup_dirs[@]} -eq 0 ]]; then
        print_status "ERROR" "No backups found for VM '$vm_name'"
        return 1
    fi
    
    echo -e "${COLOR_WHITE}Available backups for $vm_name:${COLOR_RESET}"
    for i in "${!backup_dirs[@]}"; do
        local dir="${backup_dirs[$i]}"
        local timestamp=$(basename "$dir")
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "Unknown")
        echo -e "  ${COLOR_CYAN}$((i+1)))${COLOR_RESET} $timestamp (${size})"
    done
    
    echo
    read -p "$(print_status "INPUT" "Select backup to restore (1-${#backup_dirs[@]}): ")" backup_choice
    
    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#backup_dirs[@]} ]; then
        print_status "ERROR" "Invalid selection"
        return 1
    fi
    
    local selected_dir="${backup_dirs[$((backup_choice-1))]}"
    
    print_status "WARN" "⚠️  This will overwrite the current VM configuration!"
    read -p "$(print_status "INPUT" "Type 'RESTORE' to confirm: ")" confirm
    if [[ "$confirm" != "RESTORE" ]]; then
        print_status "INFO" "Restore cancelled"
        return 0
    fi
    
    # Stop VM if running
    if is_vm_running "$vm_name"; then
        stop_vm "$vm_name"
    fi
    
    # Restore files
    print_status "INFO" "Restoring VM from backup..."
    
    # Restore configuration
    if [[ -f "$selected_dir/$vm_name.conf" ]]; then
        cp "$selected_dir/$vm_name.conf" "$VM_DIR/"
    fi
    
    # Restore disk image
    if [[ -f "$selected_dir/disk.img" ]]; then
        cp "$selected_dir/disk.img" "$VM_DIR/$vm_name.img"
    fi
    
    # Restore seed image
    if [[ -f "$selected_dir/$vm_name-seed.iso" ]]; then
        cp "$selected_dir/$vm_name-seed.iso" "$VM_DIR/"
    fi
    
    print_status "SUCCESS" "VM '$vm_name' restored from backup"
    log_action "RESTORE_VM" "$vm_name" "Restored from $selected_dir"
    
    # Ask to start VM
    read -p "$(print_status "INPUT" "Start VM now? (y/N): ")" start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        start_vm "$vm_name"
    fi
}

# Function to create VM snapshot
create_snapshot() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if [[ "$SNAPSHOT_COUNT" -eq 0 ]]; then
            print_status "ERROR" "Snapshots are disabled for this VM"
            return 1
        fi
        
        section_header "CREATE VM SNAPSHOT"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        read -p "$(print_status "INPUT" "Enter snapshot name: ")" snapshot_name
        if [[ -z "$snapshot_name" ]]; then
            print_status "ERROR" "Snapshot name cannot be empty"
            return 1
        fi
        
        print_status "INFO" "Creating snapshot '$snapshot_name'..."
        
        if qemu-img snapshot -c "$snapshot_name" "$IMG_FILE"; then
            print_status "SUCCESS" "Snapshot created successfully"
            log_action "SNAPSHOT" "$vm_name" "Created snapshot: $snapshot_name"
            
            # List current snapshots
            list_snapshots "$vm_name"
        else
            print_status "ERROR" "Failed to create snapshot"
        fi
    fi
}

# Function to list VM snapshots
list_snapshots() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VM SNAPSHOTS"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        local snapshots=$(qemu-img snapshot -l "$IMG_FILE" 2>/dev/null | tail -n +3)
        
        if [[ -z "$snshots" ]]; then
            print_status "INFO" "No snapshots found"
        else
            echo "$snapshots" | while read -r line; do
                echo -e "  ${COLOR_GRAY}$line${COLOR_RESET}"
            done
        fi
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to restore VM snapshot
restore_snapshot() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "RESTORE VM SNAPSHOT"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        # List snapshots
        list_snapshots "$vm_name"
        
        read -p "$(print_status "INPUT" "Enter snapshot name to restore: ")" snapshot_name
        
        if [[ -n "$snapshot_name" ]]; then
            print_status "WARN" "⚠️  This will revert the VM to the snapshot state!"
            read -p "$(print_status "INPUT" "Type 'REVERT' to confirm: ")" confirm
            
            if [[ "$confirm" == "REVERT" ]]; then
                # Stop VM if running
                if is_vm_running "$vm_name"; then
                    stop_vm "$vm_name"
                fi
                
                print_status "INFO" "Restoring snapshot '$snapshot_name'..."
                
                if qemu-img snapshot -a "$snapshot_name" "$IMG_FILE"; then
                    print_status "SUCCESS" "Snapshot restored successfully"
                    log_action "RESTORE_SNAPSHOT" "$vm_name" "Restored snapshot: $snapshot_name"
                else
                    print_status "ERROR" "Failed to restore snapshot"
                fi
            else
                print_status "INFO" "Snapshot restore cancelled"
            fi
        fi
    fi
}

# Function to show system overview
show_system_overview() {
    display_header
    section_header "SYSTEM OVERVIEW"
    
    # System information
    echo -e "${COLOR_WHITE}System Information:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Hostname:${COLOR_RESET} $(hostname)"
    echo -e "  ${COLOR_GRAY}Kernel:${COLOR_RESET} $(uname -r)"
    echo -e "  ${COLOR_GRAY}CPU:${COLOR_RESET} $(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)"
    echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
    echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"
    
    # Platform statistics
    local total_vms=$(get_vm_count)
    local running_vms=0
    local vms=($(get_vm_list))
    
    for vm in "${vms[@]}"; do
        if is_vm_running "$vm"; then
            ((running_vms++))
        fi
    done
    
    echo
    echo -e "${COLOR_WHITE}Platform Statistics:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Total VMs:${COLOR_RESET} ${COLOR_CYAN}$total_vms${COLOR_RESET} / $MAX_VMS"
    echo -e "  ${COLOR_GRAY}Running VMs:${COLOR_RESET} ${COLOR_GREEN}$running_vms${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Stopped VMs:${COLOR_RESET} ${COLOR_YELLOW}$((total_vms - running_vms))${COLOR_RESET}"
    
    # Storage usage
    echo
    echo -e "${COLOR_WHITE}Storage Overview:${COLOR_RESET}"
    if [ -d "$VM_BASE_DIR" ]; then
        local total_storage=$(du -sh "$VM_BASE_DIR" 2>/dev/null | cut -f1)
        local vm_storage=$(du -sh "$VM_DIR" 2>/dev/null | cut -f1)
        local image_storage=$(du -sh "$IMAGES_DIR" 2>/dev/null | cut -f1)
        local backup_storage=$(du -sh "$BACKUPS_DIR" 2>/dev/null | cut -f1)
        
        echo -e "  ${COLOR_GRAY}Total:${COLOR_RESET} $total_storage"
        echo -e "  ${COLOR_GRAY}VMs:${COLOR_RESET} $vm_storage"
        echo -e "  ${COLOR_GRAY}Images:${COLOR_RESET} $image_storage"
        echo -e "  ${COLOR_GRAY}Backups:${COLOR_RESET} $backup_storage"
    fi
    
    # Recent activity
    echo
    echo -e "${COLOR_WHITE}Recent Activity:${COLOR_RESET}"
    tail -10 "$LOGS_DIR/zynexforge.log" 2>/dev/null | while read -r line; do
        echo -e "  ${COLOR_GRAY}$line${COLOR_RESET}"
    done || echo -e "  ${COLOR_GRAY}No activity log${COLOR_RESET}"
    
    echo
    echo "$SEPARATOR"
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VM PERFORMANCE METRICS"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            # Get QEMU process ID
            local qemu_pid=""
            if [[ -f "$VM_DIR/$vm_name.pid" ]]; then
                qemu_pid=$(cat "$VM_DIR/$vm_name.pid")
            else
                qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            fi
            
            if [[ -n "$qemu_pid" ]]; then
                echo
                echo -e "${COLOR_WHITE}Process Statistics:${COLOR_RESET}"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers | awk '{
                    printf "  PID: %s | CPU: %s%% | MEM: %s%% | Size: %sMB | RSS: %sMB\n", 
                    $1, $2, $3, $4/1024, $5/1024
                }'
                
                echo
                echo -e "${COLOR_WHITE}System Resources:${COLOR_RESET}"
                free -h | head -2 | tail -1 | awk '{print "  Memory: " $3 " / " $2 " used (" $4 " free)"}'
                
                # CPU usage breakdown
                echo
                echo -e "${COLOR_WHITE}CPU Usage:${COLOR_RESET}"
                top -bn1 -p "$qemu_pid" | tail -1 | awk '{
                    printf "  VM CPU: %s%% | System: %s%% | User: %s%%\n", $9, $11, $10
                }'
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo
            echo -e "${COLOR_WHITE}Configured Resources:${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS ($CPU_TYPE)${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        fi
        
        # Disk usage
        echo
        echo -e "${COLOR_WHITE}Disk Usage:${COLOR_RESET}"
        if [ -f "$IMG_FILE" ]; then
            local disk_size=$(du -h "$IMG_FILE" 2>/dev/null | cut -f1)
            local disk_info=$(qemu-img info "$IMG_FILE" 2>/dev/null | grep -E "(virtual size|disk size)")
            echo -e "  ${COLOR_GRAY}File:${COLOR_RESET} $disk_size"
            echo "$disk_info" | while read -r line; do
                echo -e "  ${COLOR_GRAY}${line%%:*}:${COLOR_RESET} ${line#*:}"
            done
        fi
        
        echo
        echo "$SUBTLE_SEP"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to show VM logs
show_vm_logs() {
    local vm_name=$1
    
    section_header "VM LOGS"
    echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
    
    # Filter logs for this VM
    local vm_logs=$(grep "| $vm_name |" "$LOGS_DIR/zynexforge.log" 2>/dev/null | tail -50)
    
    if [[ -z "$vm_logs" ]]; then
        print_status "INFO" "No logs found for VM '$vm_name'"
    else
        echo "$vm_logs" | while read -r line; do
            echo -e "  ${COLOR_GRAY}$line${COLOR_RESET}"
        done
    fi
    
    echo
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function to export VM
export_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "EXPORT VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        read -p "$(print_status "INPUT" "Enter export directory (default: ./exports): ")" export_dir
        export_dir="${export_dir:-./exports}"
        mkdir -p "$export_dir"
        
        local export_path="$export_dir/$vm_name-$(date '+%Y%m%d_%H%M%S').tar.gz"
        
        print_status "INFO" "Exporting VM to $export_path..."
        
        # Create temporary directory for export
        local temp_dir=$(mktemp -d)
        cp "$VM_DIR/$vm_name.conf" "$temp_dir/"
        
        # Convert disk image to compressed format
        if [[ -f "$IMG_FILE" ]]; then
            print_status "INFO" "Compressing disk image..."
            qemu-img convert -c -O qcow2 "$IMG_FILE" "$temp_dir/disk.img"
        fi
        
        # Create export manifest
        cat > "$temp_dir/README.txt" <<EOF
ZYNEXFORGE VM Export
===================
VM: $vm_name
Exported: $(date)
OS: $OS_TYPE $CODENAME
Resources: ${CPUS}vCPU, ${MEMORY}MB RAM, $DISK_SIZE disk

To import:
1. Extract this archive
2. Run: ./zynexforge.sh
3. Choose "Import VM" from menu
4. Select the extracted directory

Note: This is a compressed export. Original VM remains intact.
EOF
        
        # Create tar archive
        tar -czf "$export_path" -C "$temp_dir" .
        rm -rf "$temp_dir"
        
        print_status "SUCCESS" "VM exported to: $export_path"
        echo -e "  ${COLOR_GRAY}Export size: $(du -h "$export_path" | cut -f1)${COLOR_RESET}"
        log_action "EXPORT_VM" "$vm_name" "Exported to $export_path"
    fi
}

# Function to import VM
import_vm() {
    if ! check_vm_limit; then
        return 1
    fi
    
    section_header "IMPORT VIRTUAL MACHINE"
    
    read -p "$(print_status "INPUT" "Enter path to export file or directory: ")" import_path
    
    if [[ ! -e "$import_path" ]]; then
        print_status "ERROR" "Path does not exist: $import_path"
        return 1
    fi
    
    # Determine if it's a tar file or directory
    if [[ -f "$import_path" && "$import_path" =~ \.tar\.gz$ ]]; then
        # Extract tar file
        print_status "INFO" "Extracting archive..."
        local temp_dir=$(mktemp -d)
        tar -xzf "$import_path" -C "$temp_dir"
        import_path="$temp_dir"
    fi
    
    # Look for configuration file
    local config_file=$(find "$import_path" -name "*.conf" | head -1)
    
    if [[ -z "$config_file" ]]; then
        print_status "ERROR" "No VM configuration found in import"
        [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
        return 1
    fi
    
    # Load configuration from import
    source "$config_file"
    
    # Check if VM already exists
    if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
        print_status "ERROR" "VM '$VM_NAME' already exists"
        read -p "$(print_status "INPUT" "Rename VM? (y/N): ")" rename_choice
        if [[ "$rename_choice" =~ ^[Yy]$ ]]; then
            while true; do
                read -p "$(print_status "INPUT" "Enter new VM name: ")" new_name
                if validate_input "name" "$new_name" && [[ ! -f "$VM_DIR/$new_name.conf" ]]; then
                    VM_NAME="$new_name"
                    break
                fi
            done
        else
            [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    # Update paths for new location
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    
    # Copy disk image
    local src_disk=$(find "$import_path" -name "disk.img" -o -name "*.img" | head -1)
    if [[ -f "$src_disk" ]]; then
        print_status "INFO" "Importing disk image..."
        cp "$src_disk" "$IMG_FILE"
    fi
    
    # Save configuration
    save_vm_config
    
    print_status "SUCCESS" "VM '$VM_NAME' imported successfully"
    log_action "IMPORT_VM" "$VM_NAME" "Imported from $import_path"
    
    # Cleanup
    [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
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
            echo "  4) Connect to console"
            echo "  5) Show VM info"
            echo "  6) Edit VM configuration"
            echo "  7) Delete a VM"
            echo "  8) Backup VM"
            echo "  9) Restore from backup"
            echo " 10) Create snapshot"
            echo " 11) List snapshots"
            echo " 12) Restore snapshot"
            echo " 13) Resize VM disk"
            echo " 14) Show VM performance"
            echo " 15) Show VM logs"
            echo " 16) Export VM"
            echo " 17) Import VM"
            echo " 18) System overview"
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
                    read -p "$(print_status "INPUT" "Enter VM number to connect: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        connect_vm_console "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
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
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to backup: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        backup_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            9)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to restore: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        restore_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            10)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number for snapshot: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        create_snapshot "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            11)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to list snapshots: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        list_snapshots "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            12)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to restore snapshot: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        restore_snapshot "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            13)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            14)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number for performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            15)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number for logs: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_name" -le $vm_count ]; then
                        show_vm_logs "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            16)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to export: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        export_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            17)
                import_vm
                ;;
            18)
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

# Edit VM configuration function (placeholder - implement as needed)
edit_vm_config() {
    local vm_name=$1
    print_status "INFO" "Edit functionality for $vm_name - implement as needed"
}

# Resize VM disk function (placeholder - implement as needed)
resize_vm_disk() {
    local vm_name=$1
    print_status "INFO" "Resize functionality for $vm_name - implement as needed"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

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

# Start the main menu
main_menu
