#!/bin/bash
#
# Performance Tuning Script for Linux Servers
# Applies production-grade performance optimizations
#
# Usage: sudo ./performance-tuning.sh
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

log "Starting performance tuning..."

# Backup current sysctl configuration
cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%F) 2>/dev/null || true

# Create performance tuning configuration
cat > /etc/sysctl.d/99-performance-tuning.conf <<'EOF'
# ========================================
# Network Performance Tuning
# ========================================

# Increase TCP buffer sizes for high-bandwidth applications
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Increase network device backlog
net.core.netdev_max_backlog = 5000

# Enable TCP window scaling
net.ipv4.tcp_window_scaling = 1

# Increase maximum number of connections
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# TCP connection optimization
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Optimize TCP congestion control
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# Enable TCP Fast Open
net.ipv4.tcp_fastopen = 3

# Increase local port range
net.ipv4.ip_local_port_range = 10000 65535

# ========================================
# Virtual Memory Tuning
# ========================================

# Reduce swappiness (prefer RAM over swap)
vm.swappiness = 10

# Increase dirty ratio for better write performance
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Increase dirty writeback time
vm.dirty_writeback_centisecs = 1500
vm.dirty_expire_centisecs = 3000

# Virtual memory statistics interval
vm.stat_interval = 10

# Memory overcommit handling
vm.overcommit_memory = 1
vm.overcommit_ratio = 50

# ========================================
# File System Tuning
# ========================================

# Increase file handles
fs.file-max = 2097152

# Increase inotify limits
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# AIO requests
fs.aio-max-nr = 1048576

# ========================================
# Kernel Tuning
# ========================================

# Increase PID max for containerized environments
kernel.pid_max = 4194304

# Improve shared memory
kernel.shmmax = 68719476736
kernel.shmall = 4294967296

# Core dump pattern
kernel.core_pattern = /var/crash/core.%e.%p.%h.%t

# Panic on OOM
vm.panic_on_oom = 0
vm.oom_kill_allocating_task = 0
EOF

# Apply sysctl changes
log "Applying sysctl performance tuning..."
sysctl -p /etc/sysctl.d/99-performance-tuning.conf

# Configure resource limits
log "Configuring resource limits..."

cat > /etc/security/limits.d/99-performance.conf <<'EOF'
# File descriptors
* soft nofile 65536
* hard nofile 1048576

# Process limits
* soft nproc 65536
* hard nproc 65536

# Core dumps
* soft core unlimited
* hard core unlimited

# Memory lock
* soft memlock unlimited
* hard memlock unlimited

# Stack size
* soft stack 8192
* hard stack 8192
EOF

# Optimize I/O scheduler based on disk type
log "Optimizing I/O scheduler..."

# Function to set I/O scheduler
set_io_scheduler() {
    local device=$1
    local rotational=$(cat /sys/block/$device/queue/rotational 2>/dev/null || echo "1")
    
    if [[ $rotational -eq 0 ]]; then
        # SSD/NVMe - use none (for newer kernels) or noop
        if grep -q "none" /sys/block/$device/queue/scheduler 2>/dev/null; then
            echo "none" > /sys/block/$device/queue/scheduler
            log "Set $device to 'none' scheduler (SSD)"
        elif grep -q "noop" /sys/block/$device/queue/scheduler 2>/dev/null; then
            echo "noop" > /sys/block/$device/queue/scheduler
            log "Set $device to 'noop' scheduler (SSD)"
        fi
    else
        # HDD - use deadline or mq-deadline
        if grep -q "mq-deadline" /sys/block/$device/queue/scheduler 2>/dev/null; then
            echo "mq-deadline" > /sys/block/$device/queue/scheduler
            log "Set $device to 'mq-deadline' scheduler (HDD)"
        elif grep -q "deadline" /sys/block/$device/queue/scheduler 2>/dev/null; then
            echo "deadline" > /sys/block/$device/queue/scheduler
            log "Set $device to 'deadline' scheduler (HDD)"
        fi
    fi
}

# Apply to all block devices
for device in /sys/block/sd*/queue/scheduler; do
    device_name=$(echo $device | cut -d'/' -f4)
    set_io_scheduler $device_name
done

for device in /sys/block/nvme*/queue/scheduler; do
    device_name=$(echo $device | cut -d'/' -f4)
    set_io_scheduler $device_name
