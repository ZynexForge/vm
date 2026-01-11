#!/bin/bash
set -euo pipefail

# =============================================================================
# ZynexForge CloudStack™ Platform
# Version: 4.0.0 Ultra Pro
# =============================================================================

# Global Configuration
readonly USER_HOME="$HOME"
readonly CONFIG_DIR="$USER_HOME/.zynexforge"
readonly DATA_DIR="$USER_HOME/.zynexforge/data"
readonly LOG_FILE="$USER_HOME/.zynexforge/zynexforge.log"
readonly SSH_KEY_FILE="$USER_HOME/.ssh/zynexforge_ed25519"
readonly SCRIPT_VERSION="4.0.0 Ultra Pro"

# Color Definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# ASCII Art Banner
readonly ASCII_MAIN_ART=$(cat << 'EOF'
__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
EOF
)

# Simple OS Templates
declare -A OS_TEMPLATES=(
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu|ubuntu"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu|ubuntu"
    ["debian-12"]="Debian 12|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian|debian"
    ["alpine-3.19"]="Alpine Linux 3.19|3.19|https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso|root|alpine"
    ["centos-9"]="CentOS Stream 9|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos|centos"
    ["rocky-9"]="Rocky Linux 9|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky|rocky"
)

# Simple ISO Library
declare -A ISO_LIBRARY=(
    ["ubuntu-24.04-server"]="Ubuntu 24.04 Server|https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso|ubuntu|ubuntu"
    ["debian-12"]="Debian 12|https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso|debian|debian"
    ["almalinux-9"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9.3-x86_64-dvd.iso|alma|alma"
)

# Simple Nodes (Names Only)
declare -A NODES=(
    ["local"]="Local Machine"
    ["mumbai"]="🇮🇳 Mumbai"
    ["delhi"]="🇮🇳 Delhi"
    ["singapore"]="🇸🇬 Singapore"
    ["frankfurt"]="🇩🇪 Frankfurt"
    ["newyork"]="🇺🇸 New York"
    ["tokyo"]="🇯🇵 Tokyo"
)

# Simple Docker Images
declare -A DOCKER_IMAGES=(
    ["ubuntu"]="Ubuntu|ubuntu:latest"
    ["nginx"]="Nginx|nginx:alpine"
    ["mysql"]="MySQL|mysql:8.0"
    ["postgres"]="PostgreSQL|postgres:latest"
    ["redis"]="Redis|redis:alpine"
    ["nodejs"]="Node.js|node:20-alpine"
    ["python"]="Python|python:3.12-alpine"
    ["jupyter"]="Jupyter|jupyter/base-notebook"
)

# Simple LXD Images
declare -A LXD_IMAGES=(
    ["ubuntu"]="Ubuntu|ubuntu:22.04"
    ["debian"]="Debian|debian:12"
    ["alpine"]="Alpine|alpine:3.19"
    ["centos"]="CentOS|centos:stream9"
)

# Simple Jupyter Templates
declare -A JUPYTER_TEMPLATES=(
    ["data-science"]="Data Science|jupyter/datascience-notebook|8888"
    ["minimal"]="Minimal Python|jupyter/minimal-notebook|8890"
    ["tensorflow"]="TensorFlow|jupyter/tensorflow-notebook|8889"
)

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

print_header() {
    clear
    echo -e "${CYAN}"
    echo "$ASCII_MAIN_ART"
    echo -e "${NC}"
    echo -e "${YELLOW}⚡ ZynexForge CloudStack™${NC}"
    echo -e "${WHITE}🔥 Ultra Pro Edition | Version: ${SCRIPT_VERSION}${NC}"
    echo "=================================================================="
    echo
}

print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "SUCCESS") echo -e "${GREEN}✓${NC} $message" ;;
        "ERROR") echo -e "${RED}✗${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}⚠${NC} $message" ;;
        "INFO") echo -e "${BLUE}ℹ${NC} $message" ;;
        "INPUT") echo -e "${MAGENTA}?${NC} $message" ;;
        "PROGRESS") echo -e "${CYAN}⟳${NC} $message" ;;
        *) echo "$message" ;;
    esac
}

