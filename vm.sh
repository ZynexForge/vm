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
\____    /__>.__. ____   ____ ___  __\_   _____/__________  ____   ____  
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

# Advanced CPU detection function
detect_cpu_advanced() {
    print_status "CPU" "Advanced CPU Detection"
    echo "┌─────────────────────────────────────────────────────────────┐"
    
    # Use cpuid command for detailed info
    if command -v cpuid &> /dev/null; then
        CPU_VENDOR=$(cpuid 2>/dev/null | grep -i "vendor" | head -1 | awk -F'"' '{print $2}' || echo "Unknown")
        CPU_FAMILY=$(cpuid 2>/dev/null | grep -i "family" | head -1 | awk '{print $3}' || echo "Unknown")
        CPU_MODEL=$(cpuid 2>/dev/null | grep -i "model" | head -1 | awk '{print $3}' || echo "Unknown")
        CPU_BRAND=$(cpuid 2>/dev/null | grep -i "brand" | head -1 || echo "Unknown")
        
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Vendor" "$CPU_VENDOR"
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Family" "$CPU_FAMILY"
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Model" "$CPU_MODEL"
        
        # Check for AMD specific features
        if [[ "$CPU_VENDOR" == *"AMD"* ]] || [[ "$CPU_VENDOR" == *"AuthenticAMD"* ]]; then
            IS_AMD=true
            print_status "CPU" "AMD Processor Detected!"
            
            # Detect AMD CPU family
            if [[ "$CPU_FAMILY" == "23" ]] || [[ "$CPU_FAMILY" == "25" ]]; then
                CPU_TYPE="AMD Zen (Ryzen/EPYC)"
                printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Type" "AMD Zen Architecture"
            elif [[ "$CPU_FAMILY" == "21" ]]; then
                CPU_TYPE="AMD Bulldozer"
                printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Type" "AMD Bulldozer Family"
            else
                CPU_TYPE="AMD Unknown"
                printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Type" "AMD Processor"
            fi
            
            # Check for AMD-V (SVM) support
            if grep -q "svm" /proc/cpuinfo 2>/dev/null; then
                printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "AMD-V" "Enabled ✓"
                SVM_SUPPORT=true
            else
                printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "AMD-V" "Disabled ✗"
                SVM_SUPPORT=false
            fi
            
            # Check for Nested Virtualization
            if [ -f "/sys/module/kvm_amd/parameters/nested" ]; then
                NESTED_VIRT=$(cat /sys/module/kvm_amd/parameters/nested 2>/dev/null || echo "0")
                if [ "$NESTED_VIRT" == "1" ] || [ "$NESTED_VIRT" == "Y" ]; then
                    printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Nested Virt" "Enabled ✓"
                else
                    printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Nested Virt" "Disabled ✗"
                fi
            fi
        else
            IS_AMD=false
            printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Type" "Intel/Other"
        fi
        
        # Get total cores and threads
        TOTAL_CORES=$(nproc 2>/dev/null || echo "4")
        TOTAL_THREADS=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "$TOTAL_CORES")
        
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Cores" "$TOTAL_CORES"
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Threads" "$TOTAL_THREADS"
        
    else
        # Fallback to /proc/cpuinfo
        CPU_VENDOR=$(grep -i "vendor" /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $3}' || echo "Unknown")
        TOTAL_CORES=$(nproc 2>/dev/null || echo "4")
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Vendor" "$CPU_VENDOR"
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Cores" "$TOTAL_CORES"
        IS_AMD=false
        if [[ "$CPU_VENDOR" == *"AMD"* ]] || grep -q "AMD" /proc/cpuinfo 2>/dev/null; then
            IS_AMD=true
            print_status "CPU" "AMD Processor Detected!"
        fi
    fi
    
    # Get total system memory
    if command -v free &> /dev/null; then
        TOTAL_MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "4096")
        printf "│ \033[1;36m%-15s\033[0m: %-40s │\n" "Total RAM" "${TOTAL_MEM}MB"
    fi
    
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
}

