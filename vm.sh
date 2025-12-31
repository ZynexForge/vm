#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager
# Enhanced Multi-VM Manager
# =============================

# Function to display header with ZynexForge branding
display_header() {
    clear
    cat << "EOF"

__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
                                                                         

                    ⚡ ZynexForge VM Manager ⚡
                    Enhanced Multi-VM Manager
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
        "ZYNEX") echo -e "\033[1;33m[ZynexForge]\033[0m $message" ;;
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

# Function to check dependencies
check_dependencies() {
    print_status "ZYNEX" "Checking system dependencies..."
    
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system cloud-image-utils wget"
        exit 1
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

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    print_status "ZYNEX" "Enhanced Multi-VM Manager"
    
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
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Password cannot be empty"
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

    # Additional network options
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
}

# Function to detect image format and convert if needed
detect_and_convert_image() {
    local image_file="$1"
    
    # Check if file exists
    if [[ ! -f "$image_file" ]]; then
        print_status "ERROR" "Image file not found: $image_file"
        return 1
    fi
    
    # Get file type using qemu-img info
    local image_info
    if image_info=$(qemu-img info "$image_file" 2>/dev/null); then
        local format=$(echo "$image_info" | grep -oP 'file format: \K\w+')
        
        if [[ -n "$format" ]]; then
            print_status "INFO" "Detected image format: $format"
            
            # If format is raw or qcow2, we're good
            if [[ "$format" == "qcow2" ]]; then
                return 0
            elif [[ "$format" == "raw" ]]; then
                # Convert raw to qcow2
                print_status "INFO" "Converting raw image to qcow2 format..."
                local temp_file="${image_file}.qcow2"
                if qemu-img convert -f raw -O qcow2 "$image_file" "$temp_file"; then
                    mv "$temp_file" "$image_file"
                    print_status "SUCCESS" "Image converted to qcow2 format"
                    return 0
                else
                    print_status "ERROR" "Failed to convert image format"
                    return 1
                fi
            else
                # Try to convert unknown format to qcow2
                print_status "INFO" "Converting $format image to qcow2 format..."
                local temp_file="${image_file}.qcow2"
                if qemu-img convert -f "$format" -O qcow2 "$image_file" "$temp_file"; then
                    mv "$temp_file" "$image_file"
                    print_status "SUCCESS" "Image converted to qcow2 format"
                    return 0
                else
                    print_status "ERROR" "Unsupported image format: $format"
                    return 1
                fi
            fi
        else
            # Try to determine format by file extension
            if [[ "$image_file" == *.iso ]] || [[ "$image_file" == *.ISO ]]; then
                print_status "INFO" "ISO file detected - treating as installation media"
                return 0
            else
                print_status "WARN" "Could not detect image format. Trying to use as-is..."
                # Try to convert anyway
                local temp_file="${image_file}.qcow2"
                if qemu-img convert -f raw -O qcow2 "$image_file" "$temp_file" 2>/dev/null; then
                    mv "$temp_file" "$image_file"
                    print_status "SUCCESS" "Image converted to qcow2 format"
                    return 0
                fi
                return 0
            fi
        fi
    else
        # If qemu-img info fails, try to determine by file extension
        if [[ "$image_file" == *.iso ]] || [[ "$image_file" == *.ISO ]]; then
            print_status "INFO" "ISO file detected - treating as installation media"
            return 0
        elif [[ "$image_file" == *.qcow2 ]] || [[ "$image_file" == *.img ]]; then
            print_status "INFO" "Assuming qcow2 format based on extension"
            return 0
        else
            print_status "WARN" "Could not determine image format. May cause issues."
            return 0
        fi
    fi
}