log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
}

check_dependencies() {
    local missing=()
    local tools=("qemu-system-x86_64" "qemu-img" "curl" "wget")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_status "INFO" "Installing dependencies..."
        
        if command -v apt-get > /dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils curl wget
        elif command -v dnf > /dev/null 2>&1; then
            sudo dnf install -y qemu-system-x86 qemu-img cloud-utils curl wget
        else
            print_status "ERROR" "Please install: ${missing[*]}"
            exit 1
        fi
    fi
    
    # Check KVM
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        KVM_AVAILABLE=true
    else
        KVM_AVAILABLE=false
    fi
}

generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 16
}

find_available_port() {
    local port=22000
    while netstat -tuln | grep -q ":$port "; do
        port=$((port + 1))
    done
    echo $port
}

# =============================================================================
# INITIALIZATION
# =============================================================================

initialize_platform() {
    print_status "INFO" "Initializing ZynexForge..."
    
    # Create directories
    mkdir -p "$CONFIG_DIR" \
             "$DATA_DIR/vms" \
             "$DATA_DIR/disks" \
             "$DATA_DIR/cloudinit" \
             "$DATA_DIR/isos" \
             "$DATA_DIR/backups"
    
    # Generate SSH key
    if [ ! -f "$SSH_KEY_FILE" ]; then
        ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
    fi
    
    # Check dependencies
    check_dependencies
    
    print_status "SUCCESS" "Platform ready!"
}

# =============================================================================
# QEMU/KVM VM CREATION
# =============================================================================

create_qemu_vm() {
    local node_name="$1"
    
    print_header
    echo -e "${GREEN}Create QEMU/KVM Virtual Machine${NC}"
    echo
    
    # VM Name
    while true; do
        read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
        if [[ "$vm_name" =~ ^[a-zA-Z0-9_-]{3,}$ ]] && [ ! -f "$DATA_DIR/vms/${vm_name}.conf" ]; then
            break
        fi
        print_status "ERROR" "Invalid name or already exists"
    done
    
    # OS Selection
    echo -e "${CYAN}Select OS Type:${NC}"
    local os_keys=("${!OS_TEMPLATES[@]}")
    for i in "${!os_keys[@]}"; do
        IFS='|' read -r name codename url username password <<< "${OS_TEMPLATES[${os_keys[$i]}]}"
        printf "%2d) %s\n" $((i+1)) "$name"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "Select OS (1-${#OS_TEMPLATES[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_TEMPLATES[@]} ]; then
            local selected="${os_keys[$((choice-1))]}"
            IFS='|' read -r os_name CODENAME IMG_URL USERNAME PASSWORD <<< "${OS_TEMPLATES[$selected]}"
            break
        fi
    done
    
    # Simple Resource Selection
    echo
    read -rp "$(print_status "INPUT" "Memory (MB, default: 2048): ")" memory
    memory="${memory:-2048}"
    
    read -rp "$(print_status "INPUT" "CPU Cores (default: 2): ")" cpus
    cpus="${cpus:-2}"
    
    read -rp "$(print_status "INPUT" "Disk Size (default: 20G): ")" disk_size
    disk_size="${disk_size:-20G}"
    
    # SSH Port
    SSH_PORT=$(find_available_port)
    
    # Create VM
    print_status "PROGRESS" "Creating VM..."
    
    # Download image if needed
    IMG_FILE="$DATA_DIR/disks/${vm_name}.qcow2"
    if [[ "$IMG_URL" == *.iso ]]; then
        ISO_FILE="$DATA_DIR/isos/$(basename "$IMG_URL")"
        if [ ! -f "$ISO_FILE" ]; then
            curl -L -o "$ISO_FILE" "$IMG_URL"
        fi
        qemu-img create -f qcow2 "$IMG_FILE" "$disk_size"
    else
        curl -L -o "/tmp/temp.img" "$IMG_URL"
        qemu-img convert -f qcow2 -O qcow2 "/tmp/temp.img" "$IMG_FILE"
        qemu-img resize "$IMG_FILE" "$disk_size"
        rm -f "/tmp/temp.img"
    fi
    
    # Create cloud-init
    SEED_FILE="$DATA_DIR/cloudinit/${vm_name}-seed.img"
    create_cloud_init_seed "$vm_name" "$vm_name" "$USERNAME" "$PASSWORD"
    
    # Save config
    save_vm_config "$vm_name" "$node_name" "$os_name" "$IMG_URL" "$vm_name" "$USERNAME" "$PASSWORD" \
                   "$disk_size" "$memory" "$cpus" "$SSH_PORT" "no" "" "$IMG_FILE" "$SEED_FILE"
    
    print_status "SUCCESS" "VM '$vm_name' created!"
    print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    print_status "INFO" "Password: $PASSWORD"
    
    read -rp "$(print_status "INPUT" "Start VM now? (y/n): ")" start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        start_vm "$vm_name"
    fi
}

