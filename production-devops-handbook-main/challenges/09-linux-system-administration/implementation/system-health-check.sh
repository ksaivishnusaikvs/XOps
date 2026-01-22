#!/bin/bash
#
# System Health Check Script
# Monitors system resources and alerts on issues
#
# Usage: ./system-health-check.sh
#

set -euo pipefail

# Configuration
ALERT_CPU_THRESHOLD=80
ALERT_MEMORY_THRESHOLD=85
ALERT_DISK_THRESHOLD=85
ALERT_LOAD_THRESHOLD=4.0
ALERT_EMAIL="admin@example.com"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Output file
REPORT_FILE="/var/log/health-check-$(date +%F-%H%M%S).log"

# Start report
exec > >(tee -a "$REPORT_FILE")
exec 2>&1

echo "========================================="
echo "System Health Check Report"
echo "========================================="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo ""

# Track if any issues found
ISSUES_FOUND=0

# Function to check and alert
check_threshold() {
    local value=$1
    local threshold=$2
    local metric=$3
    
    if (( $(echo "$value > $threshold" | bc -l) )); then
        echo -e "${RED}[ALERT]${NC} $metric is at ${value}% (threshold: ${threshold}%)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    else
        echo -e "${GREEN}[OK]${NC} $metric is at ${value}%"
        return 0
    fi
}

# 1. CPU Usage
echo "========================================="
echo "CPU Usage"
echo "========================================="

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
CPU_CORES=$(nproc)

echo "CPU Cores: $CPU_CORES"
echo "CPU Usage: ${CPU_USAGE}%"

check_threshold "$CPU_USAGE" "$ALERT_CPU_THRESHOLD" "CPU usage"

# Top CPU processes
echo ""
echo "Top 5 CPU consuming processes:"
ps aux --sort=-%cpu | head -6 | awk '{printf "%-10s %-8s %-6s %-6s %s\n", $1, $2, $3, $4, $11}'
echo ""

# 2. Memory Usage
echo "========================================="
echo "Memory Usage"
echo "========================================="

MEMORY_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEMORY_USED=$(free -m | awk 'NR==2{print $3}')
MEMORY_FREE=$(free -m | awk 'NR==2{print $4}')
MEMORY_AVAILABLE=$(free -m | awk 'NR==2{print $7}')
MEMORY_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($MEMORY_USED/$MEMORY_TOTAL)*100}")

echo "Total Memory: ${MEMORY_TOTAL}M"
echo "Used Memory: ${MEMORY_USED}M"
echo "Free Memory: ${MEMORY_FREE}M"
echo "Available Memory: ${MEMORY_AVAILABLE}M"
echo "Memory Usage: ${MEMORY_PERCENT}%"

check_threshold "$MEMORY_PERCENT" "$ALERT_MEMORY_THRESHOLD" "Memory usage"

# Top memory processes
echo ""
echo "Top 5 memory consuming processes:"
ps aux --sort=-%mem | head -6 | awk '{printf "%-10s %-8s %-6s %-6s %s\n", $1, $2, $3, $4, $11}'
echo ""

# Swap usage
SWAP_TOTAL=$(free -m | awk 'NR==3{print $2}')
if [[ $SWAP_TOTAL -gt 0 ]]; then
    SWAP_USED=$(free -m | awk 'NR==3{print $3}')
    SWAP_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($SWAP_USED/$SWAP_TOTAL)*100}")
    echo "Swap Usage: ${SWAP_USED}M / ${SWAP_TOTAL}M (${SWAP_PERCENT}%)"
    
    if (( $(echo "$SWAP_PERCENT > 50" | bc -l) )); then
        echo -e "${YELLOW}[WARNING]${NC} High swap usage detected"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi
echo ""

# 3. Disk Usage
echo "========================================="
echo "Disk Usage"
echo "========================================="

while IFS= read -r line; do
    FILESYSTEM=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    USED=$(echo "$line" | awk '{print $3}')
    AVAIL=$(echo "$line" | awk '{print $4}')
    PERCENT=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $6}')
    
    echo "Filesystem: $FILESYSTEM"
    echo "Mount: $MOUNT"
    echo "Size: $SIZE | Used: $USED | Available: $AVAIL"
    
    check_threshold "$PERCENT" "$ALERT_DISK_THRESHOLD" "Disk usage on $MOUNT"
    echo ""
done < <(df -h | grep -E '^/dev/' | grep -v '/boot')

# Inode usage
echo "Inode Usage:"
df -i | grep -E '^/dev/' | while read -r line; do
    FILESYSTEM=$(echo "$line" | awk '{print $1}')
    IUSED=$(echo "$line" | awk '{print $3}')
    IFREE=$(echo "$line" | awk '{print $4}')
    IPERCENT=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $6}')
    
    echo "  $MOUNT: ${IPERCENT}% (Used: $IUSED, Free: $IFREE)"
    
    if [[ $IPERCENT -gt 85 ]]; then
        echo -e "  ${RED}[ALERT]${NC} High inode usage on $MOUNT"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