# Function to setup VM image - FIXED with proper format detection
setup_vm_image() {
    print_status "INFO" "Downloading and preparing image..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check if image already exists
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Checking format..."
        detect_and_convert_image "$IMG_FILE"
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        
        # Create a temporary file for download
        local temp_file="$VM_DIR/$VM_NAME.temp"
        
        # Try with curl first, then wget
        if command -v curl &> /dev/null; then
            if curl -k -L --progress-bar "$IMG_URL" -o "$temp_file"; then
                print_status "SUCCESS" "Image downloaded successfully with curl"
            else
                print_status "ERROR" "Failed to download image with curl"
                exit 1
            fi
        elif command -v wget &> /dev/null; then
            if wget --no-check-certificate --progress=bar:force "$IMG_URL" -O "$temp_file"; then
                print_status "SUCCESS" "Image downloaded successfully"
            else
                print_status "ERROR" "Failed to download image from $IMG_URL"
                print_status "INFO" "Trying alternative method..."
                if wget --no-check-certificate "$IMG_URL" -O "$temp_file"; then
                    print_status "SUCCESS" "Image downloaded (insecure mode)"
                else
                    print_status "ERROR" "Failed to download image. Please check your internet connection."
                    exit 1
                fi
            fi
        else
            print_status "ERROR" "Neither curl nor wget found. Cannot download image."
            exit 1
        fi
        
        # Move to final location
        mv "$temp_file" "$IMG_FILE"
        
        # Detect and convert image format if needed
        detect_and_convert_image "$IMG_FILE"
    fi
    
    # Resize the disk image if needed (only for qcow2 images)
    if qemu-img info "$IMG_FILE" 2>/dev/null | grep -q "file format: qcow2"; then
        print_status "INFO" "Resizing disk to $DISK_SIZE..."
        if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
            print_status "WARN" "Failed to resize disk image. Creating new image with specified size..."
            # Create a new image with the specified size
            local temp_file="${IMG_FILE}.new"
            qemu-img create -f qcow2 "$temp_file" "$DISK_SIZE"
            
            # Try to convert old image content to new one
            if qemu-img convert -f qcow2 -O qcow2 "$IMG_FILE" "$temp_file" 2>/dev/null; then
                mv "$temp_file" "$IMG_FILE"
            else
                # If conversion fails, just keep the new empty image
                mv "$temp_file" "$IMG_FILE"
                print_status "WARN" "Created new empty disk image"
            fi
        fi
    else
        print_status "INFO" "Not resizing non-qcow2 image (likely an ISO)"
    fi

    # Special handling for Proxmox and other ISO-based installations
    if [[ "$IMG_FILE" == *.iso ]] || [[ "$IMG_FILE" == *.ISO ]] || [[ "$OS_TYPE" == *"Proxmox"* ]]; then
        print_status "INFO" "Setting up installation media (ISO-based installation)..."
        
        # For ISO installations, we don't need seed file
        if [[ -f "$SEED_FILE" ]]; then
            rm -f "$SEED_FILE"
        fi
        
        # Create a new qcow2 disk image for installation
        local disk_file="${IMG_FILE%.*}.qcow2"
        if [[ ! -f "$disk_file" ]]; then
            print_status "INFO" "Creating installation disk..."
            qemu-img create -f qcow2 "$disk_file" "$DISK_SIZE"
        fi
        
        # Update IMG_FILE to point to the ISO for booting
        # We'll handle this in the start_vm function
        
        print_status "SUCCESS" "Installation media setup ready. Will boot from ISO for installation."
    else
        # cloud-init configuration for cloud images
        cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
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
        
        print_status "SUCCESS" "Cloud-init configuration created"
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
        
        # Check if seed file exists (for cloud images)
        if [[ "$IMG_FILE" != *.iso ]] && [[ "$IMG_FILE" != *.ISO ]] && [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Determine image type
        local image_format="qcow2"
        if [[ "$IMG_FILE" == *.iso ]] || [[ "$IMG_FILE" == *.ISO ]]; then
            image_format="raw"
            print_status "INFO" "Booting from ISO installation media"
            
            # Check if we have a disk file for installation
            local disk_file="${IMG_FILE%.*}.qcow2"
            if [[ ! -f "$disk_file" ]]; then
                print_status "INFO" "Creating installation disk..."
                qemu-img create -f qcow2 "$disk_file" "$DISK_SIZE"
            fi
        fi
        
        # Base QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -m "$MEMORY"
            -smp "$CPUS"
            -cpu host
        )

        # Add disk configuration based on image type
        if [[ "$IMG_FILE" == *.iso ]] || [[ "$IMG_FILE" == *.ISO ]]; then
            # ISO installation - use both ISO and disk
            qemu_cmd+=(
                -drive "file=${IMG_FILE%.*}.qcow2,format=qcow2,if=virtio"
                -cdrom "$IMG_FILE"
                -boot order=d
            )
        else
            # Cloud image with seed
            qemu_cmd+=(
                -drive "file=$IMG_FILE,format=$image_format,if=virtio"
                -drive "file=$SEED_FILE,format=raw,if=virtio"
                -boot order=c
            )
        fi

        # Network configuration
        qemu_cmd+=(
            -device virtio-net-pci,netdev=n0
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
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

        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )

        # Special instructions for Proxmox
        if [[ "$OS_TYPE" == *"Proxmox"* ]]; then
            print_status "INFO" "=================================================================="
            print_status "INFO" "PROXMOX VE INSTALLATION INSTRUCTIONS:"
            print_status "INFO" "1. Wait for Proxmox boot screen"
            print_status "INFO" "2. Select 'Install Proxmox VE'"
            print_status "INFO" "3. Follow installation wizard"
            print_status "INFO" "4. For disk: Select the VirtIO disk"
            print_status "INFO" "5. Set root password during installation"
            print_status "INFO" "6. After installation, VM will reboot"
            print_status "INFO" "7. Access Web UI: https://localhost:8006"
            print_status "INFO" "=================================================================="
        elif [[ "$IMG_FILE" == *.iso ]] || [[ "$IMG_FILE" == *.ISO ]]; then
            print_status "INFO" "=================================================================="
            print_status "INFO" "ISO INSTALLATION INSTRUCTIONS:"
            print_status "INFO" "1. Follow the OS installation wizard"
            print_status "INFO" "2. Use credentials you specified during VM creation"
            print_status "INFO" "3. After installation, you may need to restart"
            print_status "INFO" "=================================================================="
        fi

        print_status "INFO" "Starting QEMU with command:"
        echo "  ${qemu_cmd[@]}"
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
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            # Also delete any related files
            rm -f "${IMG_FILE%.*}.qcow2" "${IMG_FILE%.*}.temp" 2>/dev/null
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        else
            # Try to delete files even if config can't be loaded
            rm -f "$VM_DIR/$vm_name.img" "$VM_DIR/$vm_name-seed.iso" "$VM_DIR/$vm_name.conf" 2>/dev/null
            print_status "SUCCESS" "VM '$vm_name' files have been deleted"
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
        echo "=========================================="
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: $PASSWORD"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "GUI Mode: $GUI_MODE"
        echo "Port Forwards: ${PORT_FORWARDS:-None}"
        echo "Created: $CREATED"
        echo "Image File: $IMG_FILE"
        
        # Check image type
        if [[ "$IMG_FILE" == *.iso ]] || [[ "$IMG_FILE" == *.ISO ]]; then
            echo "Image Type: ISO Installation Media"
            local disk_file="${IMG_FILE%.*}.qcow2"
            if [[ -f "$disk_file" ]]; then
                echo "Installation Disk: $disk_file"
            fi
        else
            echo "Image Type: Cloud Image"
            echo "Seed File: ${SEED_FILE:-Not found}"
        fi
        
        # Check if VM is running
        if is_vm_running "$vm_name"; then
            echo "Status: \033[1;32mRunning\033[0m"
        else
            echo "Status: \033[1;31mStopped\033[0m"
        fi
        
        echo "=========================================="
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if load_vm_config "$vm_name" 2>/dev/null; then
        if pgrep -f "qemu-system-x86_64.*$IMG_FILE" >/dev/null; then
            return 0
        fi
    fi
    return 1
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
            echo "What would you like to edit?"
            echo "  1) Hostname"
            echo "  2) Username"
            echo "  3) Password"
            echo "  4) SSH Port"
            echo "  5) GUI Mode"
            echo "  6) Port Forwards"
            echo "  7) Memory (RAM)"
            echo "  8) CPU Count"
            echo "  9) Disk Size"
            echo "  0) Back to main menu"
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password cannot be empty"
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
                        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                        if validate_input "port" "$new_ssh_port"; then
                            # Check if port is already in use
                            if [ "$new_ssh_port" != "$SSH_PORT" ] && ss -tln 2>/dev/null | grep -q ":$new_ssh_port "; then
                                print_status "ERROR" "Port $new_ssh_port is already in use"
                            else
                                SSH_PORT="$new_ssh_port"
                                break
                            fi
                        fi
                    done
                    ;;
                5)
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
                            # Keep current value if user just pressed Enter
                            break
                        else
                            print_status "ERROR" "Please answer y or n"
                        fi
                    done
                    ;;
                6)
                    read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                9)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            # Recreate seed image with new configuration if user/password/hostname changed
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                print_status "INFO" "Updating cloud-init configuration..."
                setup_vm_image
            fi
            
            # Save configuration
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