create_cloud_init_seed() {
    local vm_name=$1 hostname=$2 username=$3 password=$4
    local cloud_dir="/tmp/cloud-init-$vm_name"
    
    mkdir -p "$cloud_dir"
    
    cat > "$cloud_dir/user-data" << EOF
#cloud-config
hostname: $hostname
users:
  - name: $username
    sudo: ALL=(ALL) NOPASSWD:ALL
    passwd: $(echo "$password" | openssl passwd -6 -stdin)
    ssh_authorized_keys:
      - $(cat "${SSH_KEY_FILE}.pub")
EOF
    
    cat > "$cloud_dir/meta-data" << EOF
instance-id: $vm_name
local-hostname: $hostname
EOF
    
    cloud-localds "$SEED_FILE" "$cloud_dir/user-data" "$cloud_dir/meta-data"
    rm -rf "$cloud_dir"
}

save_vm_config() {
    local config_file="$DATA_DIR/vms/$1.conf"
    cat > "$config_file" << EOF
VM_NAME="$1"
NODE_ID="$2"
OS_TYPE="$3"
IMG_URL="$4"
HOSTNAME="$5"
USERNAME="$6"
PASSWORD="$7"
DISK_SIZE="$8"
MEMORY="$9"
CPUS="${10}"
SSH_PORT="${11}"
GUI_MODE="${12}"
PORT_FORWARDS="${13}"
IMG_FILE="${14}"
SEED_FILE="${15}"
CREATED="$(date)"
STATUS="stopped"
EOF
}

start_vm() {
    local vm_name=$1
    source "$DATA_DIR/vms/$vm_name.conf" 2>/dev/null || return 1
    
    # Check if already running
    if ps aux | grep -q "[q]emu-system.*$IMG_FILE"; then
        print_status "WARNING" "VM is already running"
        return
    fi
    
    # Build QEMU command
    local qemu_cmd="qemu-system-x86_64"
    qemu_cmd+=" -name $vm_name"
    qemu_cmd+=" -m ${MEMORY}M"
    qemu_cmd+=" -smp $CPUS"
    
    # Add KVM if available
    if [ "$KVM_AVAILABLE" = true ]; then
        qemu_cmd+=" -enable-kvm -cpu host"
    else
        qemu_cmd+=" -cpu qemu64"
    fi
    
    qemu_cmd+=" -drive file=$IMG_FILE,if=virtio,format=qcow2"
    qemu_cmd+=" -drive file=$SEED_FILE,if=virtio,format=raw"
    qemu_cmd+=" -netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
    qemu_cmd+=" -device virtio-net-pci,netdev=net0"
    qemu_cmd+=" -nographic"
    qemu_cmd+=" -daemonize"
    qemu_cmd+=" -pidfile /tmp/qemu-$vm_name.pid"
    
    # Start VM
    if eval "$qemu_cmd"; then
        sed -i "s/STATUS=.*/STATUS=\"running\"/" "$DATA_DIR/vms/$vm_name.conf"
        print_status "SUCCESS" "VM '$vm_name' started!"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    else
        print_status "ERROR" "Failed to start VM"
    fi
}

# =============================================================================
# DOCKER CONTAINER CREATION
# =============================================================================

