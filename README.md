# 🚀 ZynexForge VM Platform

**ZynexForge VM** is an advanced, menu-driven virtualization script built on **QEMU + KVM**, designed to feel like a real VPS / cloud platform.  
It provides a clean **terminal UI**, **real location-based VM management**, and **production-ready features** — all from a single Bash script.

---

## ✨ Key Highlights

- ⚡ **Real Virtual Machines (QEMU + KVM)**
- 🌍 **Real Location System** (India, Singapore, USA, Germany & more)
- 🧠 **Smart Interactive UI** (easy menus, clean prompts)
- 🖥️ **GUI & Headless VM Support**
- 🔐 **Cloud-init based login (root + user)**
- 📦 **Multiple Linux OS Templates**
- 🔄 **Edit VM resources anytime**
- 📊 **Live VM performance monitoring**
- 🗂️ **Per-location node storage system**
- 🧹 **Clean config-based VM management**

---

## 🌍 Real Location System (Important)

ZynexForge does **NOT** fake locations.

Each location maps to a **real node directory**, just like enterprise cloud providers:

- India  
- Singapore  
- Germany  
- USA  
- UK  
- Japan  
- UAE  
- Canada  
- Australia  
- More can be added easily  

Every VM:
- Is created inside its selected location
- Keeps disks, configs, and seeds isolated
- Can be moved between locations safely

---

## 🖥️ Supported Operating Systems

- Ubuntu 22.04 / 24.04  
- Debian 11 / 12  
- Fedora 40  
- AlmaLinux 9  
- Rocky Linux 9  
- CentOS Stream 9  

All images are **official cloud images**.

---

## 🧰 Features Overview

### VM Lifecycle
- Create VM
- Start VM
- Stop VM
- Delete VM
- Resize disk
- Edit CPU / RAM / Ports
- Change VM location
- Enable / Disable GUI mode

### Networking
- SSH port isolation
- Port forwarding support
- Collision detection

### Performance
- VirtIO drivers
- RNG acceleration
- Balloon memory device
- Host CPU passthrough

---

## 📥 One-Command Installation

Run the platform using a single command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ZynexForge/vm/main/vm.sh)


📁 File Structure
~/.zynexforge/
 └── nodes/
     ├── india/
     ├── singapore/
     ├── usa/
     ├── germany/
     └── ...
~/vms/
 └── *.conf   # VM configuration files
Each VM has:
Dedicated disk image
Cloud-init seed ISO
Persistent config file
🎯 Who Is This For?
Developers
Homelab users
VPS builders
Cloud learners
Automation enthusiasts
Anyone who wants real VM control without panels
🛡️ Stability & Safety
Strict Bash mode enabled
Input validation everywhere
Safe cleanup on exit
Dependency checks before execution
No silent failures
🧩 Customization
You can easily:
Add new locations
Add new OS images
Integrate billing / APIs
Build a web or Discord panel on top
Convert it into a full cloud platform
📜 License
This project is intended for educational, development, and infrastructure experimentation purposes.
⭐ Branding
ZynexForge™
Advanced VM Virtualization Platform
Built for power, clarity, and control.
If you like this project, consider ⭐ starring the repository.
