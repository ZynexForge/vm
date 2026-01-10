#!/bin/bash
set -euo pipefail

# =============================================================================
# ZynexForge CloudStack™ Platform - Ultimate Edition
# Non-Root Edition with Enhanced Features
# Version: 2.0.0
# Made by FaaizXD
# =============================================================================

# Global Configuration
readonly USER_HOME="$HOME"
readonly CONFIG_DIR="$USER_HOME/.zynexforge"
readonly DATA_DIR="$USER_HOME/.zynexforge/data"
readonly LOG_FILE="$USER_HOME/.zynexforge/zynexforge.log"
readonly NODES_DB="$CONFIG_DIR/nodes.yml"
readonly GLOBAL_CONFIG="$CONFIG_DIR/config.yml"
readonly SSH_KEY_FILE="$USER_HOME/.ssh/zynexforge_ed25519"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="ZynexForge CloudStack™ Ultimate Edition"

# Color Definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# ASCII Art Definitions
readonly ASCII_MAIN_ART=$(cat << 'EOF'
__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
EOF
)

readonly OS_ASCII_ART=$(cat << 'EOF'
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
EOF
)

# Supported OS Templates
declare -A OS_TEMPLATES=(
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu123"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu123"
    ["debian-12"]="Debian 12|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian123"
    ["debian-11"]="Debian 11|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian123"
    ["almalinux-9"]="AlmaLinux 9|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma123"
    ["rocky-9"]="Rocky Linux 9|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky123"
    ["centos-9"]="CentOS Stream 9|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos123"
    ["fedora-40"]="Fedora 40|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora123"
    ["alpine-latest"]="Alpine Linux|edge|https://dl-cdn.alpinelinux.org/alpine/edge/releases/x86_64/alpine-virt-3.20.0-x86_64.iso|alpine|alpine|alpine123"
)

# Region Presets
declare -A REGIONS=(
    [1]="🇮🇳 Mumbai, India|ap-south-1"
    [2]="🇮🇳 Delhi NCR, India|ap-south-2"
    [3]="🇮🇳 Bangalore, India|ap-south-1"
    [4]="🇸🇬 Singapore|ap-southeast-1"
    [5]="🇩🇪 Frankfurt, Germany|eu-central-1"
    [6]="🇳🇱 Amsterdam, Netherlands|eu-west-1"
    [7]="🇬🇧 London, UK|eu-west-2"
    [8]="🇺🇸 New York, USA|us-east-1"
    [9]="🇺🇸 Los Angeles, USA|us-west-2"
    [10]="🇨🇦 Toronto, Canada|ca-central-1"
    [11]="🇯🇵 Tokyo, Japan|ap-northeast-1"
    [12]="🇦🇺 Sydney, Australia|ap-southeast-2"
)

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE" > /dev/null 2>&1
}

log_command() {
    local cmd="$*"
    log "Executing: $cmd"
    eval "$cmd"
    local status=$?
    if [ $status -ne 0 ]; then
        log "Command failed with status: $status"
    fi
    return $status
}

# =============================================================================
# PRINT FUNCTIONS
# =============================================================================

print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "SUCCESS") echo -e "${GREEN}✅ ${message}${NC}" ;;
        "ERROR") echo -e "${RED}❌ ${message}${NC}" ;;
        "WARNING") echo -e "${YELLOW}⚠️  ${message}${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ️  ${message}${NC}" ;;
        "HEADER") echo -e "${CYAN}${BOLD}${message}${NC}" ;;
        "DEBUG") echo -e "${DIM}🔧 ${message}${NC}" ;;
        "INPUT") echo -e "${MAGENTA}💡 ${message}${NC}" ;;
        *) echo -e "${message}" ;;
    esac
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "$ASCII_MAIN_ART"
    echo -e "${NC}"
    echo -e "${YELLOW}${BOLD}⚡ ${SCRIPT_NAME}${NC}"
    echo -e "${WHITE}${DIM}🔥 Made by FaaizXD | Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${DIM}$(printf '=%.0s' {1..60})${NC}"
    
    # System capabilities summary
    print_status "INFO" "System Capabilities:"
    
    # Check KVM access
    if [ -r "/dev/kvm" ] && groups | grep -q -E "(kvm|libvirt)"; then
        echo -e "  ${GREEN}✓${NC} KVM: Available (Hardware Acceleration)"
    else
        echo -e "  ${YELLOW}⚠${NC} KVM: Not Available (Software Emulation)"
    fi
    
    # Check Docker access
    if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Docker: Available"
    else
        echo -e "  ${YELLOW}⚠${NC} Docker: Not Available"
    fi
    
    # Check QEMU
    if command -v qemu-system-x86_64 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} QEMU: Available"
    else
        echo -e "  ${RED}✗${NC} QEMU: Not Available"
    fi
    
    # Check LXD
    if command -v lxc > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} LXD: Available"
    else
        echo -e "  ${YELLOW}⚠${NC} LXD: Not Installed"
    fi
    
    local vm_count=0
    local docker_count=0
    local jupyter_count=0
    
    if [ -d "$DATA_DIR/vms" ]; then
        vm_count=$(find "$DATA_DIR/vms" -name "*.conf" -type f 2>/dev/null | wc -l)
    fi
    
    if [ -d "$DATA_DIR/dockervm" ]; then
        docker_count=$(find "$DATA_DIR/dockervm" -name "*.conf" -type f 2>/dev/null | wc -l)
    fi
    
    if [ -d "$DATA_DIR/jupyter" ]; then
        jupyter_count=$(find "$DATA_DIR/jupyter" -name "*.conf" -type f 2>/dev/null | wc -l)
    fi
    
    echo -e "  ${CYAN}📊${NC} Active VMs: ${WHITE}${vm_count}${NC}"
    echo -e "  ${CYAN}🐳${NC} Docker VMs: ${WHITE}${docker_count}${NC}"
    echo -e "  ${CYAN}🔬${NC} Jupyter Labs: ${WHITE}${jupyter_count}${NC}"
    echo -e "${DIM}$(printf '=%.0s' {1..60})${NC}"
    echo
}