# Advanced AMD CPU optimizer function
amd_cpu_optimizer() {
    if [ "$IS_AMD" = true ]; then
        print_status "CPU" "Applying AMD-specific optimizations"
        
        # AMD CPU model selection
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│                   AMD CPU Optimization                     │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│ 1) EPYC Mode - Server CPU Profile (Recommended for servers)│"
        echo "│ 2) Ryzen Mode - Desktop CPU Profile (Recommended for GUI)  │"
        echo "│ 3) Host Passthrough - Direct CPU Passthrough               │"
        echo "│ 4) Custom CPU Model                                         │"
        echo "└─────────────────────────────────────────────────────────────┘"
        
        while true; do
            read -p "$(print_status "INPUT" "Select AMD CPU mode (1-4, default: 2): ")" amd_mode
            amd_mode="${amd_mode:-2}"
            
            case $amd_mode in
                1)
                    CPU_MODEL="EPYC"
                    CPU_OPTIONS="-cpu EPYC,vendor=AMD"
                    print_status "CPU" "AMD EPYC server profile selected"
                    ;;
                2)
                    CPU_MODEL="Ryzen"
                    CPU_OPTIONS="-cpu Ryzen,vendor=AMD"
                    print_status "CPU" "AMD Ryzen desktop profile selected"
                    ;;
                3)
                    CPU_MODEL="host"
                    CPU_OPTIONS="-cpu host"
                    print_status "CPU" "Host CPU passthrough selected"
                    ;;
                4)
                    read -p "$(print_status "INPUT" "Enter custom CPU model (e.g., Opteron_G5): ")" custom_cpu
                    CPU_MODEL="$custom_cpu"
                    CPU_OPTIONS="-cpu $custom_cpu"
                    print_status "CPU" "Custom CPU model '$custom_cpu' selected"
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            break
        done
        
        # AMD-specific optimizations
        if [ "$SVM_SUPPORT" = true ]; then
            CPU_OPTIONS="$CPU_OPTIONS,svm=on"
            
            # Ask about nested virtualization
            read -p "$(print_status "INPUT" "Enable nested virtualization? (y/N): ")" enable_nested
            if [[ "$enable_nested" =~ ^[Yy]$ ]]; then
                CPU_OPTIONS="$CPU_OPTIONS,nested=1"
                print_status "CPU" "Nested virtualization enabled"
            fi
        fi
        
        # Additional AMD optimizations
        CPU_OPTIONS="$CPU_OPTIONS,topoext=on"
        
        # Machine type for AMD
        MACHINE_TYPE="q35"
        if [ "$amd_mode" == "1" ] || [ "$amd_mode" == "3" ]; then
            MACHINE_TYPE="pc-q35-6.2"
        fi
        
        print_status "SUCCESS" "AMD optimizations applied: $CPU_MODEL"
        
    else
        # Non-AMD CPU - use host model
        CPU_MODEL="host"
        CPU_OPTIONS="-cpu host"
        MACHINE_TYPE="pc"
        print_status "INFO" "Using host CPU model"
    fi
}

# Function to check dependencies
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
    
    # Advanced CPU detection
    detect_cpu_advanced
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
        unset CPU_MODEL CPU_OPTIONS MACHINE_TYPE
        
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
CPU_MODEL="$CPU_MODEL"
CPU_OPTIONS="$CPU_OPTIONS"
MACHINE_TYPE="$MACHINE_TYPE"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Simple resource configuration function
configure_resources_simple() {
    print_status "CPU" "Resource Configuration"
    echo "┌─────────────────────────────────────────────────────────────┐"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Available Cores" "$TOTAL_CORES"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Available RAM" "${TOTAL_MEM}MB"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    
    # CPU Configuration
    while true; do
        read -p "$(print_status "INPUT" "Enter number of CPU cores (1-$TOTAL_CORES): ")" CPUS
        if validate_input "number" "$CPUS" && [ "$CPUS" -ge 1 ] && [ "$CPUS" -le "$TOTAL_CORES" ]; then
            break
        fi
    done
    
    # Memory Configuration
    while true; do
        read -p "$(print_status "INPUT" "Enter memory in MB (256-$TOTAL_MEM): ")" MEMORY
        if validate_input "number" "$MEMORY" && [ "$MEMORY" -ge 256 ] && [ "$MEMORY" -le "$TOTAL_MEM" ]; then
            break
        fi
    done
    
    # Disk Configuration
    while true; do
        read -p "$(print_status "INPUT" "Enter disk size (default: 40G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-40G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done
    
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
}

# Simple network configuration
configure_network_simple() {
    print_status "NET" "Network Configuration"
    
    # SSH Port
    while true; do
        read -p "$(print_status "INPUT" "Enter SSH port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done
    
    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,443:443): ")" PORT_FORWARDS
}

