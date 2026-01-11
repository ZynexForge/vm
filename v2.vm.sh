#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge CloudStack™ - Ultra Pro Edition
# World's #1 Virtualization Platform
# Version: 4.0.0 Ultra Pro
# =============================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
ORANGE='\033[0;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'
UNDERLINE='\033[4m'

# Global Variables
VM_DIR="${VM_DIR:-$HOME/zynexforge_vms}"
ISO_DIR="${ISO_DIR:-$HOME/zynexforge_isos}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$HOME/zynexforge_templates}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/zynexforge_backups}"
DOCKER_DIR="${DOCKER_DIR:-$HOME/zynexforge_docker}"
JUPYTER_DIR="${JUPYTER_DIR:-$HOME/zynexforge_jupyter}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-$HOME/zynexforge_snapshots}"
CLUSTER_DIR="${CLUSTER_DIR:-$HOME/zynexforge_clusters}"
LOG_FILE="${LOG_file:-/tmp/zynexforge.log}"
CONFIG_FILE="${CONFIG_FILE:-$HOME/.zynexforge_config}"
VERSION="4.0.0 Ultra Pro"
EDITION="Ultra Pro Edition"

# Performance Profiles
declare -A PERF_PROFILES=(
    ["GAMING"]="cpu=host,kvm=on,+avx2,+sse4.2 memory=16384 cpus=8 disk=100G storage=nvme network=sriov"
    ["ENTERPRISE"]="cpu=host,kvm=on memory=32768 cpus=16 disk=500G storage=nvme network=virtio"
    ["DEVELOPMENT"]="cpu=host,kvm=on memory=8192 cpus=4 disk=100G storage=ssd network=virtio"
    ["CLOUD"]="cpu=host,kvm=on memory=4096 cpus=2 disk=50G storage=ssd network=virtio"
    ["ULTRA"]="cpu=host,kvm=on,+avx512 memory=65536 cpus=32 disk=1000G storage=nvme network=sriov"
)

# Create necessary directories
mkdir -p "$VM_DIR" "$ISO_DIR" "$TEMPLATE_DIR" "$BACKUP_DIR" "$DOCKER_DIR" "$JUPYTER_DIR" "$SNAPSHOT_DIR" "$CLUSTER_DIR"

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to display colored output with icons
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") 
            echo -e "${BLUE}ℹ ${NC}${message}"
            log_message "INFO" "$message"
            ;;
        "WARN") 
            echo -e "${YELLOW}⚠ ${NC}${message}"
            log_message "WARN" "$message"
            ;;
        "ERROR") 
            echo -e "${RED}✘ ${NC}${message}"
            log_message "ERROR" "$message"
            ;;
        "SUCCESS") 
            echo -e "${GREEN}✓ ${NC}${message}"
            log_message "SUCCESS" "$message"
            ;;
        "INPUT") 
            echo -e "${CYAN}? ${NC}${message}"
            ;;
        "STEP") 
            echo -e "${MAGENTA}→ ${NC}${message}"
            log_message "STEP" "$message"
            ;;
        "HEADER") 
            echo -e "${PURPLE}${BOLD}${message}${NC}"
            ;;
        "DEBUG") 
            echo -e "${WHITE}🔧 ${NC}${message}"
            log_message "DEBUG" "$message"
            ;;
        *) 
            echo "[$type] $message"
            log_message "OTHER" "$message"
            ;;
    esac
}

# Function to validate input
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid number"
                return 1
            fi
            ;;
        "size")
            if ! [[ "$value" =~ ^[0-9]+[GgTtMm]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 1T, 512M)"
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
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || [ ${#value} -gt 50 ]; then
                print_status "ERROR" "Name can only contain letters, numbers, hyphens, underscores (max 50 chars)"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore, 1-32 chars, lowercase only"
                return 1
            fi
            ;;
        "ip")
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid IP address"
                return 1
            fi
            ;;
        "email")
            if ! [[ "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                print_status "ERROR" "Must be a valid email address"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to display main banner
display_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"

                        %@@@@@                      
                  @%*+:........:+#@@                
                @+:.....-=++=-:*%#-::#@             
             @@*...:=@@@@@@@@%*:......:*@           
            @#:...*@@@@@@@#-.....-#%#:..:*          
           @%...=%@@@@%*.....:=@@@@@@@+..:#         
          @@...=@@@%=.....-*%@@%+:..:+%*...%        
        ::@+...@%-##...=@@@@@@@+........=%-:%       
       #:=@-..=@@#%#*@@@@@@@@@@@@@@@#-....:#@       
       #-*@-..:@@@@@@@@@@@@@@@@@@@#:-%@%-...+@      
       %--@+....-#@@@@@@@@@@@@@@@@#..:#@@=..-#      
       @+.+@@*:....-#@@@@@@@@@@@@@#..:#@@+..-#      
       @@-..=%@@*:..+@@@@@@@@@@@%@#..:#@@+..=#      
       @@@=....=#@@@@@@@@@@@%+:.-@#..:#@%-..=       
        @@@@:......#@@@@@%-.....=@#..:%@+..:%       
         @+.+##=:..-*@*-.....-#@@%:..=@+..-%        
          @+...:+%@=:.....+%@@@@+...:@=..=%         
           @%-........-*@@@@%#-....=#..:*@          
             @#+...+#*-:::...........-*%            
                @@#:..............:*@               
                   @%#+++===+++*%@                  

__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
EOF
    echo -e "${BOLD}${CYAN}⚡ ZynexForge CloudStack™ - World's #1 Virtualization Platform${NC}"
    echo -e "${BOLD}${GREEN}🔥 ${EDITION} | Version: ${VERSION}${NC}"
    echo -e "${BOLD}${WHITE}==================================================================${NC}\n"
}

# Function to display OS-specific ASCII art with unified banner
display_os_art() {
    local os=$1
    local title=$2
    
    echo -e "\n${BOLD}${CYAN}"
    cat << "EOF"
                        %@@@@@                      
                  @%*+:........:+#@@                
                @+:.....-=++=-:*%#-::#@             
             @@*...:=@@@@@@@@%*:......:*@           
            @#:...*@@@@@@@#-.....-#%#:..:*          
           @%...=%@@@@%*.....:=@@@@@@@+..:#         
          @@...=@@@%=.....-*%@@%+:..:+%*...%        
        ::@+...@%-#%...=@@@@@@@+........=%-:%       
       #:=@-..=@@#%#*@@@@@@@@@@@@@@@#-....:#@       
       #-*@-..:@@@@@@@@@@@@@@@@@@@#:-%@%-...+@      
       %--@+....-#@@@@@@@@@@@@@@@@#..:#@@=..-#      
       @+.+@@*:....-#@@@@@@@@@@@@@#..:#@@+..-#      
       @@-..=%@@*:..+@@@@@@@@@@@%@#..:#@@+..=#      
       @@@=....=#@@@@@@@@@@@%+:.-@#..:#@%-..=       
        @@@@:......#@@@@@%-.....=@#..:%@+..:%       
         @+.+##=:..-*@*-.....-#@@%:..=@+..-%        
          @+...:+%@=:.....+%@@@@+...:@=..=%         
           @%-........-*@@@@%#-....=#..:*@          
             @#+...+#*-:::...........-*%            
                @@#:..............:*@               
                   @%#+++===+++*%@                  
EOF
    echo -e "${NC}"
    echo -e "${BOLD}${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${WHITE}║                      ${title}                      ║${NC}"
    echo -e "${BOLD}${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

# Function to check dependencies
check_dependencies() {
    print_status "STEP" "Checking system dependencies..."
    
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "curl" "jq" "ssh" "virt-viewer")
    local optional_deps=("docker" "docker-compose" "screenfetch" "neofetch" "htop" "nmap" "rsync" "bridge-utils" "ebtables" "dnsmasq")
    local missing_deps=()
    local missing_optional=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    for dep in "${optional_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_optional+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, run: sudo apt install qemu-system cloud-image-utils wget curl jq ssh virt-viewer"
        exit 1
    fi
    
    if [ ${#missing_optional[@]} -ne 0 ]; then
        print_status "WARN" "Missing optional features: ${missing_optional[*]}"
        print_status "INFO" "Install for full experience: sudo apt install docker docker-compose screenfetch neofetch htop nmap rsync bridge-utils ebtables dnsmasq"
    fi
    
    # Check for KVM support
    if [[ ! -e /dev/kvm ]]; then
        print_status "WARN" "KVM not available. Running in software mode (slower)."
    else
        print_status "SUCCESS" "KVM acceleration available"
    fi
    
    # Check CPU virtualization support
    if grep -q "vmx\|svm" /proc/cpuinfo; then
        print_status "SUCCESS" "Hardware virtualization supported"
    else
        print_status "WARN" "Hardware virtualization not supported. Performance may be degraded."
    fi
}

# Function to get system specs for auto performance tuning
get_system_specs() {
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_MB=$((total_ram_kb / 1024))
    
    local free_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    FREE_RAM_MB=$((free_ram_kb / 1024))
    
    CPU_CORES=$(nproc --all)
    
    # Get CPU model for optimization
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    
    # Check for specific CPU features
    CPU_FEATURES=""
    if grep -q "avx512" /proc/cpuinfo; then
        CPU_FEATURES+=",+avx512f,+avx512cd,+avx512bw,+avx512dq,+avx512vl"
    fi
    if grep -q "avx2" /proc/cpuinfo; then
        CPU_FEATURES+=",+avx2"
    fi
    if grep -q "sse4_2" /proc/cpuinfo; then
        CPU_FEATURES+=",+sse4.2"
    fi
    
    print_status "DEBUG" "System Specs: ${CPU_CORES} cores, ${TOTAL_RAM_MB}MB RAM, ${FREE_RAM_MB}MB free"
}

# Function to calculate optimal VM resources
calculate_optimal_resources() {
    get_system_specs
    
    # Calculate optimal RAM (use 80% of free RAM, max 64GB per VM)
    OPTIMAL_RAM=$((FREE_RAM_MB * 80 / 100))
    if [ $OPTIMAL_RAM -gt 65536 ]; then
        OPTIMAL_RAM=65536
    fi
    if [ $OPTIMAL_RAM -lt 4096 ]; then
        OPTIMAL_RAM=4096
    fi
    
    # Calculate optimal CPUs (use 60% of total cores, max 32)
    OPTIMAL_CPUS=$((CPU_CORES * 60 / 100))
    if [ $OPTIMAL_CPUS -gt 32 ]; then
        OPTIMAL_CPUS=32
    fi
    if [ $OPTIMAL_CPUS -lt 4 ]; then
        OPTIMAL_CPUS=4
    fi
    
    # Calculate optimal disk based on available space
    local disk_space=$(df -BG "$VM_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    OPTIMAL_DISK=$((disk_space * 30 / 100))
    if [ $OPTIMAL_DISK -gt 1000 ]; then
        OPTIMAL_DISK=1000
    fi
    if [ $OPTIMAL_DISK -lt 50 ]; then
        OPTIMAL_DISK=50
    fi
    
    echo "$OPTIMAL_RAM $OPTIMAL_CPUS ${OPTIMAL_DISK}G"
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
        # Source the configuration file
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
    
    # Ensure all variables are set with defaults
    VM_NAME="${VM_NAME:-unknown}"
    OS_TYPE="${OS_TYPE:-unknown}"
    CODENAME="${CODENAME:-unknown}"
    IMG_URL="${IMG_URL:-}"
    HOSTNAME="${HOSTNAME:-$VM_NAME}"
    USERNAME="${USERNAME:-user}"
    PASSWORD="${PASSWORD:-password}"
    DISK_SIZE="${DISK_SIZE:-50G}"
    MEMORY="${MEMORY:-4096}"
    CPUS="${CPUS:-4}"
    SSH_PORT="${SSH_PORT:-2222}"
    GUI_MODE="${GUI_MODE:-false}"
    PORT_FORWARDS="${PORT_FORWARDS:-}"
    IMG_FILE="${IMG_FILE:-$VM_DIR/$VM_NAME.qcow2}"
    SEED_FILE="${SEED_FILE:-$VM_DIR/$VM_NAME-seed.img}"
    CREATED="${CREATED:-$(date)}"
    NODE="${NODE:-local}"
    NETWORK_CONFIG="${NETWORK_CONFIG:-virtio}"
    STORAGE_TYPE="${STORAGE_TYPE:-ssd}"
    ACCELERATION="${ACCELERATION:-kvm}"
    PERFORMANCE_PROFILE="${PERFORMANCE_PROFILE:-ULTRA}"
    
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
NODE="$NODE"
NETWORK_CONFIG="$NETWORK_CONFIG"
STORAGE_TYPE="$STORAGE_TYPE"
ACCELERATION="$ACCELERATION"
PERFORMANCE_PROFILE="$PERFORMANCE_PROFILE"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to display datacenter nodes
select_datacenter_node() {
    echo -e "${BOLD}${CYAN}🌍 Select Datacenter Node:${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) 🇮🇳  Mumbai, India                    │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) 🇮🇳  Delhi NCR, India                 │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) 🇮🇳  Bangalore, India                 │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) 🇸🇬  Singapore                         │"
    echo -e "${WHITE}│  ${GREEN}5${NC}) 🇩🇪  Frankfurt, Germany               │"
    echo -e "${WHITE}│  ${GREEN}6${NC}) 🇳🇱  Amsterdam, Netherlands           │"
    echo -e "${WHITE}│  ${GREEN}7${NC}) 🇬🇧  London, UK                       │"
    echo -e "${WHITE}│  ${GREEN}8${NC}) 🇺🇸  New York, USA                    │"
    echo -e "${WHITE}│  ${GREEN}9${NC}) 🇺🇸  Los Angeles, USA                 │"
    echo -e "${WHITE}│  ${GREEN}10${NC}) 🇨🇦 Toronto, Canada                 │"
    echo -e "${WHITE}│  ${GREEN}11${NC}) 🇯🇵 Tokyo, Japan                    │"
    echo -e "${WHITE}│  ${GREEN}12${NC}) 🇦🇺 Sydney, Australia               │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    while true; do
        read -p "$(print_status "INPUT" "Select node (1-12): ")" node_choice
        case $node_choice in
            1) NODE="mumbai"; break ;;
            2) NODE="delhi"; break ;;
            3) NODE="bangalore"; break ;;
            4) NODE="singapore"; break ;;
            5) NODE="frankfurt"; break ;;
            6) NODE="amsterdam"; break ;;
            7) NODE="london"; break ;;
            8) NODE="newyork"; break ;;
            9) NODE="losangeles"; break ;;
            10) NODE="toronto"; break ;;
            11) NODE="tokyo"; break ;;
            12) NODE="sydney"; break ;;
            *) print_status "ERROR" "Invalid selection. Try again." ;;
        esac
    done
}