print_centered() {
    local text="$1"
    local width=60
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s" ''
    echo -e "${text}"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_input() {
    local type="$1"
    local value="$2"
    
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
        "email")
            if ! [[ "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                print_status "ERROR" "Must be a valid email address"
                return 1
            fi
            ;;
        "ip")
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid IP address"
                return 1
            fi
            ;;
        "domain")
            if ! [[ "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
                print_status "ERROR" "Must be a valid domain name"
                return 1
            fi
            ;;
    esac
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

check_dependencies() {
    print_status "INFO" "Checking dependencies..."
    
    local missing_packages=()
    local required_tools=("qemu-system-x86_64" "qemu-img" "ssh-keygen")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" > /dev/null 2>&1; then
            missing_packages+=("$tool")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_status "WARNING" "Missing packages: ${missing_packages[*]}"
        
        if command -v apt-get > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Debian/Ubuntu..."
            sudo apt-get update && sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils genisoimage openssh-client curl wget
        elif command -v dnf > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Fedora/RHEL..."
            sudo dnf install -y qemu-system-x86 qemu-img cloud-utils genisoimage openssh-clients curl wget
        elif command -v yum > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on CentOS..."
            sudo yum install -y qemu-kvm qemu-img cloud-utils genisoimage openssh-clients curl wget
        elif command -v pacman > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Arch..."
            sudo pacman -S --noconfirm qemu qemu-arch-extra cloud-init cdrtools openssh curl wget
        else
            print_status "ERROR" "Unsupported package manager"
            print_status "INFO" "Please install manually: qemu-system-x86, qemu-utils, cloud-image-utils, genisoimage, curl, wget"
        fi
    else
        print_status "SUCCESS" "All required tools are available"
    fi
}

check_port_available() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        if ss -tuln | grep -q ":${port} "; then
            return 1
        fi
    elif command -v netstat > /dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then
            return 1
        fi
    fi
    return 0
}

find_available_port() {
    local base_port="${1:-22000}"
    local max_port=23000
    local port="$base_port"
    
    while [ "$port" -le "$max_port" ]; do
        if check_port_available "$port"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    
    # If no port found, use a random one above 30000
    echo $((RANDOM % 10000 + 30000))
}

generate_password() {
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c "$length"
}

get_system_info() {
    echo -e "${CYAN}${BOLD}System Information:${NC}"
    echo -e "${DIM}$(printf '―%.0s' {1..40})${NC}"
    echo -e "Hostname: $(hostname)"
    echo -e "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo -e "Kernel: $(uname -r)"
    echo -e "Architecture: $(uname -m)"
    echo -e "CPU: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')"
    echo -e "CPU Cores: $(nproc)"
    echo -e "Memory: $(free -h | awk '/^Mem:/ {print $2}') Total, $(free -h | awk '/^Mem:/ {print $4}') Free"
    echo -e "Disk: $(df -h / | awk 'NR==2 {print $2}') Total, $(df -h / | awk 'NR==2 {print $4}') Free"
}

# =============================================================================
# INITIALIZATION FUNCTIONS
# =============================================================================

initialize_platform() {
    log "Initializing ${SCRIPT_NAME}"
    
    # Create directory structure
    mkdir -p "$CONFIG_DIR" \
             "$DATA_DIR/vms" \
             "$DATA_DIR/disks" \
             "$DATA_DIR/cloudinit" \
             "$DATA_DIR/dockervm" \
             "$DATA_DIR/lxd" \
             "$DATA_DIR/jupyter" \
             "$DATA_DIR/backups" \
             "$DATA_DIR/snapshots" \
             "$USER_HOME/zynexforge/templates/cloud" \
             "$USER_HOME/zynexforge/templates/iso" \
             "$USER_HOME/zynexforge/logs" \
             "$USER_HOME/zynexforge/scripts"
    
    # Create default config if not exists
    if [ ! -f "$GLOBAL_CONFIG" ]; then
        cat > "$GLOBAL_CONFIG" << 'EOF'
# ZynexForge Global Configuration
platform:
  name: "ZynexForge CloudStack™ Ultimate"
  version: "2.0.0"
  default_node: "local"
  ssh_base_port: 22000
  max_vms_per_node: 100
  user_mode: true
  user_home: "$USER_HOME"
  auto_backup: true
  backup_retention_days: 7
  enable_monitoring: true
  enable_auto_updates: false

security:
  firewall_enabled: false
  default_ssh_user: "zynexuser"
  password_min_length: 12
  use_ssh_keys: true
  enforce_password_policy: true
  enable_2fa: false
  auto_security_updates: true

networking:
  default_network: "user"
  enable_bridge: false
  dns_servers: ["8.8.8.8", "1.1.1.1"]
  enable_ipv6: false

performance:
  enable_kvm_acceleration: true
  enable_virtio: true
  disk_cache: "writeback"
  io_threads: 4
  enable_hugepages: false

paths:
  templates: "$USER_HOME/zynexforge/templates/cloud"
  isos: "$USER_HOME/zynexforge/templates/iso"
  vm_configs: "$DATA_DIR/vms"
  vm_disks: "$DATA_DIR/disks"
  logs: "$USER_HOME/zynexforge/logs"
  backups: "$DATA_DIR/backups"
  snapshots: "$DATA_DIR/snapshots"
EOF
        print_status "SUCCESS" "Global configuration created"
    fi
    
    # Create nodes database if not exists
    if [ ! -f "$NODES_DB" ]; then
        cat > "$NODES_DB" << EOF
# ZynexForge Nodes Database
nodes:
  local:
    node_id: "local"
    node_name: "Local Node"
    location_name: "Local, Server"
    provider: "Self-Hosted"
    public_ip: "127.0.0.1"
    private_ip: "192.168.1.100"
    capabilities: ["kvm", "qemu", "lxd", "docker", "jupyter"]
    tags: ["production", "primary"]
    status: "active"
    created_at: "$(date -Iseconds)"
    last_seen: "$(date -Iseconds)"
    user_mode: true
    resources:
      cpu_cores: $(nproc)
      memory_gb: $(free -g | awk '/^Mem:/ {print $2}')
      disk_gb: $(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
      available_vms: 50
EOF
        print_status "SUCCESS" "Nodes database created"
    fi
    
    # Generate SSH key if not exists
    if [ ! -f "$SSH_KEY_FILE" ]; then
        print_status "INFO" "Generating SSH key for ZynexForge..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q -C "zynexforge@$(hostname)"
        chmod 600 "$SSH_KEY_FILE"
        chmod 644 "${SSH_KEY_FILE}.pub"
        print_status "SUCCESS" "SSH key generated: $SSH_KEY_FILE"
    fi
    
    # Check dependencies
    check_dependencies
    
    # Create startup script
    create_startup_script
    
    print_status "SUCCESS" "Platform initialized successfully!"
    log "Platform initialization completed"
}

create_startup_script() {
    cat > "$USER_HOME/zynexforge/scripts/startup.sh" << 'EOF'
#!/bin/bash
# ZynexForge Startup Script
# Auto-starts VMs on system boot

set -euo pipefail

CONFIG_DIR="$HOME/.zynexforge"
DATA_DIR="$CONFIG_DIR/data"
LOG_FILE="$CONFIG_DIR/startup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

start_vm() {
    local vm_name="$1"
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ -f "$vm_config" ]; then
        log "Starting VM: $vm_name"
        # Load VM config and start
        source "$vm_config"
        
        # Check if VM is already running
        if [ -f "/tmp/zynexforge_${vm_name}.pid" ]; then
            local pid
            pid=$(cat "/tmp/zynexforge_${vm_name}.pid")
            if ps -p "$pid" > /dev/null 2>&1; then
                log "VM $vm_name is already running (PID: $pid)"
                return 0
            fi
        fi
        
        # Start VM (simplified version)
        qemu-system-x86_64 \
            -name "$vm_name" \
            -enable-kvm \
            -cpu host \
            -smp "$cpu_cores" \
            -m "$ram_mb" \
            -drive "file=$disk_path,if=virtio,format=qcow2" \
            -netdev "user,id=net0,hostfwd=tcp::$ssh_port-:22" \
            -device "virtio-net-pci,netdev=net0" \
            -daemonize \
            -pidfile "/tmp/zynexforge_${vm_name}.pid"
        
        log "VM $vm_name started on port $ssh_port"
    fi
}

main() {
    log "ZynexForge Startup Script"
    log "Starting at: $(date)"
    
    # Start all VMs with auto_start=true
    if [ -d "$DATA_DIR/vms" ]; then
        for config in "$DATA_DIR/vms"/*.conf; do
            if [ -f "$config" ]; then
                # Check if auto_start is enabled
                if grep -q "auto_start: true" "$config"; then
                    vm_name=$(basename "$config" .conf)
                    start_vm "$vm_name"
                fi
            fi
        done
    fi
    
    log "Startup completed at: $(date)"
}

main "$@"
EOF
    
    chmod +x "$USER_HOME/zynexforge/scripts/startup.sh"
}

# =============================================================================
# VM MANAGEMENT FUNCTIONS
# =============================================================================

vm_create_wizard() {
    print_header
    print_status "HEADER" "🚀 Create New VM"
    echo
    
    # Node selection
    print_status "INFO" "Select Node:"
    list_nodes_simple
    echo
    read -rp "$(print_status "INPUT" "Enter Node ID (default: local): ")" node_id
    node_id=${node_id:-local}
    
    # Runtime selection
    print_status "INFO" "Select runtime:"
    echo "  [1] KVM+QEMU (Hardware Acceleration)"
    echo "  [2] QEMU TCG (Software Emulation)"
    echo "  [3] Docker Container"
    echo "  [4] LXD Container"
    echo
    read -rp "$(print_status "INPUT" "Choice (1-4): ")" runtime_choice
    
    local acceleration="tcg"
    local runtime_type="qemu"
    
    case "$runtime_choice" in
        1)
            if [ ! -r "/dev/kvm" ]; then
                print_status "ERROR" "KVM not available or no read permission on /dev/kvm!"
                print_status "INFO" "Try: sudo chmod 666 /dev/kvm (temporary) or add user to kvm group"
                sleep 2
                return
            fi
            acceleration="kvm"
            runtime_type="qemu"
            ;;
        2)
            acceleration="tcg"
            runtime_type="qemu"
            ;;
        3)
            runtime_type="docker"
            ;;
        4)
            runtime_type="lxd"
            ;;
        *)
            print_status "ERROR" "Invalid choice"
            return
            ;;
    esac
    
    # OS selection
    print_status "INFO" "Select OS Template:"
    echo "Cloud Images:"
    local i=1
    for os in "${!OS_TEMPLATES[@]}"; do
        echo "  $i) $os"
        i=$((i + 1))
    done
    echo
    echo "Custom ISO:"
    echo "  99) Boot from ISO"
    echo
    
    read -rp "$(print_status "INPUT" "Choice: ")" os_choice
    
    local os_template=""
    if [ "$os_choice" = "99" ]; then
        read -rp "$(print_status "INPUT" "Enter path to ISO file: ")" iso_path
        if [ ! -f "$iso_path" ]; then
            print_status "ERROR" "ISO file not found: $iso_path"
            return
        fi
        os_template="custom-iso"
    else
        local os_keys=("${!OS_TEMPLATES[@]}")
        local selected_key="${os_keys[$((os_choice-1))]}"
        os_template="$selected_key"
    fi
    
    # VM details
    while true; do
        read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
        if validate_input "name" "$vm_name"; then
            break
        fi
    done
    
    # Check if VM already exists
    if [ -f "$DATA_DIR/vms/${vm_name}.conf" ]; then
        print_status "ERROR" "VM '$vm_name' already exists"
        sleep 1
        return
    fi
    
    # Resource allocation
    while true; do
        read -rp "$(print_status "INPUT" "CPU cores (1-32, default: 2): ")" cpu_cores
        cpu_cores=${cpu_cores:-2}
        if validate_input "number" "$cpu_cores" && [ "$cpu_cores" -ge 1 ] && [ "$cpu_cores" -le 32 ]; then
            break
        fi
        print_status "ERROR" "Invalid CPU cores (1-32)"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "RAM in MB (512-65536, default: 2048): ")" ram_mb
        ram_mb=${ram_mb:-2048}
        if validate_input "number" "$ram_mb" && [ "$ram_mb" -ge 512 ] && [ "$ram_mb" -le 65536 ]; then
            break
        fi
        print_status "ERROR" "Invalid RAM (512-65536 MB)"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "Disk size in GB (10-1000, default: 50): ")" disk_gb
        disk_gb=${disk_gb:-50}
        if validate_input "number" "$disk_gb" && [ "$disk_gb" -ge 10 ] && [ "$disk_gb" -le 1000 ]; then
            break
        fi
        print_status "ERROR" "Invalid disk size (10-1000 GB)"
    done
    
    # SSH port (auto-find available)
    print_status "INFO" "Finding available SSH port..."
    ssh_port=$(find_available_port)
    print_status "INFO" "Using SSH port: $ssh_port"
    
    # Credentials
    while true; do
        read -rp "$(print_status "INPUT" "Username (default: zynexuser): ")" vm_user
        vm_user=${vm_user:-zynexuser}
        if validate_input "username" "$vm_user"; then
            break
        fi
    done
    
    read -rsp "$(print_status "INPUT" "Password (press Enter to generate): ")" vm_pass
    echo
    if [ -z "$vm_pass" ]; then
        vm_pass=$(generate_password 16)
        print_status "INFO" "Generated password: $vm_pass"
    fi
    
    # Network configuration
    print_status "INFO" "Network Configuration:"
    echo "  [1] User-mode networking (NAT)"
    echo "  [2] Bridge networking (requires root)"
    echo
    read -rp "$(print_status "INPUT" "Network mode (1-2, default: 1): ")" network_mode
    network_mode=${network_mode:-1}
    
    # Additional options
    read -rp "$(print_status "INPUT" "Enable auto-start on boot? (y/N): ")" auto_start
    auto_start=${auto_start:-n}
    
    read -rp "$(print_status "INPUT" "Enable backup? (y/N): ")" enable_backup
    enable_backup=${enable_backup:-n}
    
    # Confirm
    echo
    print_status "HEADER" "Summary:"
    echo "  Node: $node_id"
    echo "  Runtime: $runtime_type ($acceleration)"
    echo "  OS: $os_template"
    echo "  VM Name: $vm_name"
    echo "  Resources: ${cpu_cores}vCPU, ${ram_mb}MB RAM, ${disk_gb}GB Disk"
    echo "  SSH Port: $ssh_port"
    echo "  Username: $vm_user"
    echo "  Network: $([ "$network_mode" = "1" ] && echo "NAT" || echo "Bridge")"
    echo "  Auto-start: $([ "$auto_start" = "y" ] && echo "Yes" || echo "No")"
    echo "  Backup: $([ "$enable_backup" = "y" ] && echo "Yes" || echo "No")"
    echo
    
    read -rp "$(print_status "INPUT" "Create VM? (y/N): ")" confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_vm "$vm_name" "$node_id" "$acceleration" "$os_template" "$cpu_cores" "$ram_mb" "$disk_gb" \
                  "$ssh_port" "$vm_user" "$vm_pass" "$network_mode" "$auto_start" "$enable_backup"
    else
        print_status "INFO" "VM creation cancelled"
        sleep 1
    fi
}

create_vm() {
    local vm_name="$1"
    local node_id="$2"
    local acceleration="$3"
    local os_template="$4"
    local cpu_cores="$5"
    local ram_mb="$6"
    local disk_gb="$7"
    local ssh_port="$8"
    local vm_user="$9"
    local vm_pass="${10}"
    local network_mode="${11}"
    local auto_start="${12}"
    local enable_backup="${13}"
    
    log "Creating VM: $vm_name on node $node_id"
    
    # Create VM directory
    local vm_dir="$DATA_DIR/vms"
    local disk_dir="$DATA_DIR/disks"
    local cloudinit_dir="$DATA_DIR/cloudinit/$vm_name"
    
    mkdir -p "$vm_dir" "$disk_dir" "$cloudinit_dir"
    
    # Create disk
    local disk_path="$disk_dir/${vm_name}.qcow2"
    
    print_status "INFO" "Creating disk image..."
    
    # Check if template exists
    local template_path="$USER_HOME/zynexforge/templates/cloud/${os_template}.qcow2"
    if [ -f "$template_path" ]; then
        print_status "INFO" "Using template: $os_template"
        cp "$template_path" "$disk_path"
        qemu-img resize "$disk_path" "${disk_gb}G" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            print_status "ERROR" "Failed to resize disk"
            return 1
        fi
    else
        print_status "INFO" "Creating blank disk"
        qemu-img create -f qcow2 -o preallocation=metadata "$disk_path" "${disk_gb}G"
        if [ $? -ne 0 ]; then
            print_status "ERROR" "Failed to create disk image"
            return 1
        fi
    fi
    
    # Create cloud-init data
    print_status "INFO" "Creating cloud-init configuration..."
    
    # Get SSH public key
    local ssh_pub_key=""
    if [ -f "${SSH_KEY_FILE}.pub" ]; then
        ssh_pub_key=$(cat "${SSH_KEY_FILE}.pub")
    fi
    
    # Create advanced cloud-init config
    cat > "$cloudinit_dir/user-data" << EOF
#cloud-config
hostname: $vm_name
manage_etc_hosts: true
timezone: UTC
users:
  - name: $vm_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$vm_pass'
    ssh_authorized_keys:
      - $ssh_pub_key
    groups: [sudo, docker, admin]
    ssh_import_id: []
packages:
  - neofetch
  - htop
  - net-tools
  - curl
  - wget
  - git
  - python3-pip
  - unattended-upgrades
package_update: true
package_upgrade: true
package_reboot_if_required: true
runcmd:
  - echo "ZynexForge CloudStack™ Ultimate" > /etc/zynexforge-os.ascii
  - echo '#!/bin/bash' > /etc/profile.d/zynexforge-login.sh
  - echo 'clear' >> /etc/profile.d/zynexforge-login.sh
  - echo 'neofetch' >> /etc/profile.d/zynexforge-login.sh
  - echo 'cat /etc/zynexforge-os.ascii' >> /etc/profile.d/zynexforge-login.sh
  - echo 'echo -e "\\\\033[1;36m⚡ ZynexForge CloudStack™ Ultimate Edition\\\\033[0m"' >> /etc/profile.d/zynexforge-login.sh
  - echo 'echo -e "\\\\033[1;33m🔥 Made by FaaizXD | Version: 2.0.0\\\\033[0m"' >> /etc/profile.d/zynexforge-login.sh
  - echo 'echo -e "\\\\033[1;32mStatus: Premium VPS Active\\\\033[0m"' >> /etc/profile.d/zynexforge-login.sh
  - chmod +x /etc/profile.d/zynexforge-login.sh
  - sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
  - systemctl restart sshd
power_state:
  mode: reboot
  message: "Applying cloud-init configuration"
  timeout: 300
EOF
    
    cat > "$cloudinit_dir/meta-data" << EOF
instance-id: $vm_name
local-hostname: $vm_name
EOF
    
    # Create network configuration
    cat > "$cloudinit_dir/network-config" << EOF
version: 2
ethernets:
  eth0:
    dhcp4: true
    dhcp6: false
EOF
    
    # Create seed ISO
    print_status "INFO" "Creating cloud-init seed ISO..."
    if command -v cloud-localds > /dev/null 2>&1; then
        cloud-localds -v --network-config="$cloudinit_dir/network-config" \
            "$cloudinit_dir/seed.iso" \
            "$cloudinit_dir/user-data" \
            "$cloudinit_dir/meta-data"
    elif command -v genisoimage > /dev/null 2>&1; then
        genisoimage -output "$cloudinit_dir/seed.iso" \
            -volid cidata -joliet -rock \
            "$cloudinit_dir/user-data" \
            "$cloudinit_dir/meta-data" \
            "$cloudinit_dir/network-config"
    else
        print_status "ERROR" "No ISO creation tool found"
        return 1
    fi
    
    if [ $? -ne 0 ]; then
        print_status "ERROR" "Failed to create cloud-init ISO"
        return 1
    fi
    
    # Create VM config file
    cat > "$vm_dir/${vm_name}.conf" << EOF
# ZynexForge VM Configuration
VM_NAME="$vm_name"
NODE_ID="$node_id"
ACCELERATION="$acceleration"
RUNTIME_TYPE="$runtime_type"
OS_TEMPLATE="$os_template"
CPU_CORES="$cpu_cores"
RAM_MB="$ram_mb"
DISK_GB="$disk_gb"
SSH_PORT="$ssh_port"
VM_USER="$vm_user"
VM_PASS="$vm_pass"
NETWORK_MODE="$network_mode"
AUTO_START="$([ "$auto_start" = "y" ] && echo "true" || echo "false")"
ENABLE_BACKUP="$([ "$enable_backup" = "y" ] && echo "true" || echo "false")"
STATUS="stopped"
CREATED_AT="$(date -Iseconds)"
UPDATED_AT="$(date -Iseconds)"
DISK_PATH="$disk_path"
CLOUDINIT_DIR="$cloudinit_dir"
USER_MODE="true"
EOF
    
    print_status "SUCCESS" "VM '$vm_name' created successfully!"
    
    # Show access information
    show_vm_access "$vm_name"
    
    # Ask to start VM
    read -rp "$(print_status "INPUT" "Start VM now? (y/N): ")" start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        start_vm "$vm_name"
    fi
    
    sleep 2
}

start_vm() {
    local vm_name="$1"
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    # Load configuration
    source "$vm_config"
    
    # Check if VM is already running
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "ERROR" "VM '$vm_name' is already running (PID: $pid)"
            return 1
        fi
    fi
    
    # Check if port is available
    if ! check_port_available "$SSH_PORT"; then
        print_status "ERROR" "Port $SSH_PORT is already in use!"
        read -rp "$(print_status "INPUT" "Find new port? (y/N): ")" find_new
        if [[ "$find_new" =~ ^[Yy]$ ]]; then
            SSH_PORT=$(find_available_port)
            print_status "INFO" "Using new port: $SSH_PORT"
            # Update config
            sed -i "s/SSH_PORT=.*/SSH_PORT=\"$SSH_PORT\"/" "$vm_config"
        else
            return 1
        fi
    fi
    
    # Build QEMU command
    local qemu_cmd=(
        "qemu-system-x86_64"
        "-name" "$vm_name"
        "-pidfile" "$pid_file"
        "-daemonize"
    )
    
    # Acceleration
    if [ "$ACCELERATION" = "kvm" ] && [ -r "/dev/kvm" ]; then
        qemu_cmd+=("-enable-kvm" "-cpu" "host" "-smp" "$CPU_CORES")
    else
        qemu_cmd+=("-cpu" "qemu64" "-smp" "$CPU_CORES")
    fi
    
    # Resources
    qemu_cmd+=("-m" "$RAM_MB")
    
    # Display (none for headless)
    qemu_cmd+=("-display" "none" "-vga" "none")
    
    # Network
    if [ "$NETWORK_MODE" = "1" ]; then
        # User-mode networking
        qemu_cmd+=("-netdev" "user,id=net0,hostfwd=tcp::$SSH_PORT-:22")
        qemu_cmd+=("-device" "virtio-net-pci,netdev=net0")
    else
        # Bridge networking (simplified)
        qemu_cmd+=("-netdev" "bridge,id=net0,br=virbr0")
        qemu_cmd+=("-device" "virtio-net-pci,netdev=net0")
    fi
    
    # Storage with performance optimizations
    qemu_cmd+=(
        "-drive" "file=$DISK_PATH,if=virtio,cache=writeback,discard=unmap,format=qcow2"
        "-drive" "file=$CLOUDINIT_DIR/seed.iso,if=virtio,format=raw,readonly=on"
        "-device" "virtio-balloon-pci"
        "-object" "rng-random,filename=/dev/urandom,id=rng0"
        "-device" "virtio-rng-pci,rng=rng0"
    )
    
    # Performance optimizations
    qemu_cmd+=(
        "-machine" "type=pc,accel=$ACCELERATION"
        "-rtc" "base=utc,clock=host"
        "-boot" "order=c"
    )
    
    print_status "INFO" "Starting VM '$vm_name'..."
    
    # Start VM
    if "${qemu_cmd[@]}"; then
        # Update status
        sed -i "s/STATUS=.*/STATUS=\"running\"/" "$vm_config"
        sed -i "s/UPDATED_AT=.*/UPDATED_AT=\"$(date -Iseconds)\"/" "$vm_config"
        
        print_status "SUCCESS" "VM '$vm_name' started successfully"
        print_status "INFO" "SSH accessible on port: $SSH_PORT"
        
        # Wait for VM to boot
        print_status "INFO" "Waiting for VM to boot (30 seconds)..."
        sleep 30
        
        # Show access info
        show_vm_access "$vm_name"
    else
        print_status "ERROR" "Failed to start VM '$vm_name'"
        rm -f "$pid_file"
        return 1
    fi
}

stop_vm() {
    local vm_name="$1"
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "INFO" "Stopping VM '$vm_name' (PID: $pid)..."
            
            # Try graceful shutdown first
            kill -TERM "$pid"
            
            # Wait for process to terminate
            local wait_time=0
            while ps -p "$pid" > /dev/null 2>&1 && [ "$wait_time" -lt 30 ]; do
                sleep 1
                wait_time=$((wait_time + 1))
            done
            
            if ps -p "$pid" > /dev/null 2>&1; then
                print_status "WARNING" "VM did not stop gracefully, forcing kill..."
                kill -KILL "$pid"
            fi
            
            rm -f "$pid_file"
            print_status "SUCCESS" "VM '$vm_name' stopped"
        else
            print_status "WARNING" "VM '$vm_name' was not running (stale PID file)"
            rm -f "$pid_file"
        fi
    else
        print_status "WARNING" "VM '$vm_name' is not running"
    fi
    
    # Update status
    if [ -f "$vm_config" ]; then
        sed -i "s/STATUS=.*/STATUS=\"stopped\"/" "$vm_config"
        sed -i "s/UPDATED_AT=.*/UPDATED_AT=\"$(date -Iseconds)\"/" "$vm_config"
    fi
}

# =============================================================================
# NODE MANAGEMENT FUNCTIONS
# =============================================================================

list_nodes_simple() {
    if [ -f "$NODES_DB" ]; then
        print_status "INFO" "Available Nodes:"
        while IFS= read -r line; do
            if [[ "$line" =~ ^\ \ ([a-zA-Z0-9_]*): ]]; then
                node_id="${BASH_REMATCH[1]}"
                echo -n "  $node_id: "
            elif [[ "$line" =~ \ \ node_name:\ (.*) ]]; then
                echo -n "${BASH_REMATCH[1]} "
            elif [[ "$line" =~ \ \ location_name:\ (.*) ]]; then
                echo "[${BASH_REMATCH[1]}]"
            fi
        done < "$NODES_DB"
    else
        echo "  local: Local Node [Local, Server]"
    fi
}

add_node() {
    print_header
    print_status "HEADER" "➕ Add New Node"
    echo
    
    # Select region
    print_status "INFO" "Select region/location:"
    for i in {1..12}; do
        if [ -n "${REGIONS[$i]}" ]; then
            IFS='|' read -r location region_code <<< "${REGIONS[$i]}"
            echo "  $i) $location"
        fi
    done
    echo "  0) Custom location"
    echo
    
    read -rp "$(print_status "INPUT" "Enter choice: ")" region_choice
    
    local location_name=""
    local region_code=""
    
    if [ "$region_choice" = "0" ]; then
        read -rp "$(print_status "INPUT" "Enter custom location (City, Country): ")" custom_location
        read -rp "$(print_status "INPUT" "Enter region code (e.g., us-east-1): ")" custom_region
        location_name="$custom_location"
        region_code="$custom_region"
    elif [ -n "${REGIONS[$region_choice]}" ]; then
        IFS='|' read -r location_name region_code <<< "${REGIONS[$region_choice]}"
    else
        print_status "ERROR" "Invalid choice"
        sleep 1
        return
    fi
    
    # Node details
    while true; do
        read -rp "$(print_status "INPUT" "Node ID (unique identifier): ")" node_id
        if [ -z "$node_id" ]; then
            print_status "ERROR" "Node ID cannot be empty"
        elif grep -q "^  $node_id:" "$NODES_DB" 2>/dev/null; then
            print_status "ERROR" "Node ID already exists"
        else
            break
        fi
    done
    
    read -rp "$(print_status "INPUT" "Node name: ")" node_name
    read -rp "$(print_status "INPUT" "Provider (optional): ")" provider
    
    while true; do
        read -rp "$(print_status "INPUT" "Public IP address: ")" public_ip
        if validate_input "ip" "$public_ip"; then
            break
        fi
    done
    
    # Capabilities
    print_status "INFO" "Select capabilities (comma-separated):"
    echo "  Available: kvm, qemu, lxd, docker, jupyter, monitoring, backup"
    read -rp "$(print_status "INPUT" "Capabilities: ")" capabilities
    
    # Tags
    print_status "INFO" "Tags (comma-separated):"
    echo "  Available: production, staging, development, edge, backup, monitoring"
    read -rp "$(print_status "INPUT" "Tags: ")" tags_input
    
    # Resources
    print_status "INFO" "Node Resources:"
    read -rp "$(print_status "INPUT" "CPU Cores (default: $(nproc)): ")" node_cpu
    node_cpu=${node_cpu:-$(nproc)}
    
    read -rp "$(print_status "INPUT" "Memory in GB (default: $(free -g | awk '/^Mem:/ {print $2}')): ")" node_memory
    node_memory=${node_memory:-$(free -g | awk '/^Mem:/ {print $2}')}
    
    read -rp "$(print_status "INPUT" "Disk in GB (default: $(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')): ")" node_disk
    node_disk=${node_disk:-$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')}
    
    # Create node entry
    cat >> "$NODES_DB" << EOF
  $node_id:
    node_id: "$node_id"
    node_name: "$node_name"
    location_name: "$location_name"
    region_code: "$region_code"
    provider: "$provider"
    public_ip: "$public_ip"
    private_ip: "192.168.1.100"
    capabilities: [${capabilities// /}]
    tags: [${tags_input// /}]
    status: "active"
    created_at: "$(date -Iseconds)"
    last_seen: "$(date -Iseconds)"
    user_mode: true
    resources:
      cpu_cores: "$node_cpu"
      memory_gb: "$node_memory"
      disk_gb: "$node_disk"
      available_vms: "50"
EOF
    
    print_status "SUCCESS" "Node '$node_name' added successfully!"
    log "Added new node: $node_id ($node_name)"
    
    sleep 2
}

# =============================================================================
# DOCKER VM FUNCTIONS
# =============================================================================

create_docker_vm() {
    print_header
    print_status "HEADER" "🐳 Create Docker VM"
    echo
    
    # Check Docker availability
    if ! command -v docker > /dev/null 2>&1; then
        print_status "ERROR" "Docker is not installed"
        print_status "INFO" "Install Docker first: https://docs.docker.com/engine/install/"
        sleep 2
        return
    fi
    
    if ! docker info > /dev/null 2>&1; then
        print_status "ERROR" "Docker daemon is not running"
        print_status "INFO" "Start Docker service: sudo systemctl start docker"
        sleep 2
        return
    fi
    
    # Docker VM details
    while true; do
        read -rp "$(print_status "INPUT" "Docker VM Name: ")" dv_name
        if validate_input "name" "$dv_name"; then
            if docker ps -a --format "{{.Names}}" | grep -q "^${dv_name}$"; then
                print_status "ERROR" "Docker container '$dv_name' already exists"
            else
                break
            fi
        fi
    done
    
    # Base image selection
    print_status "INFO" "Select Base Image:"
    echo "  1) ubuntu:24.04"
    echo "  2) debian:12"
    echo "  3) alpine:latest"
    echo "  4) centos:stream9"
    echo "  5) fedora:latest"
    echo "  6) rockylinux:9"
    echo "  7) almalinux:9"
    echo
    
    read -rp "$(print_status "INPUT" "Choice (1-7): ")" image_choice
    
    case "$image_choice" in
        1) base_image="ubuntu:24.04" ;;
        2) base_image="debian:12" ;;
        3) base_image="alpine:latest" ;;
        4) base_image="centos:stream9" ;;
        5) base_image="fedora:latest" ;;
        6) base_image="rockylinux:9" ;;
        7) base_image="almalinux:9" ;;
        *) print_status "ERROR" "Invalid choice"; return ;;
    esac
    
    # Resource limits
    print_status "INFO" "Resource Limits:"
    read -rp "$(print_status "INPUT" "CPU limit (e.g., 1.5 or 2, press Enter for unlimited): ")" cpu_limit
    read -rp "$(print_status "INPUT" "Memory limit (e.g., 512m or 2g, press Enter for unlimited): ")" memory_limit
    
    # Storage
    read -rp "$(print_status "INPUT" "Storage limit (e.g., 10G, press Enter for unlimited): ")" storage_limit
    
    # SSH support
    print_status "INFO" "SSH Configuration:"
    read -rp "$(print_status "INPUT" "Enable SSH access? (y/N): ")" enable_ssh
    
    local ssh_port=""
    local ssh_user=""
    local ssh_pass=""
    
    if [[ "$enable_ssh" =~ ^[Yy]$ ]]; then
        ssh_port=$(find_available_port 22022)
        print_status "INFO" "Using SSH port: $ssh_port"
        
        while true; do
            read -rp "$(print_status "INPUT" "SSH Username (default: dockeruser): ")" ssh_user
            ssh_user=${ssh_user:-dockeruser}
            if validate_input "username" "$ssh_user"; then
                break
            fi
        done
        
        read -rsp "$(print_status "INPUT" "SSH Password (press Enter to generate): ")" ssh_pass
        echo
        if [ -z "$ssh_pass" ]; then
            ssh_pass=$(generate_password 16)
            print_status "INFO" "Generated password: $ssh_pass"
        fi
    fi
    
    # Port mappings
    print_status "INFO" "Port Mappings:"
    echo "Format: host_port:container_port (e.g., 8080:80 8443:443)"
    echo "Multiple mappings separated by space"
    read -rp "$(print_status "INPUT" "Enter port mappings: ")" port_mappings
    
    # Environment variables
    print_status "INFO" "Environment Variables:"
    echo "Format: KEY=VALUE (e.g., TZ=UTC)"
    echo "Multiple variables separated by space"
    read -rp "$(print_status "INPUT" "Enter environment variables: ")" env_vars
    
    # Volume mounts
    print_status "INFO" "Volume Mounts:"
    echo "Format: host_path:container_path (e.g., /host/data:/container/data)"
    echo "Multiple mounts separated by space"
    read -rp "$(print_status "INPUT" "Enter volume mounts: ")" volume_mounts
    
    # Create Docker VM
    print_status "INFO" "Creating Docker VM '$dv_name'..."
    
    # Build Docker command
    local docker_cmd=("docker" "run" "-d")
    docker_cmd+=("--name" "$dv_name")
    docker_cmd+=("--hostname" "$dv_name")
    docker_cmd+=("--restart" "unless-stopped")
    
    if [ -n "$cpu_limit" ]; then
        docker_cmd+=("--cpus=$cpu_limit")
    fi
    
    if [ -n "$memory_limit" ]; then
        docker_cmd+=("--memory=$memory_limit")
    fi
    
    if [ -n "$storage_limit" ]; then
        docker_cmd+=("--storage-opt" "size=$storage_limit")
    fi
    
    # SSH port mapping
    if [[ "$enable_ssh" =~ ^[Yy]$ ]] && [ -n "$ssh_port" ]; then
        docker_cmd+=("-p" "$ssh_port:22")
    fi
    
    # Add port mappings
    for mapping in $port_mappings; do
        docker_cmd+=("-p" "$mapping")
    done
    
    # Add environment variables
    for env_var in $env_vars; do
        docker_cmd+=("-e" "$env_var")
    done
    
    # Add volume mounts
    for volume in $volume_mounts; do
        docker_cmd+=("-v" "$volume")
    done
    
    docker_cmd+=("$base_image")
    
    # Start with tail to keep running
    docker_cmd+=("tail" "-f" "/dev/null")
    
    print_status "DEBUG" "Running: ${docker_cmd[*]}"
    
    if "${docker_cmd[@]}"; then
        print_status "SUCCESS" "Docker VM '$dv_name' created"
        
        # Install SSH if enabled
        if [[ "$enable_ssh" =~ ^[Yy]$ ]]; then
            print_status "INFO" "Configuring SSH access..."
            
            # Install SSH server
            docker exec "$dv_name" sh -c '
                if command -v apt-get >/dev/null 2>&1; then
                    apt-get update && apt-get install -y openssh-server sudo
                elif command -v apk >/dev/null 2>&1; then
                    apk add openssh-server sudo
                elif command -v yum >/dev/null 2>&1; then
                    yum install -y openssh-server sudo
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y openssh-server sudo
                fi
            ' 2>/dev/null
            
            # Create user and set password
            docker exec "$dv_name" sh -c "
                if id '$ssh_user' >/dev/null 2>&1; then
                    echo 'User already exists'
                else
                    useradd -m -s /bin/bash '$ssh_user'
                fi
                echo '$ssh_user:$ssh_pass' | chpasswd
                echo '$ssh_user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
                mkdir -p /home/$ssh_user/.ssh
                echo '$(cat "${SSH_KEY_FILE}.pub" 2>/dev/null || echo "")' >> /home/$ssh_user/.ssh/authorized_keys
                chown -R $ssh_user:$ssh_user /home/$ssh_user/.ssh
                chmod 700 /home/$ssh_user/.ssh
                chmod 600 /home/$ssh_user/.ssh/authorized_keys
            " 2>/dev/null
            
            # Configure SSH
            docker exec "$dv_name" sh -c '
                echo "PermitRootLogin no" >> /etc/ssh/sshd_config
                echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
                echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
                if [ -f /etc/init.d/ssh ]; then
                    /etc/init.d/ssh restart
                elif command -v systemctl >/dev/null 2>&1; then
                    systemctl restart sshd
                fi
            ' 2>/dev/null
            
            print_status "SUCCESS" "SSH installed on port $ssh_port"
        fi
        
        # Save config
        local dv_dir="$DATA_DIR/dockervm"
        mkdir -p "$dv_dir"
        
        cat > "$dv_dir/${dv_name}.conf" << EOF
# Docker VM Configuration
DV_NAME="$dv_name"
BASE_IMAGE="$base_image"
CPU_LIMIT="$cpu_limit"
MEMORY_LIMIT="$memory_limit"
STORAGE_LIMIT="$storage_limit"
ENABLE_SSH="$([ "$enable_ssh" = "y" ] && echo "true" || echo "false")"
SSH_PORT="$ssh_port"
SSH_USER="$ssh_user"
SSH_PASS="$ssh_pass"
PORT_MAPPINGS="$port_mappings"
ENV_VARS="$env_vars"
VOLUME_MOUNTS="$volume_mounts"
STATUS="running"
CREATED_AT="$(date -Iseconds)"
CONTAINER_ID=$(docker ps -qf "name=$dv_name")
EOF
        
        log "Created Docker VM: $dv_name"
        
        # Show access information
        echo
        print_status "SUCCESS" "Docker VM '$dv_name' is ready!"
        if [[ "$enable_ssh" =~ ^[Yy]$ ]]; then
            echo "  SSH Access: ssh -p $ssh_port $ssh_user@localhost"
            echo "  Password: $ssh_pass"
        fi
        echo "  Console: docker exec -it $dv_name /bin/bash"
        
    else
        print_status "ERROR" "Failed to create Docker VM"
    fi
    
    sleep 2
}

# =============================================================================
# JUPYTER LAB FUNCTIONS
# =============================================================================

create_jupyter_vm() {
    print_header
    print_status "HEADER" "🔬 Create Jupyter Lab"
    echo
    
    # Check Docker availability
    if ! command -v docker > /dev/null 2>&1; then
        print_status "ERROR" "Docker is not installed"
        print_status "INFO" "Install Docker first: https://docs.docker.com/engine/install/"
        sleep 2
        return
    fi
    
    while true; do
        read -rp "$(print_status "INPUT" "Jupyter Lab Name: ")" jv_name
        if validate_input "name" "$jv_name"; then
            if docker ps -a --format "{{.Names}}" | grep -q "^${jv_name}$"; then
                print_status "ERROR" "Jupyter Lab '$jv_name' already exists"
            else
                break
            fi
        fi
    done
    
    # Find available port
    jv_port=$(find_available_port 8888)
    print_status "INFO" "Using port: $jv_port"
    
    # Jupyter type selection
    print_status "INFO" "Select Jupyter Type:"
    echo "  1) Jupyter Lab (Recommended)"
    echo "  2) Jupyter Notebook"
    echo "  3) Data Science Notebook"
    echo "  4) TensorFlow Notebook"
    echo "  5) PySpark Notebook"
    echo
    
    read -rp "$(print_status "INPUT" "Choice (1-5): ")" jupyter_type_choice
    
    local jupyter_image="jupyter/base-notebook"
    case "$jupyter_type_choice" in
        1) jupyter_image="jupyter/tensorflow-notebook" ;;
        2) jupyter_image="jupyter/base-notebook" ;;
        3) jupyter_image="jupyter/datascience-notebook" ;;
        4) jupyter_image="jupyter/tensorflow-notebook" ;;
        5) jupyter_image="jupyter/pyspark-notebook" ;;
        *) jupyter_image="jupyter/base-notebook" ;;
    esac
    
    # Generate token
    local jv_token
    jv_token=$(openssl rand -hex 24 2>/dev/null || tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)
    
    # Resource limits
    print_status "INFO" "Resource Limits:"
    read -rp "$(print_status "INPUT" "CPU limit (e.g., 1.5, press Enter for unlimited): ")" jv_cpu_limit
    read -rp "$(print_status "INPUT" "Memory limit (e.g., 2g, press Enter for unlimited): ")" jv_memory_limit
    
    # Additional packages
    print_status "INFO" "Additional Packages:"
    echo "Enter space-separated package names (e.g., numpy pandas matplotlib)"
    read -rp "$(print_status "INPUT" "Packages to install: ")" jv_packages
    
    # Volume for persistence
    local volume_name="${jv_name}_data"
    docker volume create "$volume_name" > /dev/null 2>&1
    
    print_status "INFO" "Creating Jupyter Lab '$jv_name'..."
    
    # Build Docker command
    local docker_cmd=("docker" "run" "-d")
    docker_cmd+=("--name" "$jv_name")
    docker_cmd+=("-p" "$jv_port:8888")
    docker_cmd+=("-v" "$volume_name:/home/jovyan/work")
    docker_cmd+=("-e" "JUPYTER_TOKEN=$jv_token")
    
    if [ -n "$jv_cpu_limit" ]; then
        docker_cmd+=("--cpus=$jv_cpu_limit")
    fi
    
    if [ -n "$jv_memory_limit" ]; then
        docker_cmd+=("--memory=$jv_memory_limit")
    fi
    
    docker_cmd+=("$jupyter_image")
    
    # Start container
    if "${docker_cmd[@]}"; then
        print_status "SUCCESS" "Jupyter Lab '$jv_name' created"
        
        # Install additional packages if specified
        if [ -n "$jv_packages" ]; then
            print_status "INFO" "Installing additional packages..."
            docker exec "$jv_name" pip install $jv_packages 2>/dev/null || true
        fi
        
        # Save config
        local jv_dir="$DATA_DIR/jupyter"
        mkdir -p "$jv_dir"
        
        cat > "$jv_dir/${jv_name}.conf" << EOF