# Function to create new VM with advanced AMD support
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

    # VM Name
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

    # Hostname
    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    # Username
    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    # Password
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

    # AMD CPU Optimization
    amd_cpu_optimizer
    
    # Simple Resource Configuration
    configure_resources_simple
    
    # Simple Network Configuration
    configure_network_simple

    # Configuration Summary
    echo
    print_status "SUCCESS" "Configuration Summary"
    echo "┌─────────────────────────────────────────────────────────────┐"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "VM Name" "$VM_NAME"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "OS" "$OS_TYPE"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "CPU Model" "$CPU_MODEL"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "CPU Cores" "$CPUS"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Memory" "${MEMORY}MB"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Disk Size" "$DISK_SIZE"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "SSH Port" "$SSH_PORT"
    printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "GUI Mode" "$GUI_MODE"
    echo "└─────────────────────────────────────────────────────────────┘"
    
    # Confirmation
    read -p "$(print_status "INPUT" "Press Enter to create VM, or 'n' to cancel: ")" confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_status "INFO" "VM creation cancelled"
        return
    fi

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
        if ! wget --progress=bar:force:noscroll "$IMG_URL" -O "$IMG_FILE.tmp" 2>/dev/null; then
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

    if ! cloud-localds "$SEED_FILE" user-data meta-data 2>/dev/null; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
}

# Advanced VM start function with AMD optimizations
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
            -machine "$MACHINE_TYPE,accel=kvm"
            -smp "$CPUS"
            -m "$MEMORY"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c
            -device virtio-net-pci,netdev=n0
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )

        # Add CPU options
        qemu_cmd+=($CPU_OPTIONS)
        
        # Add port forwards if specified
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi

        # Add RNG device if available
        if [ -c /dev/urandom ]; then
            qemu_cmd+=(-object rng-random,filename=/dev/urandom,id=rng0)
            qemu_cmd+=(-device virtio-rng-pci,rng=rng0)
        fi

        # Add GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
            # Add USB tablet for better mouse integration
            qemu_cmd+=(-usb -device usb-tablet)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        # AMD-specific optimizations
        if [ "$IS_AMD" = true ]; then
            # Add IOMMU for AMD if available
            qemu_cmd+=(-device "virtio-iommu")
            print_status "CPU" "Starting with AMD optimizations: $CPU_MODEL"
        fi

        print_status "INFO" "Starting QEMU with configuration:"
        echo "CPU: $CPU_MODEL | Cores: $CPUS | RAM: ${MEMORY}MB | Disk: $DISK_SIZE"
        echo
        
        # Run QEMU
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
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "CPU Model" "$CPU_MODEL"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "CPU Cores" "$CPUS"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Memory" "$MEMORY MB"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "Disk" "$DISK_SIZE"
        printf "│ \033[1;36m%-20s\033[0m: %-35s │\n" "SSH Port" "$SSH_PORT"
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
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null 2>&1; then
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
            pkill -f "qemu-system-x86_64.*$IMG_FILE" 2>/dev/null || true
            sleep 2
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM did not stop gracefully, forcing termination..."
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE" 2>/dev/null || true
            fi
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
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

# Check dependencies and detect CPU
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