done
echo ""

# 4. System Load
echo "========================================="
echo "System Load"
echo "========================================="

LOAD_1MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | xargs)
LOAD_5MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $2}' | xargs)
LOAD_15MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $3}' | xargs)

echo "Load Average: $LOAD_1MIN (1min) | $LOAD_5MIN (5min) | $LOAD_15MIN (15min)"
echo "CPU Cores: $CPU_CORES"

LOAD_PER_CORE=$(awk "BEGIN {printf \"%.2f\", $LOAD_1MIN / $CPU_CORES}")
echo "Load per core: $LOAD_PER_CORE"

if (( $(echo "$LOAD_PER_CORE > $ALERT_LOAD_THRESHOLD" | bc -l) )); then
    echo -e "${RED}[ALERT]${NC} High load average detected"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "${GREEN}[OK]${NC} Load is normal"
fi
echo ""

# 5. Network Connectivity
echo "========================================="
echo "Network Status"
echo "========================================="

# Check internet connectivity
if ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} Internet connectivity is working"
else
    echo -e "${RED}[ALERT]${NC} No internet connectivity"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check DNS
if nslookup google.com &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} DNS resolution is working"
else
    echo -e "${RED}[ALERT]${NC} DNS resolution failed"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Network interfaces
echo ""
echo "Network Interfaces:"
ip -brief addr show | while read -r line; do
    echo "  $line"
done
echo ""

# Active connections
ESTABLISHED=$(ss -tan | grep ESTAB | wc -l)
TIME_WAIT=$(ss -tan | grep TIME-WAIT | wc -l)
echo "Active connections: $ESTABLISHED (ESTABLISHED), $TIME_WAIT (TIME-WAIT)"
echo ""

# 6. Service Status
echo "========================================="
echo "Critical Services"
echo "========================================="

# List of critical services to check
SERVICES=(
    "sshd"
    "cron"
    "rsyslog"
)

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} $service is running"
    else
        echo -e "${RED}[ALERT]${NC} $service is not running"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
done
echo ""

# 7. Failed Login Attempts
echo "========================================="
echo "Security Check"
echo "========================================="

if [[ -f /var/log/auth.log ]]; then
    FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -20 | wc -l)
    echo "Recent failed login attempts: $FAILED_LOGINS"
    
    if [[ $FAILED_LOGINS -gt 10 ]]; then
        echo -e "${YELLOW}[WARNING]${NC} High number of failed login attempts"
        echo "Last 5 failed attempts:"
        grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5
    fi
elif [[ -f /var/log/secure ]]; then
    FAILED_LOGINS=$(grep "Failed password" /var/log/secure 2>/dev/null | tail -20 | wc -l)
    echo "Recent failed login attempts: $FAILED_LOGINS"
    
    if [[ $FAILED_LOGINS -gt 10 ]]; then
        echo -e "${YELLOW}[WARNING]${NC} High number of failed login attempts"
        echo "Last 5 failed attempts:"
        grep "Failed password" /var/log/secure 2>/dev/null | tail -5
    fi
fi
echo ""

# 8. Disk I/O
echo "========================================="
echo "Disk I/O Statistics"
echo "========================================="

if command -v iostat &> /dev/null; then
    iostat -x 1 2 | tail -n +4
else
    echo "iostat not available (install sysstat package)"
fi
echo ""

# 9. System Updates
echo "========================================="
echo "System Updates"
echo "========================================="

if command -v apt-get &> /dev/null; then
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
    echo "Available updates: $UPDATES"
    
    if [[ $UPDATES -gt 0 ]]; then
        echo -e "${YELLOW}[INFO]${NC} System updates available"
    fi
elif command -v yum &> /dev/null; then
    UPDATES=$(yum check-update --quiet | grep -v "^$" | wc -l || true)
    echo "Available updates: $UPDATES"
    
    if [[ $UPDATES -gt 0 ]]; then
        echo -e "${YELLOW}[INFO]${NC} System updates available"
    fi
fi
echo ""

# 10. Summary
echo "========================================="
echo "Summary"
echo "========================================="

if [[ $ISSUES_FOUND -eq 0 ]]; then
    echo -e "${GREEN}✓ All health checks passed${NC}"
    echo "No issues detected"
else
    echo -e "${RED}✗ $ISSUES_FOUND issue(s) detected${NC}"
    echo "Please review the alerts above"
fi

echo ""
echo "Report saved to: $REPORT_FILE"
echo "========================================="

# Send email notification if issues found
if [[ $ISSUES_FOUND -gt 0 ]] && command -v mail &> /dev/null; then
    mail -s "System Health Alert: $(hostname) - $ISSUES_FOUND issues" "$ALERT_EMAIL" < "$REPORT_FILE"
fi

# Exit with error code if issues found
exit $ISSUES_FOUND