# Jupyter Lab Configuration
JV_NAME="$jv_name"
JV_PORT="$jv_port"
JV_TOKEN="$jv_token"
JV_IMAGE="$jupyter_image"
VOLUME_NAME="$volume_name"
CPU_LIMIT="$jv_cpu_limit"
MEMORY_LIMIT="$jv_memory_limit"
PACKAGES="$jv_packages"
STATUS="running"
CREATED_AT="$(date -Iseconds)"
CONTAINER_ID=$(docker ps -qf "name=$jv_name")
EOF
        
        # Show access information
        echo
        print_status "SUCCESS" "Jupyter Lab Access Information:"
        echo "  URL: http://localhost:$jv_port"
        echo "  Token: $jv_token"
        echo "  Direct URL: http://localhost:$jv_port/?token=$jv_token"
        echo
        echo "  Volume: $volume_name"
        echo "  Stop: docker stop $jv_name"
        echo "  Start: docker start $jv_name"
        
        log "Created Jupyter Lab: $jv_name"
    else
        print_status "ERROR" "Failed to create Jupyter Lab"
    fi
    
    sleep 2
}

# =============================================================================
# BACKUP & SNAPSHOT FUNCTIONS
# =============================================================================

backup_vm() {
    local vm_name="$1"
    local backup_dir="$DATA_DIR/backups"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${vm_name}_${timestamp}.tar.gz"
    
    mkdir -p "$backup_dir"
    
    print_status "INFO" "Creating backup of VM '$vm_name'..."
    
    # Stop VM if running
    stop_vm "$vm_name"
    
    # Create backup
    tar -czf "$backup_file" \
        "$DATA_DIR/vms/${vm_name}.conf" \
        "$DATA_DIR/disks/${vm_name}.qcow2" \
        "$DATA_DIR/cloudinit/${vm_name}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "Backup created: $backup_file"
        
        # Cleanup old backups (keep last 7 days)
        find "$backup_dir" -name "${vm_name}_*.tar.gz" -mtime +7 -delete 2>/dev/null
    else
        print_status "ERROR" "Failed to create backup"
    fi
    
    # Restart VM if it was running
    read -rp "$(print_status "INPUT" "Restart VM? (y/N): ")" restart_vm
    if [[ "$restart_vm" =~ ^[Yy]$ ]]; then
        start_vm "$vm_name"
    fi
}