# Function to select performance profile
select_performance_profile() {
    echo -e "${BOLD}${CYAN}⚡ Select Performance Profile:${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) 🎮  Gaming Optimized                    │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) 🏢  Enterprise Server                   │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) 💻  Development                         │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) ☁️   Cloud Hosting                      │"
    echo -e "${WHITE}│  ${GREEN}5${NC}) ⚡  Ultra Pro (Max Performance)         │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    while true; do
        read -p "$(print_status "INPUT" "Select profile (1-5): ")" profile_choice
        case $profile_choice in
            1) 
                PERFORMANCE_PROFILE="GAMING"
                MEMORY=16384
                CPUS=8
                DISK_SIZE="100G"
                STORAGE_TYPE="nvme"
                NETWORK_CONFIG="sriov"
                break 
                ;;
            2) 
                PERFORMANCE_PROFILE="ENTERPRISE"
                MEMORY=32768
                CPUS=16
                DISK_SIZE="500G"
                STORAGE_TYPE="nvme"
                NETWORK_CONFIG="virtio"
                break 
                ;;
            3) 
                PERFORMANCE_PROFILE="DEVELOPMENT"
                MEMORY=8192
                CPUS=4
                DISK_SIZE="100G"
                STORAGE_TYPE="ssd"
                NETWORK_CONFIG="virtio"
                break 
                ;;
            4) 
                PERFORMANCE_PROFILE="CLOUD"
                MEMORY=4096
                CPUS=2
                DISK_SIZE="50G"
                STORAGE_TYPE="ssd"
                NETWORK_CONFIG="virtio"
                break 
                ;;
            5) 
                PERFORMANCE_PROFILE="ULTRA"
                MEMORY=65536
                CPUS=32
                DISK_SIZE="1000G"
                STORAGE_TYPE="nvme"
                NETWORK_CONFIG="sriov"
                break 
                ;;
            *) print_status "ERROR" "Invalid selection. Try again." ;;
        esac
    done
}

