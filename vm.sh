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

# Function to display colored output
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
    esac
    return 0
}

# Function to check dependencies (using only available packages)
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "sudo")
    local missing_deps=()
    
    print_status "INFO" "Checking system dependencies..."
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    # Check for AMD CPU using cpuid (available in your packages)
    if command -v cpuid &> /dev/null; then
        if cpuid | grep -q "AMD"; then
            print_status "CPU" "AMD CPU detected - Enabling optimizations"
            AMD_CPU=true
        else
            AMD_CPU=false
        fi
    elif grep -q "AMD" /proc/cpuinfo; then
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
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to setup network using available tools
setup_network() {
    print_status "NET" "Configuring network options"
    
    # Simple network configuration using user-mode networking (NAT)
    # This works with the packages available
    print_status "INFO" "Using user-mode networking (NAT) with port forwarding"
    
    # Check if port is available
    while true; do
        read -p "$(print_status "INPUT" "Enter SSH port (default: 2222): ")" SSH_PORT
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
    
    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,443:443, press Enter for none): ")" PORT_FORWARDS
}

# Function to setup CPU optimizations using available tools
setup_cpu() {
    print_status "CPU" "Configuring CPU optimizations"
    
    # Get CPU info using available tools
    if command -v cpuid &> /dev/null; then
        print_status "INFO" "CPU Information:"
        cpuid | grep -E "(AMD|Intel|vendor|family|model)" | head -5
    fi
    
    # Simple CPU configuration - using host model for best performance
    print_status "INFO" "Using host CPU model for best performance"
    
    # Get available CPU cores
    local total_cores=$(nproc)
    local max_cpus=$total_cores
    
    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (1-$max_cpus, default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS" && [ "$CPUS" -ge 1 ] && [ "$CPUS" -le "$max_cpus" ]; then
            break
        fi
    done
    
    # Memory configuration
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local max_mem=$((total_mem - 1024)) # Leave 1GB for host
    
    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (256-$max_mem, default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY" && [ "$MEMORY" -ge 256 ] && [ "$MEMORY" -le "$max_mem" ]; then
            break
        fi
    done
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM with ZynexForge"
    
    # OS Selection
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

    # Custom Inputs
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

    # Disk Configuration
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    # Hardware Configuration
    setup_cpu
    setup_network

    # GUI Mode
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
    
    # Create VM directory
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

    # Create cloud-init configuration
    # Using openssl for password hashing (available in packages)
    local password_hash=""
    if command -v openssl &> /dev/null; then
        password_hash=$(openssl passwd -6 "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    else
        password_hash="$PASSWORD"
    fi
    
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
    passwd: $password_hash
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
package_update: true
package_upgrade: true
final_message: "ZynexForge VM $HOSTNAME ready"
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

# Function to start a VM
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
        
        # Base QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -cpu host
            -smp "$CPUS"
            -m "$MEMORY"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c
            -device virtio-net-pci,netdev=n0
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )

        # Add port forwards if specified
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi

        # Add GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        # Add AMD optimizations if detected
        if $AMD_CPU; then
            qemu_cmd+=(-machine "type=pc,accel=kvm")
            print_status "CPU" "AMD CPU optimizations enabled"
        fi

        print_status "INFO" "Starting QEMU..."
        "${qemu_cmd[@]}"
        
        print_status "INFO" "VM $vm_name has been shut down"
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

# Function to show VM info
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
            pkill -f "qemu-system-x86_64.*$IMG_FILE"
            sleep 2
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM did not stop gracefully, forcing termination..."
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
            fi
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to edit VM configuration
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo
            print_status "MENU" "Edit Configuration"
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  1) Basic Settings  │  2) Hardware  │  3) Network          │"
            echo "│  0) Back to Menu    │                                    │"
            echo "└─────────────────────────────────────────────────────────────┘"
            
            read -p "$(print_status "INPUT" "Select category: ")" category
            
            case $category in
                1) edit_basic_settings ;;
                2) edit_hardware_settings ;;
                3) edit_network_settings ;;
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
    while true; do
        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
        if validate_input "port" "$new_ssh_port"; then
            SSH_PORT="$new_ssh_port"
            break
        fi
    done
    
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

# Function to show VM performance metrics using available tools
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
                # Show process stats using available tools
                print_status "CPU" "Process Statistics:"
                if command -v htop &> /dev/null; then
                    echo "│ Use 'htop' to view process details"
                elif command -v ps &> /dev/null; then
                    ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers | awk '{printf "│ PID: %-5s CPU: %-4s MEM: %-4s\n", $1, $2, $3}'
                fi
                echo "├─────────────────────────────────────────────────────────────┤"
                
                # Show system resources
                print_status "INFO" "System Resources:"
                if command -v free &> /dev/null; then
                    free -h | awk 'NR<=2 {printf "│ %-15s %-10s %-10s %-10s\n", $1, $2, $3, $4}'
                fi
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "│ Configuration:"
            printf "│ %-20s: %-35s │\n" "Memory" "$MEMORY MB"
            printf "│ %-20s: %-35s │\n" "CPUs" "$CPUS"
            printf "│ %-20s: %-35s │\n" "Disk" "$DISK_SIZE"
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
        
        # Create backup using available tools
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

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        # Display VM status
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Virtual Machines ($vm_count total):"
            echo "┌─────┬──────────────────────┬────────────┬──────────────┐"
            echo "│ No. │ Name                 │ Status     │ SSH Port    │"
            echo "├─────┼──────────────────────┼────────────┼──────────────┤"
            
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
                
                printf "│ \033[1;36m%2d\033[0m │ %-20s │ %b │ %-12s │\n" \
                    $((i+1)) "$vm" "$status" "$port"
            done
            echo "└─────┴──────────────────────┴────────────┴──────────────┘"
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

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 24.04 LTS (Noble)"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Ubuntu 22.04 LTS (Jammy)"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Debian 12 (Bookworm)"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Debian 11 (Bullseye)"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# Start the main menu
main_menu