create_snapshot() {
    local vm_name="$1"
    local snapshot_dir="$DATA_DIR/snapshots"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_name="${vm_name}_snapshot_${timestamp}"
    
    mkdir -p "$snapshot_dir"
    
    # Check if VM is running
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    local is_running=false
    
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            is_running=true
        fi
    fi
    
    print_status "INFO" "Creating snapshot of VM '$vm_name'..."
    
    if [ "$is_running" = true ]; then
        # Live snapshot
        print_status "INFO" "Creating live snapshot..."
        # This would require QEMU monitor commands
        print_status "WARNING" "Live snapshots not implemented in this version"
        print_status "INFO" "Stopping VM for snapshot..."
        stop_vm "$vm_name"
    fi
    
    # Create snapshot
    local disk_path="$DATA_DIR/disks/${vm_name}.qcow2"
    if [ -f "$disk_path" ]; then
        qemu-img create -f qcow2 -b "$disk_path" \
            "$snapshot_dir/${snapshot_name}.qcow2"
        
        # Save snapshot info
        cat > "$snapshot_dir/${snapshot_name}.info" << EOF
SNAPSHOT_NAME="$snapshot_name"
VM_NAME="$vm_name"
CREATED_AT="$(date -Iseconds)"
DISK_SIZE=$(qemu-img info "$disk_path" | grep "virtual size" | awk '{print $3}')
EOF
        
        print_status "SUCCESS" "Snapshot created: $snapshot_name"
    else
        print_status "ERROR" "VM disk not found"
    fi
    
    # Restart VM if it was running
    if [ "$is_running" = true ]; then
        read -rp "$(print_status "INPUT" "Restart VM? (y/N): ")" restart_vm
        if [[ "$restart_vm" =~ ^[Yy]$ ]]; then
            start_vm "$vm_name"
        fi
    fi
}