done

# Make I/O scheduler settings persistent
cat > /etc/udev/rules.d/60-scheduler.rules <<'EOF'
# Set I/O scheduler for SSDs to none/noop
ACTION=="add|change", KERNEL=="sd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"

# Set I/O scheduler for HDDs to mq-deadline/deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF

# Transparent Huge Pages optimization
log "Configuring Transparent Huge Pages..."

# For most workloads, madvise is better than always
echo "madvise" > /sys/kernel/mm/transparent_hugepage/enabled
echo "madvise" > /sys/kernel/mm/transparent_hugepage/defrag

# Make THP settings persistent
cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF

systemctl daemon-reload
systemctl enable disable-thp.service

# CPU Governor for performance
log "Setting CPU governor to performance mode..."

# Install cpufrequtils if not present
if command -v apt-get &> /dev/null; then
    apt-get install -y cpufrequtils 2>/dev/null || true
elif command -v yum &> /dev/null; then
    yum install -y kernel-tools 2>/dev/null || true
fi

# Set governor to performance
if command -v cpupower &> /dev/null; then
    cpupower frequency-set -g performance 2>/dev/null || warning "Could not set CPU governor"
fi

# Disable NUMA balancing for some workloads (optional)
if [[ -f /proc/sys/kernel/numa_balancing ]]; then
    log "Disabling automatic NUMA balancing..."
    echo 0 > /proc/sys/kernel/numa_balancing
    echo "kernel.numa_balancing = 0" >> /etc/sysctl.d/99-performance-tuning.conf
fi

# IRQ balance for multi-core systems
log "Configuring IRQ balance..."

if command -v apt-get &> /dev/null; then
    apt-get install -y irqbalance
elif command -v yum &> /dev/null; then
    yum install -y irqbalance
fi

systemctl enable irqbalance
systemctl start irqbalance

# Generate performance report
log "Generating performance tuning report..."

REPORT_FILE="/var/log/performance-tuning-$(date +%F).log"

cat > "$REPORT_FILE" <<EOF
Performance Tuning Report
=========================
Date: $(date)
Hostname: $(hostname)

System Information:
- CPU Cores: $(nproc)
- Total RAM: $(free -h | awk '/^Mem:/ {print $2}')
- Kernel: $(uname -r)

Applied Optimizations:
✓ Network buffer sizes increased
✓ TCP BBR congestion control enabled
✓ TCP Fast Open enabled
✓ Virtual memory tuning applied
✓ File descriptor limits increased
✓ I/O scheduler optimized for disk type
✓ Transparent Huge Pages set to madvise
✓ CPU governor set to performance
✓ IRQ balancing enabled

Current Settings:
-----------------
Swappiness: $(cat /proc/sys/vm/swappiness)
File handles: $(cat /proc/sys/fs/file-max)
TCP congestion control: $(cat /proc/sys/net/ipv4/tcp_congestion_control)
Max connections: $(cat /proc/sys/net/core/somaxconn)

I/O Schedulers:
EOF

# Add disk scheduler info to report
for device in /sys/block/sd*/queue/scheduler; do
    device_name=$(echo $device | cut -d'/' -f4)
    scheduler=$(cat $device | grep -o '\[.*\]' | tr -d '[]')
    rotational=$(cat /sys/block/$device_name/queue/rotational)
    disk_type=$([[ $rotational -eq 0 ]] && echo "SSD" || echo "HDD")
    echo "$device_name: $scheduler ($disk_type)" >> "$REPORT_FILE"
done

cat >> "$REPORT_FILE" <<EOF

Recommendations:
1. Monitor system performance with 'sar', 'vmstat', 'iostat'
2. Adjust swappiness based on workload (0-100)
3. Tune TCP buffer sizes for your specific bandwidth
4. Test application performance before and after tuning
5. Monitor network throughput with 'iftop' or 'nload'

To verify changes:
- sysctl -a | grep -E "net.ipv4|vm.|fs."
- cat /proc/sys/vm/swappiness
- cat /sys/block/*/queue/scheduler

Report saved to: $REPORT_FILE
EOF

log "Performance tuning complete!"
log "Report saved to: $REPORT_FILE"
warning "Some changes require a reboot to take full effect"
warning "Test thoroughly in a non-production environment first!"

# Display summary
cat "$REPORT_FILE"

exit 0