create_docker_vm() {
    local node_name="$1"
    
    print_header
    echo -e "${GREEN}Create Docker Container${NC}"
    echo
    
    # Container Name
    while true; do
        read -rp "$(print_status "INPUT" "Container Name: ")" container_name
        if [[ "$container_name" =~ ^[a-zA-Z0-9_-]{3,}$ ]]; then
            if ! docker ps -a --format "{{.Names}}" | grep -q "^$container_name$"; then
                break
            fi
            print_status "ERROR" "Container already exists"
        fi
    done
    
    # Image Selection
    echo -e "${CYAN}Select Docker Image:${NC}"
    local img_keys=("${!DOCKER_IMAGES[@]}")
    for i in "${!img_keys[@]}"; do
        IFS='|' read -r name image <<< "${DOCKER_IMAGES[${img_keys[$i]}]}"
        printf "%2d) %s\n" $((i+1)) "$name"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "Select Image (1-${#DOCKER_IMAGES[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#DOCKER_IMAGES[@]} ]; then
            IFS='|' read -r name DOCKER_IMAGE <<< "${DOCKER_IMAGES[${img_keys[$((choice-1))]}]}"
            break
        fi
    done
    
    # Port Mapping
    read -rp "$(print_status "INPUT" "Port Mapping (e.g., 8080:80 or leave empty): ")" port_mapping
    
    # Create Container
    print_status "PROGRESS" "Creating container..."
    
    local docker_cmd="docker run -d"
    docker_cmd+=" --name $container_name"
    docker_cmd+=" --restart unless-stopped"
    [ -n "$port_mapping" ] && docker_cmd+=" -p $port_mapping"
    docker_cmd+=" $DOCKER_IMAGE"
    
    if eval "$docker_cmd"; then
        print_status "SUCCESS" "Container '$container_name' created!"
        
        # Save config
        local config_file="$DATA_DIR/vms/${container_name}.conf"
        cat > "$config_file" << EOF
CONTAINER_NAME="$container_name"
DOCKER_IMAGE="$DOCKER_IMAGE"
PORTS="$port_mapping"
CREATED="$(date)"
STATUS="running"
TYPE="docker"
EOF
        
        # Show info
        echo
        echo -e "${GREEN}Container Info:${NC}"
        echo "  Name: $container_name"
        echo "  Image: $DOCKER_IMAGE"
        [ -n "$port_mapping" ] && echo "  Ports: $port_mapping"
        docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name" | \
            xargs -I {} echo "  IP: {}"
    else
        print_status "ERROR" "Failed to create container"
    fi
}

# =============================================================================
# LXD CONTAINER CREATION
# =============================================================================

create_lxd_vm() {
    local node_name="$1"
    
    print_header
    echo -e "${GREEN}Create LXD Container${NC}"
    echo
    
    # Check LXD
    if ! command -v lxd > /dev/null 2>&1; then
        print_status "ERROR" "LXD not installed"
        read -rp "$(print_status "INPUT" "Install LXD? (y/n): ")" install_lxd
        if [[ "$install_lxd" =~ ^[Yy]$ ]]; then
            sudo snap install lxd
            sudo lxd init --auto
        else
            return
        fi
    fi
    
    # Container Name
    while true; do
        read -rp "$(print_status "INPUT" "Container Name: ")" container_name
        if [[ "$container_name" =~ ^[a-zA-Z0-9_-]{3,}$ ]]; then
            if ! lxc list --format csv | grep -q "^$container_name,"; then
                break
            fi
            print_status "ERROR" "Container already exists"
        fi
    done
    
    # Image Selection
    echo -e "${CYAN}Select LXD Image:${NC}"
    local img_keys=("${!LXD_IMAGES[@]}")
    for i in "${!img_keys[@]}"; do
        IFS='|' read -r name image <<< "${LXD_IMAGES[${img_keys[$i]}]}"
        printf "%2d) %s\n" $((i+1)) "$name"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "Select Image (1-${#LXD_IMAGES[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#LXD_IMAGES[@]} ]; then
            IFS='|' read -r name LXD_IMAGE <<< "${LXD_IMAGES[${img_keys[$((choice-1))]}]}"
            break
        fi
    done
    
    # Create Container
    print_status "PROGRESS" "Creating LXD container..."
    
    if lxc launch "$LXD_IMAGE" "$container_name"; then
        print_status "SUCCESS" "LXD container '$container_name' created!"
        
        # Save config
        local config_file="$DATA_DIR/vms/${container_name}.conf"
        cat > "$config_file" << EOF
CONTAINER_NAME="$container_name"
LXD_IMAGE="$LXD_IMAGE"
CREATED="$(date)"
STATUS="running"
TYPE="lxd"
EOF
        
        # Show info
        echo
        echo -e "${GREEN}Container Info:${NC}"
        echo "  Name: $container_name"
        echo "  Image: $LXD_IMAGE"
        lxc list "$container_name" --format json | jq -r '.[] | "  IP: \(.state.network.eth0.addresses[0].address)"'
        
        read -rp "$(print_status "INPUT" "Open shell? (y/n): ")" open_shell
        if [[ "$open_shell" =~ ^[Yy]$ ]]; then
            lxc exec "$container_name" -- /bin/bash
        fi
    else
        print_status "ERROR" "Failed to create LXD container"
    fi
}

