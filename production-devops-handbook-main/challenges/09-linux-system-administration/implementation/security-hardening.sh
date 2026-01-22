#!/bin/bash
#
# Security Hardening Script for Linux Servers
# Applies CIS benchmark recommendations and security best practices
#
# Usage: sudo ./security-hardening.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    error "Cannot detect OS"
    exit 1
fi

log "Starting security hardening for $OS..."

# 1. SSH Hardening
log "Configuring SSH security..."

# Backup original sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%F)

# Apply SSH hardening
cat > /etc/ssh/sshd_config.d/hardening.conf <<'EOF'
# SSH Hardening Configuration
Protocol 2
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60
AllowUsers *@*
AllowGroups sudo admin

# Ciphers and algorithms
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
EOF

# Test SSH configuration
if sshd -t; then
    log "SSH configuration is valid"
    systemctl reload sshd
else
    error "SSH configuration test failed, reverting..."
    rm /etc/ssh/sshd_config.d/hardening.conf
    exit 1
fi

# 2. Firewall Configuration
log "Configuring firewall..."

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    # Install and configure UFW
    apt-get update
    apt-get install -y ufw
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow 22/tcp
    
    # Enable firewall
    echo "y" | ufw enable
    ufw status verbose
    
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" ]]; then
    # Configure firewalld
    systemctl enable firewalld
    systemctl start firewalld
    
    firewall-cmd --set-default-zone=public
    firewall-cmd --zone=public --add-service=ssh --permanent
    firewall-cmd --reload
fi

# 3. Install and Configure fail2ban
log "Installing and configuring fail2ban..."

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get install -y fail2ban
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" ]]; then
    yum install -y epel-release
    yum install -y fail2ban fail2ban-systemd
fi

# Configure fail2ban
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = admin@example.com
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 86400
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# 4. Kernel Hardening
log "Applying kernel hardening parameters..."

cat > /etc/sysctl.d/99-security-hardening.conf <<'EOF'
# IP Forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable TCP SYN cookies
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# Enable reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1

# File system hardening
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF

sysctl -p /etc/sysctl.d/99-security-hardening.conf

# 5. Set up AIDE (Intrusion Detection)
log "Installing and configuring AIDE..."

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get install -y aide aide-common
    aideinit
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" ]]; then
    yum install -y aide
    aide --init
    mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
fi

# Schedule daily AIDE checks
cat > /etc/cron.daily/aide-check <<'EOF'
#!/bin/bash
/usr/bin/aide --check | mail -s "AIDE Report for $(hostname)" admin@example.com
EOF
chmod +x /etc/cron.daily/aide-check

# 6. Disable Unnecessary Services
log "Disabling unnecessary services..."

SERVICES_TO_DISABLE=(
    "cups"
    "avahi-daemon"
    "bluetooth"
)

for service in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files | grep -q "$service"; then
        systemctl disable "$service" 2>/dev/null || true
        systemctl stop "$service" 2>/dev/null || true
        log "Disabled $service"
    fi
done

# 7. Set File Permissions
log "Setting secure file permissions..."

chmod 600 /etc/ssh/sshd_config
chmod 644 /etc/passwd
chmod 640 /etc/shadow
chmod 640 /etc/gshadow
chmod 644 /etc/group
chmod 600 /boot/grub/grub.cfg 2>/dev/null || chmod 600 /boot/grub2/grub.cfg 2>/dev/null || true

# 8. Configure Password Policy
log "Configuring password policy..."

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get install -y libpam-pwquality
    
    # Configure password quality requirements
    sed -i 's/^# minlen.*/minlen = 14/' /etc/security/pwquality.conf
    sed -i 's/^# dcredit.*/dcredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# ucredit.*/ucredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# lcredit.*/lcredit = -1/' /etc/security/pwquality.conf
    sed -i 's/^# ocredit.*/ocredit = -1/' /etc/security/pwquality.conf
    
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" ]]; then
    # Configure password quality
    authconfig --passminlen=14 --update
fi

# Configure password aging
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

# 9. Enable auditd
log "Configuring audit daemon..."

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get install -y auditd
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" ]]; then
    yum install -y audit
fi

# Configure audit rules
cat > /etc/audit/rules.d/hardening.rules <<'EOF'
# Delete all existing rules
-D

# Buffer size
-b 8192

# Failure mode (0=silent 1=printk 2=panic)
-f 1

# Audit system calls
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# User and group changes
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Network configuration changes
-w /etc/hosts -p wa -k network-config
-w /etc/network/ -p wa -k network-config

# System administration
-w /var/log/sudo.log -p wa -k actions
-w /etc/sudoers -p wa -k actions
-w /etc/sudoers.d/ -p wa -k actions

# SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd

# Cron configuration
-w /etc/cron.allow -p wa -k cron
-w /etc/cron.deny -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/cron.daily/ -p wa -k cron
-w /etc/cron.hourly/ -p wa -k cron
-w /etc/cron.monthly/ -p wa -k cron
-w /etc/cron.weekly/ -p wa -k cron
EOF

# Load audit rules
augenrules --load
systemctl enable auditd
systemctl restart auditd

# 10. Update system packages
log "Updating system packages..."

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get update
    apt-get upgrade -y
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" ]]; then
    yum update -y
fi

# 11. Create security report
log "Generating security report..."

REPORT_FILE="/var/log/security-hardening-$(date +%F).log"

cat > "$REPORT_FILE" <<EOF
Security Hardening Report
========================
Date: $(date)
Hostname: $(hostname)
OS: $OS

Applied Hardening:
- SSH configuration hardened
- Firewall configured and enabled
- fail2ban installed and configured
- Kernel parameters hardened
- AIDE intrusion detection configured
- Unnecessary services disabled
- File permissions set
- Password policy configured
- Audit daemon configured
- System packages updated

Next Steps:
1. Review and customize firewall rules for your applications
2. Configure fail2ban email notifications
3. Set up regular AIDE scans
4. Review audit logs regularly
5. Test SSH configuration with key-based authentication
6. Schedule regular security audits with Lynis

Report saved to: $REPORT_FILE
EOF

log "Security hardening complete!"
log "Report saved to: $REPORT_FILE"
warning "IMPORTANT: Test SSH access in a new terminal before closing this session!"
warning "If you get locked out, you may need console access to recover."

# Display summary
cat "$REPORT_FILE"

exit 0