# =============================================================================
# MONITORING FUNCTIONS
# =============================================================================

show_vm_performance() {
    local vm_name="$1"
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        sleep 1
        return 1
    fi
    
    print_header
    print_status "HEADER" "📊 VM Performance: $vm_name"
    echo
    
    source "$vm_config"
    
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "INFO" "Process Resources (PID: $pid):"
            echo "══════════════════════════════════════════"
            
            # Get process stats
            echo "📈 CPU and Memory Usage:"
            ps -p "$pid" -o pid,ppid,pcpu,pmem,rss,vsz,etime,cmd --no-headers 2>/dev/null || echo "Cannot get process info"
            echo
            
            # Get CPU percentage
            local cpu_percent
            cpu_percent=$(ps -p "$pid" -o pcpu --no-headers 2>/dev/null | tr -d ' ' || echo "0")
            echo "  CPU Usage: ${cpu_percent}%"
            
            # Get memory usage
            local mem_kb
            mem_kb=$(ps -p "$pid" -o rss --no-headers 2>/dev/null | tr -d ' ' || echo "0")
            local mem_mb=$((mem_kb / 1024))
            echo "  Memory Usage: ${mem_mb}MB / ${RAM_MB}MB"
            
            # Get uptime
            local uptime
            uptime=$(ps -p "$pid" -o etime --no-headers 2>/dev/null | tr -d ' ' || echo "00:00")
            echo "  Uptime: $uptime"
            
            # Disk usage
            echo
            echo "💾 Disk Information:"
            if [ -f "$DISK_PATH" ]; then
                qemu-img info "$DISK_PATH" 2>/dev/null | grep -E "(virtual size|disk size|format)" || echo "Cannot get disk info"
            fi
            
            # Network connections
            echo
            echo "🌐 Network Connections:"
            if command -v ss > /dev/null 2>&1; then
                ss -tlnp | grep ":$SSH_PORT" || echo "No connections on port $SSH_PORT"
            fi
            
        else
            print_status "INFO" "VM is not running"
            echo "Configuration:"
            echo "  CPU: $CPU_CORES vCPU"
            echo "  RAM: $RAM_MB MB"
            echo "  Disk: $DISK_GB GB"
            echo "  SSH Port: $SSH_PORT"
        fi
    else
        print_status "INFO" "VM is not running"
    fi
    
    echo
    read -rp "$(print_status "INPUT" "Press Enter to continue...")"
}