# =============================================================================
# JUPYTER CREATION
# =============================================================================

create_jupyter_vm() {
    local node_name="$1"
    
    print_header
    echo -e "${GREEN}Create Jupyter Notebook${NC}"
    echo
    
    # Notebook Name
    while true; do
        read -rp "$(print_status "INPUT" "Notebook Name: ")" notebook_name
        if [[ "$notebook_name" =~ ^[a-zA-Z0-9_-]{3,}$ ]]; then
            if [ ! -f "$DATA_DIR/vms/${notebook_name}.conf" ]; then
                break
            fi
            print_status "ERROR" "Notebook already exists"
        fi
    done
    
    # Template Selection
    echo -e "${CYAN}Select Template:${NC}"
    local temp_keys=("${!JUPYTER_TEMPLATES[@]}")
    for i in "${!temp_keys[@]}"; do
        IFS='|' read -r name image port <<< "${JUPYTER_TEMPLATES[${temp_keys[$i]}]}"
        printf "%2d) %s\n" $((i+1)) "$name"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "Select Template (1-${#JUPYTER_TEMPLATES[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#JUPYTER_TEMPLATES[@]} ]; then
            IFS='|' read -r name JUPYTER_IMAGE JUPYTER_PORT <<< "${JUPYTER_TEMPLATES[${temp_keys[$((choice-1))]}]}"
            break
        fi
    done
    
    # Find available port
    local available_port=$(find_available_port "$JUPYTER_PORT")
    
    # Create Volume
    local volume_path="$DATA_DIR/jupyter/${notebook_name}"
    mkdir -p "$volume_path"
    
    # Create Notebook
    print_status "PROGRESS" "Creating Jupyter notebook..."
    
    local docker_cmd="docker run -d"
    docker_cmd+=" --name jupyter-$notebook_name"
    docker_cmd+=" -p $available_port:8888"
    docker_cmd+=" -v $volume_path:/home/jovyan/work"
    docker_cmd+=" --restart unless-stopped"
    docker_cmd+=" $JUPYTER_IMAGE"
    
    if eval "$docker_cmd"; then
        print_status "SUCCESS" "Jupyter notebook '$notebook_name' created!"
        
        # Save config
        local config_file="$DATA_DIR/vms/${notebook_name}.conf"
        cat > "$config_file" << EOF
NOTEBOOK_NAME="$notebook_name"
JUPYTER_IMAGE="$JUPYTER_IMAGE"
JUPYTER_PORT="$available_port"
VOLUME_PATH="$volume_path"
CREATED="$(date)"
STATUS="running"
TYPE="jupyter"
EOF
        
        # Show info
        echo
        echo -e "${GREEN}Notebook Info:${NC}"
        echo "  Name: $notebook_name"
        echo "  URL: http://localhost:$available_port"
        echo "  Volume: $volume_path"
        
        # Get token
        sleep 2
        local token=$(docker logs "jupyter-$notebook_name" 2>/dev/null | grep -o "token=[a-zA-Z0-9]*" | head -1)
        if [ -n "$token" ]; then
            echo "  Token: ${token#token=}"
        fi
    else
        print_status "ERROR" "Failed to create Jupyter notebook"
    fi
}