# Function to resize VM disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current disk size: $DISK_SIZE"
        
        # Check if image is an ISO (can't resize ISO)
        if [[ "$IMG_FILE" == *.iso ]] || [[ "$IMG_FILE" == *.ISO ]]; then
            print_status "ERROR" "Cannot resize ISO installation media"
            print_status "INFO" "Resize the installation disk instead: ${IMG_FILE%.*}.qcow2"
            return 1
        fi
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "New disk size is the same as current size. No changes made."
                    return 0
                fi
                
                # Check if new size is smaller than current (not recommended)
                local current_size_num=${DISK_SIZE%[GgMm]}
                local new_size_num=${new_disk_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_disk_size: -1}
                
                # Convert both to MB for comparison
                if [[ "$current_unit" =~ [Gg] ]]; then
                    current_size_num=$((current_size_num * 1024))
                fi
                if [[ "$new_unit" =~ [Gg] ]]; then
                    new_size_num=$((new_size_num * 1024))
                fi
                
                if [[ $new_size_num -lt $current_size_num ]]; then
                    print_status "WARN" "Shrinking disk size is not recommended and may cause data loss!"
                    read -p "$(print_status "INPUT" "Are you sure you want to continue? (y/N): ")" confirm_shrink
                    if [[ ! "$confirm_shrink" =~ ^[Yy]$ ]]; then
                        print_status "INFO" "Disk resize cancelled."
                        return 0
                    fi
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
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Performance metrics for VM: $vm_name"
            echo "=========================================="
            
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                # Show process stats
                echo "QEMU Process Stats:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                
                # Show memory usage
                echo "Memory Usage:"
                free -h
                echo
                
                # Show disk usage
                echo "Disk Usage:"
                df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE"
                
                # Show network connections
                echo
                echo "Network Connections for port $SSH_PORT:"
                ss -tlnp | grep ":$SSH_PORT" || echo "No active connections on port $SSH_PORT"
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "Configuration:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
            echo "  Image: $(basename "$IMG_FILE")"
            if [[ -f "$IMG_FILE" ]]; then
                echo "  Image Size: $(du -h "$IMG_FILE" | cut -f1)"
            fi
        fi
        echo "=========================================="
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to backup VM
backup_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local backup_dir="$VM_DIR/backups"
        mkdir -p "$backup_dir"
        
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$backup_dir/${vm_name}_${timestamp}.tar.gz"
        
        print_status "INFO" "Backing up VM: $vm_name"
        print_status "INFO" "Backup file: $backup_file"
        
        # Stop VM if running
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM is running. Stopping for backup..."
            stop_vm "$vm_name"
            sleep 3
        fi
        
        # Create backup
        tar -czf "$backup_file" -C "$VM_DIR" "$vm_name.conf" "$(basename "$IMG_FILE")" 2>/dev/null
        if [[ -f "$SEED_FILE" ]]; then
            tar -czf "$backup_file" -C "$VM_DIR" "$vm_name.conf" "$(basename "$IMG_FILE")" "$(basename "$SEED_FILE")" 2>/dev/null || \
            tar -czf "$backup_file" -C "$VM_DIR" "$vm_name.conf" "$(basename "$IMG_FILE")" 2>/dev/null
        fi
        
        if [[ -f "$backup_file" ]]; then
            print_status "SUCCESS" "Backup created successfully: $backup_file"
            echo "  Size: $(du -h "$backup_file" | cut -f1)"
        else
            print_status "ERROR" "Failed to create backup"
        fi
    fi
}