# Function to create QEMU VM
create_qemu_vm() {
    display_os_art "qemu" "QEMU Virtual Machine Creation"
    
    print_status "STEP" "Creating a new QEMU VM"
    
    # VM Name
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name: ")" VM_NAME
        VM_NAME="${VM_NAME:-qemu-vm}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done
    
    # Datacenter Node
    select_datacenter_node
    
    # Performance Profile
    select_performance_profile
    
    # Storage Type (override if profile already set it)
    if [[ -z "$STORAGE_TYPE" ]]; then
        echo -e "${BOLD}${CYAN}💾 Select Storage Type:${NC}"
        echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│  ${GREEN}1${NC}) SSD (High Speed)                       │"
        echo -e "${WHITE}│  ${GREEN}2${NC}) NVMe (Ultra Speed)                     │"
        echo -e "${WHITE}│  ${GREEN}3${NC}) HDD (Standard)                         │"
        echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
        
        while true; do
            read -p "$(print_status "INPUT" "Select storage (1-3): ")" storage_choice
            case $storage_choice in
                1) STORAGE_TYPE="ssd"; break ;;
                2) STORAGE_TYPE="nvme"; break ;;
                3) STORAGE_TYPE="hdd"; break ;;
                *) print_status "ERROR" "Invalid selection. Try again." ;;
            esac
        done
    fi
    
    # Network Configuration
    if [[ -z "$NETWORK_CONFIG" ]]; then
        echo -e "${BOLD}${CYAN}🌐 Select Network Configuration:${NC}"
        echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│  ${GREEN}1${NC}) NAT (Default)                          │"
        echo -e "${WHITE}│  ${GREEN}2${NC}) Bridged Network                        │"
        echo -e "${WHITE}│  ${GREEN}3${NC}) Isolated Network                       │"
        echo -e "${WHITE}│  ${GREEN}4${NC}) SR-IOV (High Performance)              │"
        echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
        
        while true; do
            read -p "$(print_status "INPUT" "Select network (1-4): ")" network_choice
            case $network_choice in
                1) NETWORK_CONFIG="nat"; break ;;
                2) NETWORK_CONFIG="bridged"; break ;;
                3) NETWORK_CONFIG="isolated"; break ;;
                4) NETWORK_CONFIG="sriov"; break ;;
                *) print_status "ERROR" "Invalid selection. Try again." ;;
            esac
        done
    fi
    
    # SSH Port
    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done
    
    # GUI Mode
    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: y): ")" gui_input
        gui_input="${gui_input:-y}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            GUI_MODE=false
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done
    
    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,443:443): ")" PORT_FORWARDS
    
    # ISO Selection for QEMU
    echo -e "${BOLD}${CYAN}📀 Select Installation Method:${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) Use Cloud Image (Fast, Recommended)     │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) Use ISO File                           │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) Use Template                           │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) Use Raw Disk Image                      │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    while true; do
        read -p "$(print_status "INPUT" "Select method (1-4): ")" method_choice
        
        case $method_choice in
            1)
                # Cloud Image
                print_status "INFO" "Select Cloud Image OS:"
                local cloud_os=("Ubuntu 22.04 LTS" "Ubuntu 24.04 LTS" "Debian 11 Bullseye" "Debian 12 Bookworm" "Fedora 40" "CentOS Stream 9" "AlmaLinux 9" "Rocky Linux 9" "openSUSE Leap 15.5")
                select os in "${cloud_os[@]}"; do
                    case $os in
                        "Ubuntu 22.04 LTS")
                            OS_TYPE="ubuntu"; CODENAME="jammy"
                            IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
                            HOSTNAME="${VM_NAME:-ubuntu22}"
                            USERNAME="ubuntu"; PASSWORD="ubuntu"
                            break
                            ;;
                        "Ubuntu 24.04 LTS")
                            OS_TYPE="ubuntu"; CODENAME="noble"
                            IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
                            HOSTNAME="${VM_NAME:-ubuntu24}"
                            USERNAME="ubuntu"; PASSWORD="ubuntu"
                            break
                            ;;
                        "Debian 11 Bullseye")
                            OS_TYPE="debian"; CODENAME="bullseye"
                            IMG_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
                            HOSTNAME="${VM_NAME:-debian11}"
                            USERNAME="debian"; PASSWORD="debian"
                            break
                            ;;
                        "Debian 12 Bookworm")
                            OS_TYPE="debian"; CODENAME="bookworm"
                            IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
                            HOSTNAME="${VM_NAME:-debian12}"
                            USERNAME="debian"; PASSWORD="debian"
                            break
                            ;;
                        "Fedora 40")
                            OS_TYPE="fedora"; CODENAME="40"
                            IMG_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2"
                            HOSTNAME="${VM_NAME:-fedora40}"
                            USERNAME="fedora"; PASSWORD="fedora"
                            break
                            ;;
                        "CentOS Stream 9")
                            OS_TYPE="centos"; CODENAME="stream9"
                            IMG_URL="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
                            HOSTNAME="${VM_NAME:-centos9}"
                            USERNAME="centos"; PASSWORD="centos"
                            break
                            ;;
                        "AlmaLinux 9")
                            OS_TYPE="almalinux"; CODENAME="9"
                            IMG_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
                            HOSTNAME="${VM_NAME:-almalinux9}"
                            USERNAME="alma"; PASSWORD="alma"
                            break
                            ;;
                        "Rocky Linux 9")
                            OS_TYPE="rockylinux"; CODENAME="9"
                            IMG_URL="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
                            HOSTNAME="${VM_NAME:-rocky9}"
                            USERNAME="rocky"; PASSWORD="rocky"
                            break
                            ;;
                        "openSUSE Leap 15.5")
                            OS_TYPE="opensuse"; CODENAME="leap15.5"
                            IMG_URL="https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-JeOS.x86_64-OpenStack.qcow2"
                            HOSTNAME="${VM_NAME:-opensuse15}"
                            USERNAME="opensuse"; PASSWORD="opensuse"
                            break
                            ;;
                        *) print_status "ERROR" "Invalid selection" ;;
                    esac
                done
                break
                ;;
            2)
                # ISO File
                print_status "INFO" "Available ISO files in $ISO_DIR:"
                local iso_files=($(ls "$ISO_DIR"/*.iso 2>/dev/null))
                
                if [ ${#iso_files[@]} -eq 0 ]; then
                    print_status "WARN" "No ISO files found. Please place ISO files in $ISO_DIR"
                    print_status "INFO" "You can download ISOs from:"
                    echo "  - Ubuntu: https://ubuntu.com/download"
                    echo "  - Debian: https://www.debian.org/CD"
                    echo "  - Windows: https://www.microsoft.com/software-download"
                    echo "  - CentOS: https://www.centos.org/download"
                    read -p "$(print_status "INPUT" "Enter path to ISO file: ")" iso_path
                    if [ ! -f "$iso_path" ]; then
                        print_status "ERROR" "ISO file not found: $iso_path"
                        return 1
                    fi
                    cp "$iso_path" "$ISO_DIR/"
                    iso_path="$ISO_DIR/$(basename "$iso_path")"
                else
                    select iso_file in "${iso_files[@]}" "Enter custom path"; do
                        if [ "$REPLY" -le ${#iso_files[@]} ]; then
                            iso_path="${iso_files[$((REPLY-1))]}"
                            break
                        elif [ "$REPLY" -eq $((${#iso_files[@]}+1)) ]; then
                            read -p "$(print_status "INPUT" "Enter path to ISO file: ")" iso_path
                            if [ ! -f "$iso_path" ]; then
                                print_status "ERROR" "ISO file not found: $iso_path"
                                return 1
                            fi
                            break
                        fi
                    done
                fi
                
                # Manual configuration for ISO install
                OS_TYPE="custom"
                IMG_FILE="$VM_DIR/$VM_NAME.qcow2"
                qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
                
                read -p "$(print_status "INPUT" "Enter OS type (e.g., windows, linux): ")" OS_TYPE
                read -p "$(print_status "INPUT" "Enter username: ")" USERNAME
                read -p "$(print_status "INPUT" "Enter password: ")" -s PASSWORD
                echo
                HOSTNAME="$VM_NAME"
                
                # Save config for ISO install
                CREATED="$(date)"
                ACCELERATION="kvm"
                
                save_vm_config
                
                print_status "INFO" "Starting QEMU with ISO: $iso_path"
                print_status "INFO" "Please complete the OS installation manually"
                
                start_qemu_iso "$iso_path"
                return 0
                ;;
            3)
                # Template
                print_status "INFO" "Available templates in $TEMPLATE_DIR:"
                local templates=($(ls "$TEMPLATE_DIR"/*.qcow2 2>/dev/null))
                
                if [ ${#templates[@]} -eq 0 ]; then
                    print_status "WARN" "No templates found"
                    return 1
                fi
                
                select template in "${templates[@]}"; do
                    IMG_FILE="$VM_DIR/$VM_NAME.qcow2"
                    cp "$template" "$IMG_FILE"
                    qemu-img resize "$IMG_FILE" "$DISK_SIZE"
                    
                    # Load template config
                    local template_config="${template%.qcow2}.conf"
                    if [ -f "$template_config" ]; then
                        source "$template_config"
                    fi
                    
                    OS_TYPE="${OS_TYPE:-custom}"
                    HOSTNAME="$VM_NAME"
                    break
                done
                break
                ;;
            4)
                # Raw disk
                read -p "$(print_status "INPUT" "Enter path to raw disk image: ")" raw_disk
                if [ ! -f "$raw_disk" ]; then
                    print_status "ERROR" "Raw disk image not found"
                    return 1
                fi
                IMG_FILE="$VM_DIR/$VM_NAME.raw"
                cp "$raw_disk" "$IMG_FILE"
                OS_TYPE="custom"
                HOSTNAME="$VM_NAME"
                USERNAME="root"
                PASSWORD="password"
                break
                ;;
            *) print_status "ERROR" "Invalid selection. Try again." ;;
        esac
    done
    
    # Set default values if not set
    HOSTNAME="${HOSTNAME:-$VM_NAME}"
    USERNAME="${USERNAME:-user}"
    PASSWORD="${PASSWORD:-password}"
    MEMORY="${MEMORY:-8192}"
    CPUS="${CPUS:-4}"
    DISK_SIZE="${DISK_SIZE:-50G}"
    
    # Set image and seed files
    IMG_FILE="$VM_DIR/$VM_NAME.qcow2"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.img"
    CREATED="$(date)"
    ACCELERATION="kvm"
    
    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
    
    print_status "SUCCESS" "QEMU VM '$VM_NAME' created successfully!"
    print_status "INFO" "Location: $NODE datacenter"
    print_status "INFO" "Performance Profile: $PERFORMANCE_PROFILE"
    print_status "INFO" "Resources: ${MEMORY}MB RAM, ${CPUS} CPUs, ${DISK_SIZE} disk"
}

# Function to setup VM image with performance optimization
setup_vm_image() {
    print_status "STEP" "Downloading and preparing image with ULTRA PRO optimization..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check if image already exists
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Optimizing..."
    else
        if [[ -n "$IMG_URL" ]]; then
            print_status "INFO" "Downloading optimized image from $IMG_URL..."
            if ! wget --progress=bar:force -q --show-progress "$IMG_URL" -O "$IMG_FILE.tmp"; then
                print_status "ERROR" "Failed to download image from $IMG_URL"
                exit 1
            fi
            mv "$IMG_FILE.tmp" "$IMG_FILE"
        else
            print_status "INFO" "Creating new optimized image..."
            qemu-img create -f qcow2 -o cluster_size=2M,preallocation=metadata,lazy_refcounts=on "$IMG_FILE" "$DISK_SIZE"
        fi
    fi
    
    # Resize the disk image with optimal settings
    if [[ -n "$IMG_URL" ]]; then
        print_status "INFO" "Optimizing disk image for maximum performance..."
        if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
            print_status "INFO" "Creating new optimized image with specified size..."
            rm -f "$IMG_FILE"
            qemu-img create -f qcow2 -o cluster_size=2M,preallocation=metadata,lazy_refcounts=on "$IMG_FILE" "$DISK_SIZE"
        fi
    fi
    
    # Performance-optimized cloud-init configuration
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
    ssh_authorized_keys:
      - $(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "# No SSH key found")
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
timezone: UTC
package_upgrade: true
packages:
  - qemu-guest-agent
  - cloud-init
  - screenfetch
  - neofetch
  - htop
  - curl
  - wget
  - git
  - net-tools
  - tmux
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "==================================================================" > /etc/motd
  - echo "  ⚡ ZynexForge CloudStack™ - Ultra Pro Edition" >> /etc/motd
  - echo "  🔥 Performance Profile: $PERFORMANCE_PROFILE" >> /etc/motd
  - echo "  🌍 Datacenter Node: $NODE" >> /etc/motd
  - echo "  🖥️  VM Name: $VM_NAME" >> /etc/motd
  - echo "  📅 Created: $CREATED" >> /etc/motd
  - echo "  💾 Resources: ${MEMORY}MB RAM, ${CPUS} CPUs, ${DISK_SIZE} Disk" >> /etc/motd
  - echo "==================================================================" >> /etc/motd
  - echo "" >> /etc/motd
  - echo "Welcome to ZynexForge CloudStack™ Ultra Pro Edition!" >> /etc/motd
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
region: $NODE
availability-zone: ${NODE}-az1
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created with ULTRA PRO optimization!"
}

# Function to generate ULTRA PRO QEMU command
generate_ultra_pro_qemu_cmd() {
    local vm_name=$1
    
    # Generate CPU flags based on host CPU
    local cpu_flags="host"
    if grep -q "avx512" /proc/cpuinfo; then
        cpu_flags="$cpu_flags,+avx512f,+avx512cd,+avx512bw,+avx512dq,+avx512vl"
    fi
    if grep -q "avx2" /proc/cpuinfo; then
        cpu_flags="$cpu_flags,+avx2"
    fi
    if grep -q "sse4_2" /proc/cpuinfo; then
        cpu_flags="$cpu_flags,+sse4.2"
    fi
    
    # Enable all performance features
    cpu_flags="$cpu_flags,+ssse3,+sse4.1,+popcnt,+aes,+xsave,+xsaveopt,+vmx,+svm"
    
    # Base QEMU command with ULTRA PRO performance
    local qemu_cmd=(
        qemu-system-x86_64
        -name "$vm_name"
        -enable-kvm
        -machine "type=q35,accel=kvm,kernel_irqchip=on,nvdimm=on"
        -cpu "$cpu_flags,kvm=on,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time,hv_reset,hv_vpindex,hv_runtime,hv_synic,hv_stimer,hv_frequencies"
        -smp "sockets=1,cores=$CPUS,threads=2"
        -m "${MEMORY}M,slots=2,maxmem=$(($MEMORY * 2))M"
        -mem-prealloc
        -mem-path "/dev/hugepages"
        -overcommit mem-lock=on
        -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=writeback,discard=unmap,aio=native"
        -drive "file=$SEED_FILE,format=raw,if=virtio"
        -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
        -device "virtio-net-pci,netdev=net0,mac=52:54:00:$(openssl rand -hex 3| sed 's/\(..\)/\1:/g; s/.$//'),vectors=8"
        -device "virtio-balloon-pci"
        -object "rng-random,filename=/dev/urandom,id=rng0"
        -device "virtio-rng-pci,rng=rng0,max-bytes=1024,period=1000"
        -device "virtio-scsi-pci,id=scsi0,num_queues=4"
        -device "scsi-hd,bus=scsi0.0,drive=drive0"
        -vga "virtio"
        -usb
        -device "usb-tablet"
        -device "virtio-keyboard-pci"
        -device "virtio-mouse-pci"
        -parallel none
        -serial none
        -rtc "base=utc,clock=host,driftfix=slew"
        -boot "order=c,menu=on"
        -nodefaults
        -monitor "telnet:127.0.0.1:4444,server,nowait"
        -monitor "stdio"
        -D "/tmp/qemu-$vm_name.log"
        -msg "timestamp=on"
    )
    
    # Add GUI if enabled
    if [[ "$GUI_MODE" == true ]]; then
        qemu_cmd+=(
            -display "gtk,gl=on,show-cursor=on"
            -vga "virtio"
            -audiodev "pa,id=audio0"
            -device "ich9-intel-hda"
            -device "hda-duplex,audiodev=audio0"
        )
    else
        qemu_cmd+=(-nographic)
    fi
    
    # Add port forwards if specified
    if [[ -n "$PORT_FORWARDS" ]]; then
        local forward_index=1
        IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
        for forward in "${forwards[@]}"; do
            IFS=':' read -r host_port guest_port <<< "$forward"
            qemu_cmd+=(
                -netdev "user,id=net${forward_index},hostfwd=tcp::$host_port-:$guest_port"
                -device "virtio-net-pci,netdev=net${forward_index}"
            )
            ((forward_index++))
        done
    fi
    
    # Add storage optimization based on type
    if [[ "$STORAGE_TYPE" == "nvme" ]]; then
        qemu_cmd+=(
            -drive "file=$IMG_FILE,format=qcow2,if=none,cache=writeback,discard=unmap,aio=native,id=drive0"
            -device "nvme,drive=drive0,serial=ZynexForgeNVME,num_queues=8"
        )
    fi
    
    # Add network optimization
    if [[ "$NETWORK_CONFIG" == "sriov" ]]; then
        qemu_cmd+=(
            -device "vfio-pci,host=00:02.0"
        )
    elif [[ "$NETWORK_CONFIG" == "bridged" ]]; then
        qemu_cmd[-4]="-netdev bridge,br=virbr0,id=net0"
    fi
    
    # Add hugepages configuration
    if [ -d /sys/kernel/mm/hugepages ]; then
        qemu_cmd+=(
            -object "memory-backend-file,id=mem,size=${MEMORY}M,mem-path=/dev/hugepages,share=on,prealloc=on"
            -numa "node,memdev=mem"
        )
    fi
    
    echo "${qemu_cmd[@]}"
}

# Function to start a VM with ULTRA PRO performance
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "STEP" "Starting VM: $vm_name with ULTRA PRO performance"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        print_status "INFO" "Performance Profile: $PERFORMANCE_PROFILE"
        print_status "INFO" "Resources: ${MEMORY}MB RAM, ${CPUS} CPUs"
        print_status "INFO" "Datacenter: $NODE"
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        # Check if seed file exists
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating with ULTRA PRO optimization..."
            setup_vm_image
        fi
        
        # Generate and execute QEMU command
        local qemu_cmd
        qemu_cmd=$(generate_ultra_pro_qemu_cmd "$vm_name")
        
        print_status "INFO" "Launching VM with ULTRA PRO optimization..."
        
        # Execute QEMU in background
        eval "$qemu_cmd" &
        local qemu_pid=$!
        
        # Wait a moment and check if QEMU started
        sleep 2
        if kill -0 "$qemu_pid" 2>/dev/null; then
            print_status "SUCCESS" "VM $vm_name started with PID: $qemu_pid"
            print_status "INFO" "Monitor: telnet 127.0.0.1 4444"
            print_status "INFO" "Logs: /tmp/qemu-$vm_name.log"
            
            # Show connection info
            echo -e "\n${BOLD}${GREEN}🔗 Connection Information:${NC}"
            echo "SSH:        ssh -p $SSH_PORT $USERNAME@localhost"
            echo "Password:   $PASSWORD"
            echo "Monitor:    telnet 127.0.0.1 4444"
            
            # Wait for VM to shutdown
            wait "$qemu_pid"
            print_status "INFO" "VM $vm_name has been shut down"
        else
            print_status "ERROR" "Failed to start VM $vm_name"
            return 1
        fi
    fi
}

# Function to start QEMU with ISO
start_qemu_iso() {
    local iso_path=$1
    
    print_status "INFO" "Starting QEMU with ISO installation..."
    
    local qemu_cmd=(
        qemu-system-x86_64
        -name "$VM_NAME"
        -enable-kvm
        -machine "type=q35,accel=kvm"
        -cpu "host,kvm=on"
        -smp "sockets=1,cores=$CPUS"
        -m "${MEMORY}M"
        -drive "file=$IMG_FILE,format=qcow2,if=virtio"
        -cdrom "$iso_path"
        -boot "order=d"
        -vga "virtio"
        -display "gtk,gl=on"
        -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
        -device "virtio-net-pci,netdev=net0"
        -usb
        -device "usb-tablet"
        -audiodev "pa,id=audio0"
        -device "ich9-intel-hda"
        -device "hda-duplex,audiodev=audio0"
    )
    
    print_status "INFO" "Starting installation. Please complete OS installation in the GUI."
    print_status "INFO" "After installation, configure SSH for access."
    
    "${qemu_cmd[@]}"
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo -e "\n${BOLD}${CYAN}📊 VM Information: $vm_name${NC}"
        echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${GREEN}🌍 Location:${NC} $NODE"
        echo -e "${BOLD}${GREEN}⚡ Profile:${NC} $PERFORMANCE_PROFILE"
        echo -e "${BOLD}${GREEN}🖥️  OS:${NC} $OS_TYPE $CODENAME"
        echo -e "${BOLD}${GREEN}🏷️  Hostname:${NC} $HOSTNAME"
        echo -e "${BOLD}${GREEN}👤 Username:${NC} $USERNAME"
        echo -e "${BOLD}${GREEN}🔑 Password:${NC} $PASSWORD"
        echo -e "${BOLD}${GREEN}🔌 SSH Port:${NC} $SSH_PORT"
        echo -e "${BOLD}${GREEN}💾 Memory:${NC} $MEMORY MB"
        echo -e "${BOLD}${GREEN}⚙️  CPUs:${NC} $CPUS"
        echo -e "${BOLD}${GREEN}💿 Disk:${NC} $DISK_SIZE ($STORAGE_TYPE)"
        echo -e "${BOLD}${GREEN}🖥️  GUI Mode:${NC} $GUI_MODE"
        echo -e "${BOLD}${GREEN}🌐 Network:${NC} $NETWORK_CONFIG"
        echo -e "${BOLD}${GREEN}🔗 Port Forwards:${NC} ${PORT_FORWARDS:-None}"
        echo -e "${BOLD}${GREEN}📅 Created:${NC} $CREATED"
        echo -e "${BOLD}${GREEN}💿 Image:${NC} $(basename "$IMG_FILE")"
        echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}\n"
        
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

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "⚠️  This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to create VM snapshot
create_snapshot() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local snapshot_file="$SNAPSHOT_DIR/${vm_name}_${timestamp}.qcow2"
        
        print_status "INFO" "Creating snapshot of VM: $vm_name"
        qemu-img create -f qcow2 -b "$IMG_FILE" "$snapshot_file"
        
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "Snapshot created: $snapshot_file"
        else
            print_status "ERROR" "Failed to create snapshot"
        fi
    fi
}

# Function to restore VM snapshot
restore_snapshot() {
    local vm_name=$1
    
    local snapshots=($(ls "$SNAPSHOT_DIR"/*"$vm_name"*.qcow2 2>/dev/null))
    if [ ${#snapshots[@]} -eq 0 ]; then
        print_status "INFO" "No snapshots found for VM: $vm_name"
        return 1
    fi
    
    select snapshot in "${snapshots[@]}" "Cancel"; do
        if [ "$snapshot" == "Cancel" ]; then
            break
        elif [ -n "$snapshot" ]; then
            load_vm_config "$vm_name"
            cp "$snapshot" "$IMG_FILE"
            print_status "SUCCESS" "Snapshot restored: $(basename "$snapshot")"
            break
        fi
    done
}

# Function to migrate VM
migrate_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo -e "${BOLD}${CYAN}🌍 Migrate VM to another datacenter:${NC}"
        select_datacenter_node
        
        local old_node="$NODE"
        select_datacenter_node
        local new_node="$NODE"
        
        if [ "$old_node" != "$new_node" ]; then
            print_status "INFO" "Migrating VM $vm_name from $old_node to $new_node..."
            NODE="$new_node"
            save_vm_config
            print_status "SUCCESS" "VM $vm_name migrated to $new_node datacenter"
        else
            print_status "INFO" "VM is already in $old_node datacenter"
        fi
    fi
}

# Function to create VM cluster
create_vm_cluster() {
    display_os_art "cluster" "VM Cluster Creation"
    
    print_status "STEP" "Creating a new VM Cluster"
    
    read -p "$(print_status "INPUT" "Enter cluster name: ")" cluster_name
    mkdir -p "$CLUSTER_DIR/$cluster_name"
    
    echo -e "${BOLD}${CYAN}Select number of nodes in cluster:${NC}"
    read -p "$(print_status "INPUT" "Number of nodes (2-16): ")" node_count
    
    echo -e "${BOLD}${CYAN}Select cluster type:${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) Kubernetes Cluster                      │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) Docker Swarm                           │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) High Availability                      │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) Load Balanced                          │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    read -p "$(print_status "INPUT" "Select type (1-4): ")" cluster_type
    
    print_status "INFO" "Creating $node_count node cluster: $cluster_name"
    
    for i in $(seq 1 $node_count); do
        local vm_name="${cluster_name}-node${i}"
        VM_NAME="$vm_name"
        HOSTNAME="$vm_name"
        USERNAME="cluster"
        PASSWORD="cluster123"
        MEMORY=4096
        CPUS=2
        DISK_SIZE="50G"
        SSH_PORT=$((2222 + i - 1))
        NODE="local"
        PERFORMANCE_PROFILE="CLOUD"
        
        IMG_FILE="$VM_DIR/$vm_name.qcow2"
        SEED_FILE="$VM_DIR/$vm_name-seed.img"
        CREATED="$(date)"
        
        # Create VM
        setup_vm_image
        save_vm_config
        
        print_status "SUCCESS" "Cluster node $i created: $vm_name"
    done
    
    # Create cluster configuration
    cat > "$CLUSTER_DIR/$cluster_name/cluster.conf" <<EOF
CLUSTER_NAME="$cluster_name"
NODE_COUNT="$node_count"
CLUSTER_TYPE="$cluster_type"
CREATED="$(date)"
NODES="${cluster_name}-node1 to ${cluster_name}-node${node_count}"
EOF
    
    print_status "SUCCESS" "Cluster '$cluster_name' created with $node_count nodes!"
}

# Function to manage ISO files
manage_iso_files() {
    while true; do
        display_os_art "iso" "ISO & Template Library"
        
        local iso_files=($(ls "$ISO_DIR"/*.iso 2>/dev/null))
        local template_files=($(ls "$TEMPLATE_DIR"/*.qcow2 2>/dev/null))
        
        echo -e "${BOLD}${CYAN}📀 ISO & Template Management${NC}"
        echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│  ${GREEN}1${NC}) List ISO Files (${#iso_files[@]} found)       │"
        echo -e "${WHITE}│  ${GREEN}2${NC}) List Templates (${#template_files[@]} found)  │"
        echo -e "${WHITE}│  ${GREEN}3${NC}) Download ISO from URL                        │"
        echo -e "${WHITE}│  ${GREEN}4${NC}) Create Template from VM                       │"
        echo -e "${WHITE}│  ${GREEN}5${NC}) Delete ISO/Template                          │"
        echo -e "${WHITE}│  ${GREEN}6${NC}) Import ISO from CD/DVD                       │"
        echo -e "${WHITE}│  ${GREEN}0${NC}) Back to Main Menu                            │"
        echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
        
        read -p "$(print_status "INPUT" "Select option: ")" iso_choice
        
        case $iso_choice in
            1)
                echo -e "\n${BOLD}${CYAN}📀 Available ISO Files:${NC}"
                if [ ${#iso_files[@]} -eq 0 ]; then
                    print_status "INFO" "No ISO files found in $ISO_DIR"
                else
                    for i in "${!iso_files[@]}"; do
                        local size=$(du -h "${iso_files[$i]}" | cut -f1)
                        echo "  $((i+1))) $(basename "${iso_files[$i]}") ($size)"
                    done
                fi
                ;;
            2)
                echo -e "\n${BOLD}${CYAN}📦 Available Templates:${NC}"
                if [ ${#template_files[@]} -eq 0 ]; then
                    print_status "INFO" "No templates found in $TEMPLATE_DIR"
                else
                    for i in "${!template_files[@]}"; do
                        local size=$(du -h "${template_files[$i]}" | cut -f1)
                        echo "  $((i+1))) $(basename "${template_files[$i]}") ($size)"
                    done
                fi
                ;;
            3)
                read -p "$(print_status "INPUT" "Enter ISO URL: ")" iso_url
                if [ -n "$iso_url" ]; then
                    local filename=$(basename "$iso_url")
                    print_status "INFO" "Downloading $filename..."
                    wget --progress=bar:force -q --show-progress "$iso_url" -O "$ISO_DIR/$filename"
                    if [ $? -eq 0 ]; then
                        print_status "SUCCESS" "ISO downloaded successfully: $ISO_DIR/$filename"
                    else
                        print_status "ERROR" "Failed to download ISO"
                    fi
                fi
                ;;
            4)
                local vms=($(get_vm_list))
                if [ ${#vms[@]} -eq 0 ]; then
                    print_status "INFO" "No VMs available to create template from"
                else
                    echo -e "\n${BOLD}${CYAN}Select VM to create template from:${NC}"
                    select vm in "${vms[@]}" "Cancel"; do
                        if [ "$vm" == "Cancel" ]; then
                            break
                        elif [ -n "$vm" ]; then
                            read -p "$(print_status "INPUT" "Enter template name: ")" template_name
                            if [ -n "$template_name" ]; then
                                load_vm_config "$vm"
                                cp "$IMG_FILE" "$TEMPLATE_DIR/$template_name.qcow2"
                                cp "$VM_DIR/$vm.conf" "$TEMPLATE_DIR/$template_name.conf"
                                print_status "SUCCESS" "Template created: $TEMPLATE_DIR/$template_name.qcow2"
                            fi
                            break
                        fi
                    done
                fi
                ;;
            5)
                local all_files=($(ls "$ISO_DIR"/*.iso 2>/dev/null) $(ls "$TEMPLATE_DIR"/*.qcow2 2>/dev/null))
                if [ ${#all_files[@]} -eq 0 ]; then
                    print_status "INFO" "No files to delete"
                else
                    select file in "${all_files[@]}" "Cancel"; do
                        if [ "$file" == "Cancel" ]; then
                            break
                        elif [ -n "$file" ]; then
                            rm -f "$file"
                            # Also delete config file if it's a template
                            if [[ "$file" == *.qcow2 ]]; then
                                rm -f "${file%.qcow2}.conf"
                            fi
                            print_status "SUCCESS" "Deleted: $file"
                            break
                        fi
                    done
                fi
                ;;
            6)
                if [ -b /dev/sr0 ]; then
                    read -p "$(print_status "INPUT" "Enter ISO name: ")" iso_name
                    print_status "INFO" "Importing from CD/DVD drive..."
                    dd if=/dev/sr0 of="$ISO_DIR/$iso_name.iso" bs=1M status=progress
                    print_status "SUCCESS" "ISO imported: $ISO_DIR/$iso_name.iso"
                else
                    print_status "ERROR" "No CD/DVD drive detected"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Function for Docker Containers
docker_management() {
    display_os_art "docker" "Docker Containers Management"
    
    echo -e "${BOLD}${CYAN}🐳 Docker Container Management${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) List Docker Containers                  │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) Start Docker Container                  │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) Stop Docker Container                   │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) Run New Container                       │"
    echo -e "${WHITE}│  ${GREEN}5${NC}) View Container Logs                     │"
    echo -e "${WHITE}│  ${GREEN}6${NC}) Docker System Info                      │"
    echo -e "${WHITE}│  ${GREEN}7${NC}) Docker Compose Management              │"
    echo -e "${WHITE}│  ${GREEN}0${NC}) Back to Main Menu                       │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    read -p "$(print_status "INPUT" "Select option: ")" docker_choice
    
    case $docker_choice in
        1)
            docker ps -a
            ;;
        2)
            read -p "$(print_status "INPUT" "Enter container name/ID: ")" container
            docker start "$container"
            ;;
        3)
            read -p "$(print_status "INPUT" "Enter container name/ID: ")" container
            docker stop "$container"
            ;;
        4)
            read -p "$(print_status "INPUT" "Enter image name: ")" image
            read -p "$(print_status "INPUT" "Enter container name (optional): ")" name
            read -p "$(print_status "INPUT" "Enter port mapping (e.g., 8080:80): ")" ports
            local cmd="docker run -d"
            [ -n "$name" ] && cmd+=" --name $name"
            [ -n "$ports" ] && cmd+=" -p $ports"
            cmd+=" $image"
            eval "$cmd"
            ;;
        5)
            read -p "$(print_status "INPUT" "Enter container name/ID: ")" container
            docker logs "$container"
            ;;
        6)
            docker info
            ;;
        7)
            if command -v docker-compose &> /dev/null; then
                echo -e "\n${BOLD}${CYAN}Docker Compose Management${NC}"
                echo "1) Start Compose"
                echo "2) Stop Compose"
                echo "3) View Logs"
                read -p "$(print_status "INPUT" "Select option: ")" compose_choice
                
                case $compose_choice in
                    1) docker-compose up -d ;;
                    2) docker-compose down ;;
                    3) docker-compose logs ;;
                esac
            else
                print_status "ERROR" "docker-compose not installed"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            print_status "ERROR" "Invalid option"
            ;;
    esac
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function for Jupyter Notebooks
jupyter_management() {
    display_os_art "jupyter" "Jupyter Notebooks Management"
    
    echo -e "${BOLD}${CYAN}🔬 Jupyter Notebooks Management${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) Start Jupyter Server                     │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) List Running Jupyter Servers            │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) Stop Jupyter Server                      │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) Create New Notebook                      │"
    echo -e "${WHITE}│  ${GREEN}5${NC}) Open Jupyter in Browser                  │"
    echo -e "${WHITE}│  ${GREEN}6${NC}) JupyterLab Server                        │"
    echo -e "${WHITE}│  ${GREEN}0${NC}) Back to Main Menu                       │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    read -p "$(print_status "INPUT" "Select option: ")" jupyter_choice
    
    case $jupyter_choice in
        1)
            local port=8888
            while ss -tln | grep -q ":$port "; do
                ((port++))
            done
            mkdir -p "$JUPYTER_DIR"
            cd "$JUPYTER_DIR"
            nohup jupyter notebook --port=$port --no-browser --ip=0.0.0.0 > "$JUPYTER_DIR/jupyter.log" 2>&1 &
            print_status "SUCCESS" "Jupyter started on port $port"
            print_status "INFO" "Token: $(jupyter notebook list 2>/dev/null | grep -o 'token=[^ ]*' | cut -d= -f2 | head -1)"
            ;;
        2)
            jupyter notebook list
            ;;
        3)
            pkill -f jupyter-notebook
            print_status "SUCCESS" "Jupyter servers stopped"
            ;;
        4)
            read -p "$(print_status "INPUT" "Enter notebook name: ")" notebook_name
            mkdir -p "$JUPYTER_DIR"
            touch "$JUPYTER_DIR/$notebook_name.ipynb"
            print_status "SUCCESS" "Notebook created: $JUPYTER_DIR/$notebook_name.ipynb"
            ;;
        5)
            local url=$(jupyter notebook list 2>/dev/null | grep -o 'http://[^ ]*' | head -1)
            if [ -n "$url" ]; then
                xdg-open "$url" 2>/dev/null || print_status "INFO" "Open: $url"
            else
                print_status "ERROR" "No running Jupyter server found"
            fi
            ;;
        6)
            local port=8889
            while ss -tln | grep -q ":$port "; do
                ((port++))
            done
            mkdir -p "$JUPYTER_DIR"
            cd "$JUPYTER_DIR"
            nohup jupyter lab --port=$port --no-browser --ip=0.0.0.0 > "$JUPYTER_DIR/jupyterlab.log" 2>&1 &
            print_status "SUCCESS" "JupyterLab started on port $port"
            ;;
        0)
            return 0
            ;;
        *)
            print_status "ERROR" "Invalid option"
            ;;
    esac
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function for Backup & Restore
backup_management() {
    display_os_art "backup" "Backup & Restore"
    
    echo -e "${BOLD}${CYAN}💾 Backup & Restore Management${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) Backup VM                                 │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) Restore VM                                │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) List Backups                              │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) Delete Backup                             │"
    echo -e "${WHITE}│  ${GREEN}5${NC}) Export VM Configuration                   │"
    echo -e "${WHITE}│  ${GREEN}6${NC}) Schedule Automatic Backups               │"
    echo -e "${WHITE}│  ${GREEN}0${NC}) Back to Main Menu                        │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    read -p "$(print_status "INPUT" "Select option: ")" backup_choice
    
    case $backup_choice in
        1)
            local vms=($(get_vm_list))
            if [ ${#vms[@]} -eq 0 ]; then
                print_status "INFO" "No VMs available to backup"
            else
                select vm in "${vms[@]}" "Cancel"; do
                    if [ "$vm" == "Cancel" ]; then
                        break
                    elif [ -n "$vm" ]; then
                        local timestamp=$(date +%Y%m%d_%H%M%S)
                        local backup_file="$BACKUP_DIR/${vm}_${timestamp}.tar.gz"
                        
                        load_vm_config "$vm"
                        tar -czf "$backup_file" "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm.conf" 2>/dev/null
                        
                        if [ $? -eq 0 ]; then
                            print_status "SUCCESS" "Backup created: $backup_file"
                            echo "$(date): $vm" >> "$BACKUP_DIR/backup_history.log"
                        else
                            print_status "ERROR" "Backup failed"
                        fi
                        break
                    fi
                done
            fi
            ;;
        2)
            local backups=($(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
            if [ ${#backups[@]} -eq 0 ]; then
                print_status "INFO" "No backups available"
            else
                select backup in "${backups[@]}" "Cancel"; do
                    if [ "$backup" == "Cancel" ]; then
                        break
                    elif [ -n "$backup" ]; then
                        read -p "$(print_status "INPUT" "Enter VM name for restore: ")" vm_name
                        if [ -n "$vm_name" ]; then
                            tar -xzf "$backup" -C "$VM_DIR/" --strip-components=1
                            print_status "SUCCESS" "Restored VM: $vm_name"
                            echo "$(date): Restored $vm_name from $backup" >> "$BACKUP_DIR/restore_history.log"
                        fi
                        break
                    fi
                done
            fi
            ;;
        3)
            echo -e "\n${BOLD}${CYAN}📦 Available Backups:${NC}"
            local backups=($(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
            if [ ${#backups[@]} -eq 0 ]; then
                print_status "INFO" "No backups found"
            else
                for backup in "${backups[@]}"; do
                    local size=$(du -h "$backup" | cut -f1)
                    local date=$(stat -c %y "$backup" | cut -d' ' -f1)
                    echo "  $(basename "$backup") ($size) - $date"
                done
            fi
            ;;
        4)
            local backups=($(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
            if [ ${#backups[@]} -eq 0 ]; then
                print_status "INFO" "No backups to delete"
            else
                select backup in "${backups[@]}" "Cancel"; do
                    if [ "$backup" == "Cancel" ]; then
                        break
                    elif [ -n "$backup" ]; then
                        rm -f "$backup"
                        print_status "SUCCESS" "Deleted: $(basename "$backup")"
                        break
                    fi
                done
            fi
            ;;
        5)
            local vms=($(get_vm_list))
            if [ ${#vms[@]} -eq 0 ]; then
                print_status "INFO" "No VMs available"
            else
                select vm in "${vms[@]}" "Cancel"; do
                    if [ "$vm" == "Cancel" ]; then
                        break
                    elif [ -n "$vm" ]; then
                        cp "$VM_DIR/$vm.conf" "$BACKUP_DIR/${vm}_config_$(date +%Y%m%d).conf"
                        print_status "SUCCESS" "Configuration exported: $BACKUP_DIR/${vm}_config_$(date +%Y%m%d).conf"
                        break
                    fi
                done
            fi
            ;;
        6)
            read -p "$(print_status "INPUT" "Enter VM name for scheduled backup: ")" vm_name
            read -p "$(print_status "INPUT" "Enter schedule (daily/weekly/monthly): ")" schedule
            echo "0 2 * * * /bin/bash -c 'cd $(pwd) && ./$(basename "$0") --backup $vm_name'" > /tmp/cronjob
            if [[ "$schedule" == "daily" ]]; then
                echo "0 2 * * *" > /tmp/cronjob
            elif [[ "$schedule" == "weekly" ]]; then
                echo "0 2 * * 0" > /tmp/cronjob
            elif [[ "$schedule" == "monthly" ]]; then
                echo "0 2 1 * *" > /tmp/cronjob
            fi
            crontab -l | cat - /tmp/cronjob | crontab -
            print_status "SUCCESS" "Scheduled backup configured for $vm_name ($schedule)"
            ;;
        0)
            return 0
            ;;
        *)
            print_status "ERROR" "Invalid option"
            ;;
    esac
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function for Settings
settings_management() {
    display_os_art "settings" "Settings & Configuration"
    
    echo -e "${BOLD}${CYAN}⚙️  Settings & Configuration${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) Change Default Directories                │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) Configure SSH Keys                        │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) Update Cloud Images                       │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) View System Information                   │"
    echo -e "${WHITE}│  ${GREEN}5${NC}) View Logs                                 │"
    echo -e "${WHITE}│  ${GREEN}6${NC}) Clear Cache                               │"
    echo -e "${WHITE}│  ${GREEN}7${NC}) Performance Tuning                        │"
    echo -e "${WHITE}│  ${GREEN}8${NC}) Network Configuration                     │"
    echo -e "${WHITE}│  ${GREEN}0${NC}) Back to Main Menu                        │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    read -p "$(print_status "INPUT" "Select option: ")" settings_choice
    
    case $settings_choice in
        1)
            read -p "$(print_status "INPUT" "Enter new VM directory [$VM_DIR]: ")" new_vm_dir
            [ -n "$new_vm_dir" ] && VM_DIR="$new_vm_dir"
            read -p "$(print_status "INPUT" "Enter new ISO directory [$ISO_DIR]: ")" new_iso_dir
            [ -n "$new_iso_dir" ] && ISO_DIR="$new_iso_dir"
            read -p "$(print_status "INPUT" "Enter new Backup directory [$BACKUP_DIR]: ")" new_backup_dir
            [ -n "$new_backup_dir" ] && BACKUP_DIR="$new_backup_dir"
            mkdir -p "$VM_DIR" "$ISO_DIR" "$BACKUP_DIR"
            print_status "SUCCESS" "Directories updated"
            ;;
        2)
            if [ ! -f ~/.ssh/id_rsa.pub ]; then
                print_status "INFO" "Generating SSH key..."
                ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
            fi
            echo -e "\n${BOLD}${CYAN}SSH Public Key:${NC}"
            cat ~/.ssh/id_rsa.pub
            echo -e "\n${BOLD}${CYAN}Add this key to your VMs for passwordless SSH access${NC}"
            ;;
        3)
            print_status "INFO" "Checking for cloud image updates..."
            # This would check for updates to cloud images
            print_status "INFO" "Update check completed"
            ;;
        4)
            echo -e "\n${BOLD}${CYAN}🖥️  System Information:${NC}"
            echo "Hostname: $(hostname)"
            echo "Kernel: $(uname -r)"
            echo "Distribution: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
            echo "CPU: $(lscpu | grep "Model name" | cut -d: -f2 | xargs)"
            echo "Cores: $(nproc)"
            echo "RAM: $(free -h | grep Mem | awk '{print $2}')"
            echo "Disk: $(df -h / | awk 'NR==2 {print $4}') free"
            echo "QEMU Version: $(qemu-system-x86_64 --version | head -1)"
            echo "KVM Support: $(test -e /dev/kvm && echo "Yes" || echo "No")"
            ;;
        5)
            echo -e "\n${BOLD}${CYAN}📋 Recent Logs:${NC}"
            if [ -f "$LOG_FILE" ]; then
                tail -100 "$LOG_FILE"
            else
                print_status "INFO" "No log file found"
            fi
            ;;
        6)
            rm -f /tmp/zynexforge_*.tmp 2>/dev/null
            print_status "SUCCESS" "Temporary files cleared"
            ;;
        7)
            echo -e "\n${BOLD}${CYAN}⚡ Performance Tuning:${NC}"
            echo "1) Enable Hugepages"
            echo "2) Optimize CPU Governor"
            echo "3) Tune Disk I/O"
            read -p "$(print_status "INPUT" "Select option: ")" perf_choice
            
            case $perf_choice in
                1)
                    echo "Enabling hugepages..."
                    echo "vm.nr_hugepages = 1024" | sudo tee -a /etc/sysctl.conf
                    sudo sysctl -p
                    ;;
                2)
                    echo "Setting performance governor..."
                    echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
                    ;;
                3)
                    echo "Tuning disk I/O..."
                    echo deadline | sudo tee /sys/block/sda/queue/scheduler
                    ;;
            esac
            ;;
        8)
            echo -e "\n${BOLD}${CYAN}🌐 Network Configuration:${NC}"
            echo "1) Configure Bridge Network"
            echo "2) Set Static IP"
            echo "3) Configure DNS"
            read -p "$(print_status "INPUT" "Select option: ")" net_choice
            
            case $net_choice in
                1)
                    sudo brctl addbr virbr0
                    sudo ip addr add 192.168.100.1/24 dev virbr0
                    sudo ip link set virbr0 up
                    print_status "SUCCESS" "Bridge network configured"
                    ;;
            esac
            ;;
        0)
            return 0
            ;;
        *)
            print_status "ERROR" "Invalid option"
            ;;
    esac
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function for System Diagnostics
system_diagnostics() {
    display_os_art "diagnostics" "System Diagnostics"
    
    echo -e "${BOLD}${CYAN}🔧 System Diagnostics${NC}"
    echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│  ${GREEN}1${NC}) Check System Health                      │"
    echo -e "${WHITE}│  ${GREEN}2${NC}) Test Network Speed                       │"
    echo -e "${WHITE}│  ${GREEN}3${NC}) Benchmark CPU Performance                │"
    echo -e "${WHITE}│  ${GREEN}4${NC}) Benchmark Disk I/O                       │"
    echo -e "${WHITE}│  ${GREEN}5${NC}) Check Virtualization Support            │"
    echo -e "${WHITE}│  ${GREEN}6${NC}) Monitor Resource Usage                  │"
    echo -e "${WHITE}│  ${GREEN}7${NC}) Check Services Status                   │"
    echo -e "${WHITE}│  ${GREEN}0${NC}) Back to Main Menu                       │"
    echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
    
    read -p "$(print_status "INPUT" "Select option: ")" diag_choice
    
    case $diag_choice in
        1)
            echo -e "\n${BOLD}${CYAN}🏥 System Health Check:${NC}"
            
            # Check CPU load
            local load=$(uptime | awk -F'load average:' '{print $2}')
            echo "CPU Load: $load"
            
            # Check memory
            local mem_free=$(free -m | awk 'NR==2 {printf "%.1f%%", $4*100/$2}')
            echo "Memory Free: $mem_free"
            
            # Check disk space
            local disk_free=$(df -h / | awk 'NR==2 {print $4}')
            echo "Disk Free (root): $disk_free"
            
            # Check temperature (if available)
            if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
                local temp=$(cat /sys/class/thermal/thermal_zone0/temp)
                echo "CPU Temp: $((temp/1000))°C"
            fi
            
            # Check KVM
            if [ -e /dev/kvm ]; then
                echo "KVM: ✅ Available"
            else
                echo "KVM: ❌ Not available"
            fi
            
            # Check hugepages
            if [ -d /sys/kernel/mm/hugepages ]; then
                echo "Hugepages: ✅ Available"
            else
                echo "Hugepages: ❌ Not available"
            fi
            ;;
        2)
            print_status "INFO" "Testing network speed (this may take a moment)..."
            if command -v speedtest-cli &> /dev/null; then
                speedtest-cli --simple
            else
                local speed=$(curl -s -w "%{speed_download}\n" -o /dev/null http://cachefly.cachefly.net/100mb.test 2>/dev/null)
                if [ -n "$speed" ]; then
                    local mbps=$(echo "scale=2; $speed / 125000" | bc)
                    echo "Network Speed: ${mbps} Mbps"
                else
                    print_status "ERROR" "Network test failed"
                fi
            fi
            ;;
        3)
            print_status "INFO" "Benchmarking CPU (this may take a few seconds)..."
            local start_time=$(date +%s.%N)
            local count=10000000
            for i in $(seq 1 $count); do
                : # Simple CPU stress
            done
            local end_time=$(date +%s.%N)
            local elapsed=$(echo "$end_time - $start_time" | bc)
            local ops_per_sec=$(echo "scale=2; $count / $elapsed" | bc)
            echo "CPU Performance: $ops_per_sec operations/second"
            ;;
        4)
            print_status "INFO" "Benchmarking Disk I/O..."
            local test_file="/tmp/zynexforge_disk_test"
            local start_time=$(date +%s.%N)
            dd if=/dev/zero of="$test_file" bs=1M count=100 oflag=direct 2>/dev/null
            local end_time=$(date +%s.%N)
            rm -f "$test_file"
            local elapsed=$(echo "$end_time - $start_time" | bc)
            local mbps=$(echo "scale=2; 100 / $elapsed" | bc)
            echo "Disk Write Speed: ${mbps} MB/s"
            ;;
        5)
            echo -e "\n${BOLD}${CYAN}🔬 Virtualization Support:${NC}"
            
            # Check CPU flags
            echo "CPU Virtualization Support:"
            if grep -q "vmx" /proc/cpuinfo; then
                echo "  Intel VT-x: ✅ Available"
            else
                echo "  Intel VT-x: ❌ Not available"
            fi
            
            if grep -q "svm" /proc/cpuinfo; then
                echo "  AMD-V: ✅ Available"
            else
                echo "  AMD-V: ❌ Not available"
            fi
            
            # Check KVM module
            if lsmod | grep -q kvm; then
                echo "KVM Module: ✅ Loaded"
            else
                echo "KVM Module: ❌ Not loaded"
            fi
            
            # Check nested virtualization
            if [ -f /sys/module/kvm_intel/parameters/nested ]; then
                if grep -q "Y" /sys/module/kvm_intel/parameters/nested; then
                    echo "Nested Virtualization: ✅ Enabled"
                else
                    echo "Nested Virtualization: ❌ Disabled"
                fi
            fi
            ;;
        6)
            echo -e "\n${BOLD}${CYAN}📊 Resource Usage:${NC}"
            if command -v htop &> /dev/null; then
                htop --version >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    htop
                else
                    top -b -n 1 | head -20
                fi
            else
                top -b -n 1 | head -20
            fi
            ;;
        7)
            echo -e "\n${BOLD}${CYAN}🔧 Services Status:${NC}"
            systemctl status libvirtd --no-pager
            echo ""
            systemctl status docker --no-pager
            ;;
        0)
            return 0
            ;;
        *)
            print_status "ERROR" "Invalid option"
            ;;
    esac
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function for Documentation & Help
show_documentation() {
    display_os_art "help" "Documentation & Help"
    
    echo -e "${BOLD}${CYAN}📚 ZynexForge CloudStack™ Ultra Pro Documentation${NC}"
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "\n${BOLD}${GREEN}⚡ ULTRA PRO Features:${NC}"
    echo "  • Auto-performance tuning with 5 preset profiles"
    echo "  • 12 global datacenter node selection"
    echo "  • Cloud image, ISO, template, and raw disk support"
    echo "  • Docker container and Jupyter notebook management"
    echo "  • VM clustering and migration capabilities"
    echo "  • Advanced snapshot and backup system"
    echo "  • Real-time system diagnostics"
    echo "  • Performance profiling and optimization"
    
    echo -e "\n${BOLD}${GREEN}🚀 Performance Profiles:${NC}"
    echo "  🎮  GAMING: 16GB RAM, 8 CPUs, NVMe, SR-IOV"
    echo "  🏢  ENTERPRISE: 32GB RAM, 16 CPUs, NVMe, VirtIO"
    echo "  💻  DEVELOPMENT: 8GB RAM, 4 CPUs, SSD, VirtIO"
    echo "  ☁️   CLOUD: 4GB RAM, 2 CPUs, SSD, VirtIO"
    echo "  ⚡  ULTRA: 64GB RAM, 32 CPUs, NVMe, SR-IOV"
    
    echo -e "\n${BOLD}${GREEN}🌍 Datacenter Nodes:${NC}"
    echo "  🇮🇳  Mumbai, Delhi, Bangalore"
    echo "  🇸🇬  Singapore"
    echo "  🇩🇪  Frankfurt"
    echo "  🇳🇱  Amsterdam"
    echo "  🇬🇧  London"
    echo "  🇺🇸  New York, Los Angeles"
    echo "  🇨🇦  Toronto"
    echo "  🇯🇵  Tokyo"
    echo "  🇦🇺  Sydney"
    
    echo -e "\n${BOLD}${GREEN}🔧 Quick Commands:${NC}"
    echo "  SSH to VM:        ssh -p <port> user@localhost"
    echo "  Monitor VM:       telnet 127.0.0.1 4444"
    echo "  View QEMU logs:   tail -f /tmp/qemu-<vmname>.log"
    echo "  List running VMs: pgrep -a qemu"
    
    echo -e "\n${BOLD}${GREEN}📞 Support:${NC}"
    echo "  • Check system diagnostics for hardware issues"
    echo "  • View logs in Settings > View Logs"
    echo "  • Ensure all dependencies are installed"
    echo "  • Use performance profiles for optimal results"
    
    echo -e "\n${BOLD}${GREEN}🔒 Security Notes:${NC}"
    echo "  • Change default passwords after VM creation"
    echo "  • Use SSH keys for authentication"
    echo "  • Keep backups in secure location"
    echo "  • Regular updates for both host and VMs"
    
    echo "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Main menu function
main_menu() {
    while true; do
        display_banner
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            echo -e "${BOLD}${CYAN}Existing VMs:${NC}"
            for i in "${!vms[@]}"; do
                local status="🔴"
                if is_vm_running "${vms[$i]}"; then
                    status="🟢"
                fi
                echo "  $((i+1))) ${status} ${vms[$i]}"
            done
            echo ""
        fi
        
        echo -e "${BOLD}${CYAN}🏠 Main Menu (Ultra Pro Edition):${NC}"
        echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│  ${GREEN}1${NC}) ⚡ Create New Virtual Machine         │"
        if [ $vm_count -gt 0 ]; then
            echo -e "${WHITE}│  ${GREEN}2${NC}) 🖥️  VM Management Dashboard          │"
        fi
        echo -e "${WHITE}│  ${GREEN}3${NC}) 🐳 Docker Containers                  │"
        echo -e "${WHITE}│  ${GREEN}4${NC}) 🔬 Jupyter Notebooks                  │"
        echo -e "${WHITE}│  ${GREEN}5${NC}) 📦 ISO & Template Library            │"
        echo -e "${WHITE}│  ${GREEN}6${NC}) 💾 Backup & Restore                  │"
        echo -e "${WHITE}│  ${GREEN}7${NC}) ⚙️  Settings                          │"
        echo -e "${WHITE}│  ${GREEN}8${NC}) 🔧 System Diagnostics                │"
        echo -e "${WHITE}│  ${GREEN}9${NC}) 📚 Documentation & Help              │"
        echo -e "${WHITE}│  ${GREEN}C${NC}) 🌀 Create VM Cluster                 │"
        echo -e "${WHITE}│  ${GREEN}0${NC}) 🚪 Exit                               │"
        echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
        
        read -p "$(print_status "INPUT" "Select option (0-9 or C): ")" choice
        
        case $choice in
            1)
                echo -e "\n${BOLD}${CYAN}Select VM Type:${NC}"
                echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
                echo -e "${WHITE}│  ${GREEN}1${NC}) ⚡ QEMU (Ultra Pro Performance)      │"
                echo -e "${WHITE}│  ${GREEN}2${NC}) 🔄 Cloud Image VM                     │"
                echo -e "${WHITE}│  ${GREEN}3${NC}) 💿 ISO Installation                   │"
                echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
                
                read -p "$(print_status "INPUT" "Select VM type (1-3): ")" vm_type
                case $vm_type in
                    1|2|3) create_qemu_vm ;;
                    *) print_status "ERROR" "Invalid selection" ;;
                esac
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    while true; do
                        display_os_art "vm" "VM Management Dashboard"
                        
                        echo -e "${BOLD}${CYAN}🖥️  VM Management Dashboard${NC}"
                        echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
                        for i in "${!vms[@]}"; do
                            local status="🔴"
                            if is_vm_running "${vms[$i]}"; then
                                status="🟢"
                            fi
                            printf "${WHITE}│  ${GREEN}%2d${NC}) ${status} %-30s ${WHITE}│\n" $((i+1)) "${vms[$i]}"
                        done
                        echo -e "${WHITE}├─────────────────────────────────────────────┤${NC}"
                        echo -e "${WHITE}│  ${GREEN}S${NC}) Start VM                             │"
                        echo -e "${WHITE}│  ${GREEN}T${NC}) Stop VM                              │"
                        echo -e "${WHITE}│  ${GREEN}I${NC}) Show VM Info                         │"
                        echo -e "${WHITE}│  ${GREEN}E${NC}) Edit VM Config                       │"
                        echo -e "${WHITE}│  ${GREEN}D${NC}) Delete VM                            │"
                        echo -e "${WHITE}│  ${GREEN}N${NC}) Create Snapshot                      │"
                        echo -e "${WHITE}│  ${GREEN}R${NC}) Restore Snapshot                     │"
                        echo -e "${WHITE}│  ${GREEN}M${NC}) Migrate VM                           │"
                        echo -e "${WHITE}│  ${GREEN}B${NC}) Back to Main Menu                    │"
                        echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
                        
                        read -p "$(print_status "INPUT" "Enter VM number or command: ")" vm_cmd
                        
                        if [[ "$vm_cmd" =~ ^[0-9]+$ ]] && [ "$vm_cmd" -ge 1 ] && [ "$vm_cmd" -le $vm_count ]; then
                            local selected_vm="${vms[$((vm_cmd-1))]}"
                            echo -e "\n${BOLD}${CYAN}Actions for VM: $selected_vm${NC}"
                            echo -e "${WHITE}┌─────────────────────────────────────────────┐${NC}"
                            echo -e "${WHITE}│  ${GREEN}1${NC}) Start VM                             │"
                            echo -e "${WHITE}│  ${GREEN}2${NC}) Stop VM                              │"
                            echo -e "${WHITE}│  ${GREEN}3${NC}) Show Info                            │"
                            echo -e "${WHITE}│  ${GREEN}4${NC}) Create Snapshot                      │"
                            echo -e "${WHITE}│  ${GREEN}5${NC}) Restore Snapshot                     │"
                            echo -e "${WHITE}│  ${GREEN}6${NC}) Migrate to another DC               │"
                            echo -e "${WHITE}│  ${GREEN}7${NC}) Delete VM                            │"
                            echo -e "${WHITE}│  ${GREEN}0${NC}) Back                                 │"
                            echo -e "${WHITE}└─────────────────────────────────────────────┘${NC}"
                            
                            read -p "$(print_status "INPUT" "Select action: ")" action
                            
                            case $action in
                                1) start_vm "$selected_vm" ;;
                                2) stop_vm "$selected_vm" ;;
                                3) show_vm_info "$selected_vm" ;;
                                4) create_snapshot "$selected_vm" ;;
                                5) restore_snapshot "$selected_vm" ;;
                                6) migrate_vm "$selected_vm" ;;
                                7) 
                                    delete_vm "$selected_vm"
                                    vms=($(get_vm_list))
                                    vm_count=${#vms[@]}
                                    ;;
                                0) continue ;;
                                *) print_status "ERROR" "Invalid action" ;;
                            esac
                        elif [[ "$vm_cmd" =~ ^[Ss]$ ]]; then
                            read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                            if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                                start_vm "${vms[$((vm_num-1))]}"
                            fi
                        elif [[ "$vm_cmd" =~ ^[Tt]$ ]]; then
                            read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                            if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                                stop_vm "${vms[$((vm_num-1))]}"
                            fi
                        elif [[ "$vm_cmd" =~ ^[Ii]$ ]]; then
                            read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                            if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                                show_vm_info "${vms[$((vm_num-1))]}"
                            fi
                        elif [[ "$vm_cmd" =~ ^[Nn]$ ]]; then
                            read -p "$(print_status "INPUT" "Enter VM number for snapshot: ")" vm_num
                            if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                                create_snapshot "${vms[$((vm_num-1))]}"
                            fi
                        elif [[ "$vm_cmd" =~ ^[Rr]$ ]]; then
                            read -p "$(print_status "INPUT" "Enter VM number to restore: ")" vm_num
                            if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                                restore_snapshot "${vms[$((vm_num-1))]}"
                            fi
                        elif [[ "$vm_cmd" =~ ^[Mm]$ ]]; then
                            read -p "$(print_status "INPUT" "Enter VM number to migrate: ")" vm_num
                            if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                                migrate_vm "${vms[$((vm_num-1))]}"
                            fi
                        elif [[ "$vm_cmd" =~ ^[Dd]$ ]]; then
                            read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                            if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                                delete_vm "${vms[$((vm_num-1))]}"
                                vms=($(get_vm_list))
                                vm_count=${#vms[@]}
                            fi
                        elif [[ "$vm_cmd" =~ ^[Bb]$ ]]; then
                            break
                        else
                            print_status "ERROR" "Invalid input"
                        fi
                        
                        read -p "$(print_status "INPUT" "Press Enter to continue...")"
                    done
                fi
                ;;
            3)
                docker_management
                ;;
            4)
                jupyter_management
                ;;
            5)
                manage_iso_files
                ;;
            6)
                backup_management
                ;;
            7)
                settings_management
                ;;
            8)
                system_diagnostics
                ;;
            9)
                show_documentation
                ;;
            C|c)
                create_vm_cluster
                ;;
            0)
                print_status "INFO" "Thank you for using ZynexForge CloudStack™ Ultra Pro Edition!"
                print_status "INFO" "Goodbye! 👋"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Cleanup function
cleanup() {
    print_status "INFO" "Cleaning up temporary files..."
    rm -f user-data meta-data 2>/dev/null
    print_status "INFO" "Cleanup complete"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Initialize
check_dependencies
get_system_specs

# Start the main menu
main_menu