# =============================================================================
# MAIN MENU
# =============================================================================

main_menu() {
    while true; do
        print_header
        
        # Show existing VMs
        local vms=($(find "$DATA_DIR/vms" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
        if [ ${#vms[@]} -gt 0 ]; then
            echo -e "${GREEN}Existing VMs:${NC}"
            for vm in "${vms[@]}"; do
                local status="stopped"
                if source "$DATA_DIR/vms/$vm.conf" 2>/dev/null; then
                    case "$TYPE" in
                        "docker")
                            if docker ps --format "{{.Names}}" | grep -q "^$vm$"; then
                                status="running"
                            fi
                            ;;
                        "lxd")
                            if lxc list --format csv | grep -q "^$vm,.*,RUNNING"; then
                                status="running"
                            fi
                            ;;
                        "jupyter")
                            if docker ps --format "{{.Names}}" | grep -q "^jupyter-$vm$"; then
                                status="running"
                            fi
                            ;;
                        *)
                            if [ -f "/tmp/qemu-$vm.pid" ] && ps -p "$(cat "/tmp/qemu-$vm.pid")" > /dev/null 2>&1; then
                                status="running"
                            fi
                            ;;
                    esac
                    
                    if [ "$status" = "running" ]; then
                        echo "  🟢 $vm"
                    else
                        echo "  🔴 $vm"
                    fi
                fi
            done
            echo
        fi
        
        echo -e "${CYAN}Main Menu:${NC}"
        echo "  1) Create New VM/Container"
        echo "  2) Manage Existing"
        echo "  3) View VM Info"
        echo "  4) Start/Stop VM"
        echo "  5) Delete VM"
        echo "  0) Exit"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1) create_vm_menu ;;
            2) manage_vms_menu ;;
            3) view_vm_info ;;
            4) start_stop_vm ;;
            5) delete_vm ;;
            0) 
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        echo
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

create_vm_menu() {
    print_header
    echo -e "${GREEN}Create New VM/Container${NC}"
    echo
    
    # Node Selection
    echo -e "${CYAN}Select Location:${NC}"
    local node_keys=("${!NODES[@]}")
    for i in "${!node_keys[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${NODES[${node_keys[$i]}]}"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "Select Location (1-${#NODES[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#NODES[@]} ]; then
            local selected_node="${node_keys[$((choice-1))]}"
            local node_name="${NODES[$selected_node]}"
            break
        fi
    done
    
    # Technology Selection
    echo
    echo -e "${CYAN}Select Technology:${NC}"
    echo "  1) QEMU (No KVM)"
    echo "  2) QEMU/KVM"
    echo "  3) Docker"
    echo "  4) LXD"
    echo "  5) Jupyter"
    
    while true; do
        read -rp "$(print_status "INPUT" "Select Technology (1-5): ")" tech_choice
        
        case $tech_choice in
            1|2)
                if [ "$tech_choice" = "2" ] && [ "$KVM_AVAILABLE" = false ]; then
                    print_status "WARNING" "KVM not available. Using QEMU only."
                fi
                create_qemu_vm "$node_name"
                break
                ;;
            3)
                if ! command -v docker > /dev/null 2>&1; then
                    print_status "ERROR" "Docker not installed"
                else
                    create_docker_vm "$node_name"
                fi
                break
                ;;
            4)
                create_lxd_vm "$node_name"
                break
                ;;
            5)
                create_jupyter_vm "$node_name"
                break
                ;;
            *)
                print_status "ERROR" "Invalid choice"
                ;;
        esac
    done
}