# Function to restore VM from backup
restore_vm() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        print_status "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Extract VM name from backup filename
    local vm_name=$(basename "$backup_file" | cut -d'_' -f1)
    
    print_status "INFO" "Restoring VM: $vm_name"
    print_status "WARN" "This will overwrite any existing VM with the same name!"
    
    read -p "$(print_status "INPUT" "Continue? (y/N): ")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "INFO" "Restore cancelled"
        return 0
    fi
    
    # Stop VM if running
    if is_vm_running "$vm_name" 2>/dev/null; then
        stop_vm "$vm_name"
    fi
    
    # Extract backup
    tar -xzf "$backup_file" -C "$VM_DIR"
    
    if [[ $? -eq 0 ]]; then
        print_status "SUCCESS" "VM restored successfully: $vm_name"
        show_vm_info "$vm_name"
    else
        print_status "ERROR" "Failed to restore VM"
    fi
}

# Function to list backups
list_backups() {
    local backup_dir="$VM_DIR/backups"
    
    if [[ -d "$backup_dir" ]]; then
        local backups=($(ls -1 "$backup_dir"/*.tar.gz 2>/dev/null))
        local backup_count=${#backups[@]}
        
        if [[ $backup_count -gt 0 ]]; then
            print_status "INFO" "Found $backup_count backup(s):"
            for i in "${!backups[@]}"; do
                local file=$(basename "${backups[$i]}")
                local size=$(du -h "${backups[$i]}" | cut -f1)
                printf "  %2d) %s (%s)\n" $((i+1)) "$file" "$size"
            done
            echo
            return 0
        fi
    fi
    
    print_status "INFO" "No backups found"
    return 1
}

# Function to clone VM
clone_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local new_vm_name
        while true; do
            read -p "$(print_status "INPUT" "Enter name for cloned VM: ")" new_vm_name
            if validate_input "name" "$new_vm_name"; then
                if [[ -f "$VM_DIR/$new_vm_name.conf" ]]; then
                    print_status "ERROR" "VM with name '$new_vm_name' already exists"
                else
                    break
                fi
            fi
        done
        
        print_status "INFO" "Cloning VM '$vm_name' to '$new_vm_name'..."
        
        # Clone the disk image
        local new_img_file="$VM_DIR/$new_vm_name.img"
        if [[ -f "$IMG_FILE" ]]; then
            if qemu-img create -f qcow2 -b "$IMG_FILE" "$new_img_file" 2>/dev/null || \
               cp "$IMG_FILE" "$new_img_file"; then
                print_status "SUCCESS" "Disk image cloned"
            else
                print_status "ERROR" "Failed to clone disk image"
                return 1
            fi
        fi
        
        # Clone the seed file if it exists
        local new_seed_file="$VM_DIR/$new_vm_name-seed.iso"
        if [[ -f "$SEED_FILE" ]]; then
            if cp "$SEED_FILE" "$new_seed_file"; then
                print_status "SUCCESS" "Seed file cloned"
            fi
        fi
        
        # Create new configuration
        local original_name="$VM_NAME"
        VM_NAME="$new_vm_name"
        IMG_FILE="$new_img_file"
        SEED_FILE="$new_seed_file"
        CREATED="$(date)"
        
        # Modify hostname if it's the same as VM name
        if [[ "$HOSTNAME" == "$original_name" ]]; then
            HOSTNAME="$new_vm_name"
        fi
        
        save_vm_config
        print_status "SUCCESS" "VM cloned successfully: $new_vm_name"
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        print_status "ZYNEX" "Enhanced Multi-VM Manager"
        echo
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if is_vm_running "${vms[$i]}"; then
                    status="\033[1;32mRunning\033[0m"
                else
                    status="\033[1;31mStopped\033[0m"
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
            echo "  5) Edit VM configuration"
            echo "  6) Delete a VM"
            echo "  7) Resize VM disk"
            echo "  8) Show VM performance"
            echo "  9) Backup VM"
            echo " 10) Restore VM from backup"
            echo " 11) List backups"
            echo " 12) Clone VM"
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
            10)
                # List backups and let user choose one to restore
                if list_backups; then
                    read -p "$(print_status "INPUT" "Enter backup number to restore (or 0 to cancel): ")" backup_num
                    if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ]; then
                        local backups=($(ls -1 "$VM_DIR/backups"/*.tar.gz 2>/dev/null))
                        if [ "$backup_num" -le ${#backups[@]} ]; then
                            restore_vm "${backups[$((backup_num-1))]}"
                        else
                            print_status "ERROR" "Invalid selection"
                        fi
                    elif [[ "$backup_num" != "0" ]]; then
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "INFO" "No backups available to restore"
                fi
                ;;
            11)
                list_backups
                read -p "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            12)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to clone: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        clone_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            0)
                print_status "ZYNEX" "Thank you for using ZynexForge VM Manager!"
                echo "Goodbye!"
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
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"
mkdir -p "$VM_DIR/backups"

# Supported OS list - FIXED with proper format detection
declare -A OS_OPTIONS=(
    # Cloud images (qcow2 format)
    ["Ubuntu 22.04 LTS (Cloud Image)"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04 LTS (Cloud Image)"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11 Bullseye (Cloud Image)"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12 Bookworm (Cloud Image)"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40 (Cloud Image)"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9 (Cloud Image)"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9 (Cloud Image)"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9 (Cloud Image)"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
    
    # ISO installations
    ["Ubuntu 22.04 LTS (ISO)"]="ubuntu|jammy|https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04 LTS (ISO)"]="ubuntu|noble|https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso|ubuntu24|ubuntu|ubuntu"
    ["Debian 12 (ISO)"]="debian|bookworm|https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso|debian12|debian|debian"
    
    # REAL PROXMOX VE ISO IMAGES
    ["Proxmox VE 8.2 (ISO)"]="proxmox|ve82|https://download.proxmox.com/iso/proxmox-ve_8.2-1.iso|proxmox-ve82|root|proxmox123"
    ["Proxmox VE 8.1 (ISO)"]="proxmox|ve81|https://download.proxmox.com/iso/proxmox-ve_8.1-1.iso|proxmox-ve81|root|proxmox123"
    ["Proxmox VE 8.0 (ISO)"]="proxmox|ve80|https://download.proxmox.com/iso/proxmox-ve_8.0-2.iso|proxmox-ve80|root|proxmox123"
    ["Proxmox VE 7.4 (ISO)"]="proxmox|ve74|https://download.proxmox.com/iso/proxmox-ve_7.4-1.iso|proxmox-ve74|root|proxmox123"
)

# Start the main menu
main_menu