show_system_monitor() {
    print_header
    print_status "HEADER" "📊 System Monitor"
    echo
    
    # CPU usage
    echo "🖥️ CPU Usage:"
    echo "  Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo "  CPU Cores: $(nproc)"
    echo
    
    # Memory usage
    echo "🧠 Memory Usage:"
    free -h | awk '
        /^Mem:/ {
            total=$2
            used=$3
            free=$4
            printf "  Total: %s | Used: %s | Free: %s\n", total, used, free
        }
    '
    echo
    
    # Disk usage
    echo "💾 Disk Usage:"
    df -h / | awk '
        NR==2 {
            total=$2
            used=$3
            free=$4
            used_percent=$5
            printf "  Total: %s | Used: %s (%s) | Free: %s\n", total, used, used_percent, free
        }
    '
    echo
    
    # Network interfaces
    echo "🌐 Network Interfaces:"
    ip -brief addr show | head -10
    echo
    
    # Running VMs
    echo "⚡ Running VMs:"
    local running_count=0
    if [ -d "$DATA_DIR/vms" ]; then
        for conf in "$DATA_DIR/vms"/*.conf; do
            if [ -f "$conf" ]; then
                local vm_name
                vm_name=$(basename "$conf" .conf)
                local pid_file="/tmp/zynexforge_${vm_name}.pid"
                if [ -f "$pid_file" ]; then
                    local pid
                    pid=$(cat "$pid_file" 2>/dev/null)
                    if ps -p "$pid" > /dev/null 2>&1; then
                        echo "  • $vm_name (PID: $pid)"
                        running_count=$((running_count + 1))
                    fi
                fi
            fi
        done
    fi
    echo "  Total Running: $running_count"
    echo
    
    read -rp "$(print_status "INPUT" "Press Enter to continue...")"
}

# =============================================================================
# ACCESS FUNCTIONS
# =============================================================================

show_vm_access() {
    local vm_name="$1"
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    source "$vm_config"
    
    print_status "HEADER" "🔗 Access Information: $vm_name"
    echo
    echo "📋 VM Details:"
    echo "══════════════════════════════════════════"
    echo "  VM Name: $VM_NAME"
    echo "  SSH Port: $SSH_PORT"
    echo "  Username: $VM_USER"
    echo "  Password: [hidden for security]"
    echo
    echo "🔗 SSH Commands:"
    echo "══════════════════════════════════════════"
    echo "  ssh -p $SSH_PORT $VM_USER@localhost"
    echo "  ssh -o StrictHostKeyChecking=no -p $SSH_PORT $VM_USER@localhost"
    echo "  ssh -i $SSH_KEY_FILE -p $SSH_PORT $VM_USER@localhost"
    echo
    echo "📁 Files:"
    echo "══════════════════════════════════════════"
    echo "  Configuration: $vm_config"
    echo "  Disk Image: $DISK_PATH"
    echo "  Cloud-init: $CLOUDINIT_DIR"
    echo
    
    read -rp "$(print_status "INPUT" "Auto-connect now? (y/N): ")" connect_now
    if [[ "$connect_now" =~ ^[Yy]$ ]]; then
        print_status "INFO" "Connecting to $vm_name..."
        ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$VM_USER@localhost"
    fi
}

# =============================================================================
# MAIN MENU FUNCTIONS
# =============================================================================

main_menu() {
    while true; do
        print_header
        print_status "HEADER" "Main Menu"
        echo
        
        echo "  1) ⚡ KVM + QEMU VM Cloud"
        echo "  2) 🖥️ QEMU VM Cloud (Universal)"
        echo "  3) 🧊 LXD Cloud (VMs/Containers)"
        echo "  4) 🐳 Docker VM Cloud (Container VPS)"
        echo "  5) 🔬 Jupyter Cloud Lab"
        echo "  6) 📦 Templates + ISO Library"
        echo "  7) 🛡️ Security & Authentication"
        echo "  8) 📊 Monitoring & Analytics"
        echo "  9) 💾 Backup & Snapshots"
        echo "  10) ⚙️ VM Manager (Lifecycle Menu)"
        echo "  11) 🌐 Nodes & Clusters"
        echo "  12) 🔧 System Configuration"
        echo "  13) ℹ️ System Information"
        echo "  0) ❌ Exit"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case "$choice" in
            1) kvm_qemu_menu ;;
            2) qemu_universal_menu ;;
            3) lxd_cloud_menu ;;
            4) docker_vm_menu ;;
            5) jupyter_cloud_menu ;;
            6) templates_menu ;;
            7) security_menu ;;
            8) monitoring_menu ;;
            9) backup_menu ;;
            10) vm_manager_menu ;;
            11) nodes_menu ;;
            12) config_menu ;;
            13) system_info_menu ;;
            0) 
                print_status "INFO" "Exiting ZynexForge CloudStack™ Ultimate Edition"
                echo -e "${GREEN}Thank you for using our platform!${NC}"
                exit 0
                ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
    done
}

# Module menus
kvm_qemu_menu() {
    print_header
    print_status "HEADER" "⚡ KVM + QEMU VM Cloud"
    echo
    print_status "INFO" "Hardware-accelerated virtualization with KVM."
    echo
    echo "  1) Create KVM VM"
    echo "  2) Start KVM VM"
    echo "  3) Stop KVM VM"
    echo "  4) List KVM VMs"
    echo "  5) Performance Monitor"
    echo "  0) Back"
    echo
    
    read -rp "$(print_status "INPUT" "Select option: ")" choice
    
    case "$choice" in
        1) vm_create_wizard ;;
        2)
            read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
            start_vm "$vm_name"
            ;;
        3)
            read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
            stop_vm "$vm_name"
            ;;
        4) list_vms ;;
        5)
            read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
            show_vm_performance "$vm_name"
            ;;
        0) return ;;
        *) print_status "ERROR" "Invalid option" ;;
    esac
}

docker_vm_menu() {
    while true; do
        print_header
        print_status "HEADER" "🐳 Docker VM Cloud"
        echo
        
        echo "  1) Create Docker VM"
        echo "  2) Start Docker VM"
        echo "  3) Stop Docker VM"
        echo "  4) Docker VM Console"
        echo "  5) List Docker VMs"
        echo "  6) Docker VM Info"
        echo "  7) Delete Docker VM"
        echo "  8) Docker System Info"
        echo "  0) Back"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case "$choice" in
            1) create_docker_vm ;;
            2)
                read -rp "$(print_status "INPUT" "Docker VM Name: ")" dv_name
                docker start "$dv_name" 2>/dev/null && print_status "SUCCESS" "Started $dv_name"
                ;;
            3)
                read -rp "$(print_status "INPUT" "Docker VM Name: ")" dv_name
                docker stop "$dv_name" 2>/dev/null && print_status "SUCCESS" "Stopped $dv_name"
                ;;
            4)
                read -rp "$(print_status "INPUT" "Docker VM Name: ")" dv_name
                docker exec -it "$dv_name" /bin/bash || docker exec -it "$dv_name" /bin/sh
                ;;
            5) docker ps -a ;;
            6)
                read -rp "$(print_status "INPUT" "Docker VM Name: ")" dv_name
                docker inspect "$dv_name" | jq . 2>/dev/null || docker inspect "$dv_name"
                ;;
            7)
                read -rp "$(print_status "INPUT" "Docker VM Name: ")" dv_name
                docker rm -f "$dv_name" 2>/dev/null && print_status "SUCCESS" "Deleted $dv_name"
                ;;
            8) docker info ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        [ "$choice" -ne 0 ] && read -rp "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

jupyter_cloud_menu() {
    while true; do
        print_header
        print_status "HEADER" "🔬 Jupyter Cloud Lab"
        echo
        
        echo "  1) Create Jupyter Lab"
        echo "  2) List Jupyter Labs"
        echo "  3) Stop Jupyter Lab"
        echo "  4) Start Jupyter Lab"
        echo "  5) Show Jupyter URL"
        echo "  6) Delete Jupyter Lab"
        echo "  7) Jupyter Lab Stats"
        echo "  0) Back"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case "$choice" in
            1) create_jupyter_vm ;;
            2)
                echo "Jupyter Labs:"
                docker ps -a --filter "ancestor=jupyter" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                ;;
            3)
                read -rp "$(print_status "INPUT" "Jupyter Lab Name: ")" jv_name
                docker stop "$jv_name" 2>/dev/null && print_status "SUCCESS" "Stopped $jv_name"
                ;;
            4)
                read -rp "$(print_status "INPUT" "Jupyter Lab Name: ")" jv_name
                docker start "$jv_name" 2>/dev/null && print_status "SUCCESS" "Started $jv_name"
                ;;
            5)
                read -rp "$(print_status "INPUT" "Jupyter Lab Name: ")" jv_name
                local config="$DATA_DIR/jupyter/${jv_name}.conf"
                if [ -f "$config" ]; then
                    source "$config"
                    echo "URL: http://localhost:$JV_PORT/?token=$JV_TOKEN"
                else
                    print_status "ERROR" "Jupyter Lab not found"
                fi
                ;;
            6)
                read -rp "$(print_status "INPUT" "Jupyter Lab Name: ")" jv_name
                docker rm -f "$jv_name" 2>/dev/null && docker volume rm "${jv_name}_data" 2>/dev/null
                rm -f "$DATA_DIR/jupyter/${jv_name}.conf"
                print_status "SUCCESS" "Deleted $jv_name"
                ;;
            7)
                echo "Jupyter Lab Statistics:"
                docker stats --no-stream $(docker ps --filter "ancestor=jupyter" --format "{{.Names}}") 2>/dev/null || echo "No Jupyter labs running"
                ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        [ "$choice" -ne 0 ] && read -rp "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

vm_manager_menu() {
    while true; do
        print_header
        print_status "HEADER" "⚙️ VM Manager"
        echo
        
        echo "  1) Create a VM"
        echo "  2) Start a VM"
        echo "  3) Stop a VM"
        echo "  4) Restart a VM"
        echo "  5) Show VM Info"
        echo "  6) Edit VM Configuration"
        echo "  7) Delete a VM"
        echo "  8) Resize VM Disk"
        echo "  9) Show VM Performance"
        echo "  10) Access VM (SSH)"
        echo "  11) Clone VM"
        echo "  12) Migrate VM"
        echo "  0) Back"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case "$choice" in
            1) vm_create_wizard ;;
            2)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                start_vm "$vm_name"
                ;;
            3)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                stop_vm "$vm_name"
                ;;
            4)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                stop_vm "$vm_name"
                sleep 2
                start_vm "$vm_name"
                ;;
            5)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                show_vm_access "$vm_name"
                ;;
            6)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                edit_vm_config "$vm_name"
                ;;
            7)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                delete_vm "$vm_name"
                ;;
            8)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                resize_vm_disk "$vm_name"
                ;;
            9)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                show_vm_performance "$vm_name"
                ;;
            10)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                ssh -o StrictHostKeyChecking=no -p "$(grep SSH_PORT "$DATA_DIR/vms/${vm_name}.conf" | cut -d= -f2 | tr -d '\"')" \
                    "$(grep VM_USER "$DATA_DIR/vms/${vm_name}.conf" | cut -d= -f2 | tr -d '\"')@localhost" || true
                ;;
            11)
                read -rp "$(print_status "INPUT" "Source VM Name: ")" source_vm
                read -rp "$(print_status "INPUT" "New VM Name: ")" new_vm
                clone_vm "$source_vm" "$new_vm"
                ;;
            12)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                read -rp "$(print_status "INPUT" "Target Node ID: ")" target_node
                migrate_vm "$vm_name" "$target_node"
                ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        [ "$choice" -ne 0 ] && sleep 1
    done
}

backup_menu() {
    while true; do
        print_header
        print_status "HEADER" "💾 Backup & Snapshots"
        echo
        
        echo "  1) Backup VM"
        echo "  2) Restore VM from Backup"
        echo "  3) Create Snapshot"
        echo "  4) Restore from Snapshot"
        echo "  5) List Backups"
        echo "  6) List Snapshots"
        echo "  7) Delete Old Backups"
        echo "  8) Schedule Auto-backup"
        echo "  0) Back"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case "$choice" in
            1)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                backup_vm "$vm_name"
                ;;
            2)
                read -rp "$(print_status "INPUT" "Backup File: ")" backup_file
                restore_backup "$backup_file"
                ;;
            3)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                create_snapshot "$vm_name"
                ;;
            4)
                read -rp "$(print_status "INPUT" "Snapshot Name: ")" snapshot_name
                restore_snapshot "$snapshot_name"
                ;;
            5)
                echo "Backup Files:"
                find "$DATA_DIR/backups" -name "*.tar.gz" -type f 2>/dev/null | sort
                ;;
            6)
                echo "Snapshots:"
                find "$DATA_DIR/snapshots" -name "*.info" -type f 2>/dev/null | sort
                ;;
            7)
                find "$DATA_DIR/backups" -name "*.tar.gz" -mtime +30 -delete 2>/dev/null
                print_status "SUCCESS" "Deleted backups older than 30 days"
                ;;
            8)
                read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
                read -rp "$(print_status "INPUT" "Schedule (cron format): ")" cron_schedule
                schedule_backup "$vm_name" "$cron_schedule"
                ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        [ "$choice" -ne 0 ] && read -rp "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

monitoring_menu() {
    while true; do
        print_header
        print_status "HEADER" "📊 Monitoring & Analytics"
        echo
        
        echo "  1) System Overview"
        echo "  2) VM Resources"
        echo "  3) Docker Resources"
        echo "  4) Disk Usage"
        echo "  5) Network Statistics"
        echo "  6) Performance Dashboard"
        echo "  7) Log Viewer"
        echo "  8) Alert Configuration"
        echo "  0) Back"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case "$choice" in
            1) show_system_monitor ;;
            2)
                echo "VM Resources:"
                if [ -d "$DATA_DIR/vms" ]; then
                    for conf in "$DATA_DIR/vms"/*.conf; do
                        [ -f "$conf" ] && source "$conf"
                        echo "  $VM_NAME: CPU ${CPU_CORES}v, RAM ${RAM_MB}MB, Disk ${DISK_GB}GB"
                    done
                fi
                ;;
            3)
                echo "Docker Resources:"
                docker stats --no-stream 2>/dev/null || echo "Docker not available"
                ;;
            4)
                echo "Disk Usage:"
                df -h
                ;;
            5)
                echo "Network Statistics:"
                ifconfig || ip addr show
                ;;
            6)
                print_status "INFO" "Performance Dashboard"
                htop 2>/dev/null || top
                ;;
            7)
                print_status "INFO" "Log Viewer"
                tail -f "$LOG_FILE"
                ;;
            8)
                print_status "INFO" "Alert Configuration"
                configure_alerts
                ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        [ "$choice" -ne 0 ] && read -rp "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# =============================================================================
# HELPER FUNCTIONS FOR OTHER MENUS
# =============================================================================

list_vms() {
    print_header
    print_status "HEADER" "📋 Virtual Machines"
    echo
    
    if [ -d "$DATA_DIR/vms" ] && ls "$DATA_DIR/vms"/*.conf 2>/dev/null | grep -q .; then
        echo "Virtual Machines:"
        echo "══════════════════════════════════════════"
        for conf in "$DATA_DIR/vms"/*.conf; do
            [ -f "$conf" ] && source "$conf"
            local status="stopped"
            local pid_file="/tmp/zynexforge_${VM_NAME}.pid"
            if [ -f "$pid_file" ]; then
                local pid
                pid=$(cat "$pid_file" 2>/dev/null)
                if ps -p "$pid" > /dev/null 2>&1; then
                    status="running"
                fi
            fi
            echo "  • $VM_NAME [$NODE_ID] - Status: $status"
            echo "    CPU: ${CPU_CORES}v | RAM: ${RAM_MB}MB | Disk: ${DISK_GB}GB | SSH: $SSH_PORT"
        done
    else
        print_status "INFO" "No VMs configured"
    fi
    
    echo
    read -rp "$(print_status "INPUT" "Press Enter to continue...")"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Show welcome message
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo "   ZynexForge CloudStack™ Ultimate Edition - Version ${SCRIPT_VERSION}"
    echo "================================================================"
    echo -e "${NC}"
    print_status "INFO" "🔥 Made by FaaizXD"
    echo
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_status "WARNING" "Running as root is not recommended!"
        print_status "INFO" "This script is designed to run as a regular user."
        read -rp "$(print_status "INPUT" "Continue anyway? (y/N): ")" continue_as_root
        if [[ ! "$continue_as_root" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Initialize platform
    initialize_platform
    
    # Start main menu
    main_menu
}

# Handle script arguments
case "${1:-}" in
    "init"|"setup")
        initialize_platform
        print_status "SUCCESS" "Platform initialized"
        ;;
    "start")
        shift
        start_vm "$@"
        ;;
    "stop")
        shift
        stop_vm "$@"
        ;;
    "list-vms")
        list_vms
        ;;
    "list-nodes")
        list_nodes_simple
        ;;
    "status")
        print_header
        ;;
    "backup")
        shift
        backup_vm "$@"
        ;;
    "restore")
        shift
        restore_backup "$@"
        ;;
    "monitor")
        show_system_monitor
        ;;
    "help"|"--help"|"-h")
        cat << EOF
Usage: $0 [command] [arguments]

Commands:
  init, setup      Initialize the platform
  start <vm>       Start a VM
  stop <vm>        Stop a VM
  list-vms         List all virtual machines
  list-nodes       List all nodes
  backup <vm>      Backup a VM
  restore <file>   Restore from backup
  monitor          Show system monitor
  status           Show platform status
  help             Show this help message

Without arguments: Start interactive menu

Examples:
  $0 start my-vm
  $0 backup my-vm
  $0 list-vms
EOF
        ;;
    *)
        # Start the platform
        main "$@"
        ;;
esac