manage_vms_menu() {
    print_header
    echo -e "${GREEN}Manage VMs/Containers${NC}"
    echo
    
    local vms=($(find "$DATA_DIR/vms" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
    if [ ${#vms[@]} -eq 0 ]; then
        print_status "INFO" "No VMs found"
        return
    fi
    
    for i in "${!vms[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${vms[$i]}"
    done
    
    echo
    read -rp "$(print_status "INPUT" "Select VM (1-${#vms[@]}): ")" vm_choice
    
    if [[ "$vm_choice" =~ ^[0-9]+$ ]] && [ "$vm_choice" -ge 1 ] && [ "$vm_choice" -le ${#vms[@]} ]; then
        local vm_name="${vms[$((vm_choice-1))]}"
        vm_actions_menu "$vm_name"
    else
        print_status "ERROR" "Invalid selection"
    fi
}

vm_actions_menu() {
    local vm_name="$1"
    
    while true; do
        print_header
        echo -e "${GREEN}Manage: $vm_name${NC}"
        echo
        
        echo "  1) Start"
        echo "  2) Stop"
        echo "  3) Restart"
        echo "  4) View Logs"
        echo "  5) Connect"
        echo "  0) Back"
        echo
        
        read -rp "$(print_status "INPUT" "Select action: ")" action
        
        case $action in
            1) start_vm_action "$vm_name" ;;
            2) stop_vm_action "$vm_name" ;;
            3) restart_vm_action "$vm_name" ;;
            4) view_logs_action "$vm_name" ;;
            5) connect_vm_action "$vm_name" ;;
            0) return ;;
            *) print_status "ERROR" "Invalid action" ;;
        esac
        
        echo
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

start_vm_action() {
    local vm_name="$1"
    
    if [ ! -f "$DATA_DIR/vms/$vm_name.conf" ]; then
        print_status "ERROR" "VM not found"
        return
    fi
    
    source "$DATA_DIR/vms/$vm_name.conf"
    
    case "$TYPE" in
        "docker")
            docker start "$vm_name" 2>/dev/null && print_status "SUCCESS" "Container started"
            ;;
        "lxd")
            lxc start "$vm_name" 2>/dev/null && print_status "SUCCESS" "Container started"
            ;;
        "jupyter")
            docker start "jupyter-$vm_name" 2>/dev/null && print_status "SUCCESS" "Notebook started"
            ;;
        *)
            start_vm "$vm_name"
            ;;
    esac
}

stop_vm_action() {
    local vm_name="$1"
    
    if [ ! -f "$DATA_DIR/vms/$vm_name.conf" ]; then
        print_status "ERROR" "VM not found"
        return
    fi
    
    source "$DATA_DIR/vms/$vm_name.conf"
    
    case "$TYPE" in
        "docker")
            docker stop "$vm_name" 2>/dev/null && print_status "SUCCESS" "Container stopped"
            ;;
        "lxd")
            lxc stop "$vm_name" 2>/dev/null && print_status "SUCCESS" "Container stopped"
            ;;
        "jupyter")
            docker stop "jupyter-$vm_name" 2>/dev/null && print_status "SUCCESS" "Notebook stopped"
            ;;
        *)
            if [ -f "/tmp/qemu-$vm_name.pid" ]; then
                kill -TERM "$(cat "/tmp/qemu-$vm_name.pid")" 2>/dev/null
                rm -f "/tmp/qemu-$vm_name.pid"
                sed -i "s/STATUS=.*/STATUS=\"stopped\"/" "$DATA_DIR/vms/$vm_name.conf"
                print_status "SUCCESS" "VM stopped"
            fi
            ;;
    esac
}

view_vm_info() {
    print_header
    echo -e "${GREEN}View VM Information${NC}"
    echo
    
    local vms=($(find "$DATA_DIR/vms" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
    if [ ${#vms[@]} -eq 0 ]; then
        print_status "INFO" "No VMs found"
        return
    fi
    
    for i in "${!vms[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${vms[$i]}"
    done
    
    echo
    read -rp "$(print_status "INPUT" "Select VM (1-${#vms[@]}): ")" vm_choice
    
    if [[ "$vm_choice" =~ ^[0-9]+$ ]] && [ "$vm_choice" -ge 1 ] && [ "$vm_choice" -le ${#vms[@]} ]; then
        local vm_name="${vms[$((vm_choice-1))]}"
        
        if [ -f "$DATA_DIR/vms/$vm_name.conf" ]; then
            echo
            echo -e "${CYAN}VM Configuration:${NC}"
            cat "$DATA_DIR/vms/$vm_name.conf"
        fi
    else
        print_status "ERROR" "Invalid selection"
    fi
}

start_stop_vm() {
    print_header
    echo -e "${GREEN}Start/Stop VM${NC}"
    echo
    
    local vms=($(find "$DATA_DIR/vms" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
    if [ ${#vms[@]} -eq 0 ]; then
        print_status "INFO" "No VMs found"
        return
    fi
    
    for i in "${!vms[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${vms[$i]}"
    done
    
    echo
    read -rp "$(print_status "INPUT" "Select VM (1-${#vms[@]}): ")" vm_choice
    
    if [[ "$vm_choice" =~ ^[0-9]+$ ]] && [ "$vm_choice" -ge 1 ] && [ "$vm_choice" -le ${#vms[@]} ]; then
        local vm_name="${vms[$((vm_choice-1))]}"
        
        echo
        echo "  1) Start"
        echo "  2) Stop"
        echo "  3) Restart"
        
        read -rp "$(print_status "INPUT" "Select action: ")" action
        
        case $action in
            1) start_vm_action "$vm_name" ;;
            2) stop_vm_action "$vm_name" ;;
            3) 
                stop_vm_action "$vm_name"
                sleep 2
                start_vm_action "$vm_name"
                ;;
            *) print_status "ERROR" "Invalid action" ;;
        esac
    else
        print_status "ERROR" "Invalid selection"
    fi
}

delete_vm() {
    print_header
    echo -e "${GREEN}Delete VM/Container${NC}"
    echo
    
    local vms=($(find "$DATA_DIR/vms" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
    if [ ${#vms[@]} -eq 0 ]; then
        print_status "INFO" "No VMs found"
        return
    fi
    
    for i in "${!vms[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${vms[$i]}"
    done
    
    echo
    read -rp "$(print_status "INPUT" "Select VM to delete (1-${#vms[@]}): ")" vm_choice
    
    if [[ "$vm_choice" =~ ^[0-9]+$ ]] && [ "$vm_choice" -ge 1 ] && [ "$vm_choice" -le ${#vms[@]} ]; then
        local vm_name="${vms[$((vm_choice-1))]}"
        
        read -rp "$(print_status "INPUT" "Delete '$vm_name'? (y/n): ")" confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # Stop first
            stop_vm_action "$vm_name"
            
            # Remove based on type
            if [ -f "$DATA_DIR/vms/$vm_name.conf" ]; then
                source "$DATA_DIR/vms/$vm_name.conf"
                
                case "$TYPE" in
                    "docker")
                        docker rm -f "$vm_name" 2>/dev/null
                        ;;
                    "lxd")
                        lxc delete -f "$vm_name" 2>/dev/null
                        ;;
                    "jupyter")
                        docker rm -f "jupyter-$vm_name" 2>/dev/null
                        rm -rf "$DATA_DIR/jupyter/$vm_name"
                        ;;
                    *)
                        rm -f "$IMG_FILE" "$SEED_FILE" "/tmp/qemu-$vm_name.pid"
                        ;;
                esac
                
                rm -f "$DATA_DIR/vms/$vm_name.conf"
                print_status "SUCCESS" "VM '$vm_name' deleted"
            fi
        else
            print_status "INFO" "Deletion cancelled"
        fi
    else
        print_status "ERROR" "Invalid selection"
    fi
}

# =============================================================================
# START SCRIPT
# =============================================================================

# Initialize
initialize_platform

# Start main menu
main_menu

# Cleanup on exit
cleanup() {
    print_status "INFO" "Cleaning up..."
    # Stop QEMU VMs
    for pidfile in /tmp/qemu-*.pid; do
        if [ -f "$pidfile" ]; then
            kill -TERM "$(cat "$pidfile")" 2>/dev/null
            rm -f "$pidfile"
        fi
    done
}

trap cleanup EXIT
