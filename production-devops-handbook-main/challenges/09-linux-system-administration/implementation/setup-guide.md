# Linux System Administration Implementation Guide

This guide provides step-by-step instructions to implement modern Linux system administration practices.

## Prerequisites

- Linux server (Ubuntu 22.04 LTS or RHEL 8/9)
- Root or sudo access
- Basic Linux command-line knowledge

## 1. Security Hardening

### Step 1: Run Security Audit
```bash
# Install Lynis
sudo apt update && sudo apt install -y lynis  # Ubuntu/Debian
sudo yum install -y lynis                      # RHEL/CentOS

# Run security audit
sudo lynis audit system

# Review recommendations in /var/log/lynis.log
```

### Step 2: Apply Security Hardening Script
```bash
# Use the provided security-hardening.sh script
sudo ./security-hardening.sh

# This script will:
# - Configure SSH security
# - Set up firewall rules
# - Enable fail2ban
# - Apply kernel hardening
# - Set up AIDE intrusion detection
```

### Step 3: Configure SELinux/AppArmor
```bash
# For RHEL/CentOS (SELinux)
sudo setenforce 1
sudo sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config

# For Ubuntu (AppArmor)
sudo systemctl enable apparmor
sudo systemctl start apparmor
sudo aa-enforce /etc/apparmor.d/*
```

## 2. Configuration Management with Ansible

### Step 1: Install Ansible
```bash
# Ubuntu/Debian
sudo apt install -y ansible

# RHEL/CentOS
sudo yum install -y ansible
```

### Step 2: Set Up Ansible Project
```bash
# Create directory structure
mkdir -p ~/ansible/{inventory,playbooks,roles}
cd ~/ansible

# Create inventory file
cat > inventory/hosts.yml <<EOF
all:
  children:
    webservers:
      hosts:
        web1.example.com:
        web2.example.com:
    databases:
      hosts:
        db1.example.com:
EOF
```

### Step 3: Use Provided Ansible Playbooks
```bash
# Run server baseline configuration
ansible-playbook -i inventory/hosts.yml playbooks/baseline-config.yml

# Deploy monitoring agents
ansible-playbook -i inventory/hosts.yml playbooks/monitoring-setup.yml

# Apply security hardening
ansible-playbook -i inventory/hosts.yml playbooks/security-hardening.yml
```

## 3. Monitoring Setup

### Step 1: Install Prometheus Node Exporter
```bash
# Download and install node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo useradd -rs /bin/false node_exporter

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Start and enable service
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

### Step 2: Configure Centralized Logging
```bash
# Install and configure rsyslog for central logging
sudo apt install -y rsyslog  # Ubuntu/Debian
sudo yum install -y rsyslog  # RHEL/CentOS

# Configure remote logging
echo "*.* @@logserver.example.com:514" | sudo tee -a /etc/rsyslog.conf
sudo systemctl restart rsyslog
```

### Step 3: Set Up Log Rotation
```bash
# Configure logrotate for application logs
sudo tee /etc/logrotate.d/application <<EOF
/var/log/application/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 appuser appuser
    sharedscripts
    postrotate
        systemctl reload application || true
    endscript
}
EOF
```

## 4. Performance Optimization

### Step 1: Apply Kernel Tuning
```bash
# Use the provided performance-tuning.sh script
sudo ./performance-tuning.sh

# This applies optimizations for:
# - Network stack (TCP/IP)
# - Virtual memory
# - File system
# - Process limits
```

### Step 2: Configure Resource Limits
```bash
# Edit /etc/security/limits.conf
sudo tee -a /etc/security/limits.conf > /dev/null <<EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 4096
* hard nproc 4096
EOF
```

### Step 3: Optimize Disk I/O
```bash
# Set I/O scheduler for SSDs
echo "none" | sudo tee /sys/block/sda/queue/scheduler

# Make persistent
echo 'ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"' | \
  sudo tee /etc/udev/rules.d/60-scheduler.rules
```

## 5. Backup Implementation

### Step 1: Install Restic
```bash
# Install restic
sudo apt install -y restic  # Ubuntu/Debian
sudo yum install -y restic  # RHEL/CentOS

# Or download latest version
wget https://github.com/restic/restic/releases/download/v0.16.3/restic_0.16.3_linux_amd64.bz2
bunzip2 restic_0.16.3_linux_amd64.bz2
sudo mv restic_0.16.3_linux_amd64 /usr/local/bin/restic
sudo chmod +x /usr/local/bin/restic
```

### Step 2: Initialize Backup Repository
```bash
# Initialize repository (local or S3)
export RESTIC_REPOSITORY=/backup/repo
export RESTIC_PASSWORD="your-secure-password"

restic init

# For S3 backend
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export RESTIC_REPOSITORY="s3:s3.amazonaws.com/my-backup-bucket"
restic init
```

### Step 3: Use Provided Backup Script
```bash
# Run backup
sudo ./backup-system.sh

# This script:
# - Backs up system files and configurations
# - Creates database dumps
# - Uploads to remote repository
# - Verifies backup integrity
# - Sends notification on completion/failure
```

### Step 4: Schedule Automated Backups
```bash
# Create systemd timer for daily backups
sudo tee /etc/systemd/system/backup-system.service > /dev/null <<EOF
[Unit]
Description=System Backup Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-system.sh
EOF

sudo tee /etc/systemd/system/backup-system.timer > /dev/null <<EOF
[Unit]
Description=Daily System Backup

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now backup-system.timer
```

## 6. User and Access Management

### Step 1: Configure SSH Key Authentication
```bash
# Generate SSH key (on client)
ssh-keygen -t ed25519 -C "admin@example.com"

# Copy to server
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server

# Disable password authentication
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### Step 2: Configure Sudo Access
```bash
# Create admin group
sudo groupadd admin

# Add user to admin group
sudo usermod -aG admin username

# Configure sudo for admin group
echo "%admin ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/admin
sudo chmod 440 /etc/sudoers.d/admin
```

### Step 3: Enable Audit Logging
```bash
# Install auditd
sudo apt install -y auditd  # Ubuntu/Debian
sudo yum install -y audit   # RHEL/CentOS

# Configure audit rules
sudo tee -a /etc/audit/rules.d/audit.rules > /dev/null <<EOF
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /var/log/auth.log -p wa -k auth_log_changes
EOF

# Load rules and start service
sudo augenrules --load
sudo systemctl enable --now auditd
```

## 7. Automated Patching

### Step 1: Configure Unattended Upgrades (Ubuntu/Debian)
```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Configure automatic security updates
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Mail "admin@example.com";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# Enable automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades
```

### Step 2: Configure yum-cron (RHEL/CentOS)
```bash
# Install yum-cron
sudo yum install -y yum-cron

# Configure for security updates only
sudo sed -i 's/update_cmd = default/update_cmd = security/' /etc/yum/yum-cron.conf
sudo sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf

# Start and enable
sudo systemctl enable --now yum-cron
```

## 8. Health Check and Monitoring Scripts

### Step 1: Deploy Health Check Script
```bash
# Use the provided system-health-check.sh script
sudo cp system-health-check.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/system-health-check.sh

# Run manually
/usr/local/bin/system-health-check.sh
```

### Step 2: Schedule Regular Health Checks
```bash
# Create systemd timer for hourly health checks
sudo tee /etc/systemd/system/health-check.timer > /dev/null <<EOF
[Unit]
Description=Hourly System Health Check

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl enable --now health-check.timer
```

## Validation and Testing

### Test 1: Security Validation
```bash
# Run Lynis audit
sudo lynis audit system

# Check SSH configuration
sudo sshd -t

# Verify firewall rules
sudo iptables -L -n -v
# OR for nftables
sudo nft list ruleset
```

### Test 2: Monitoring Validation
```bash
# Check node_exporter metrics
curl http://localhost:9100/metrics

# Verify logs are being sent
sudo tail -f /var/log/syslog  # or journalctl -f
```

### Test 3: Backup Validation
```bash
# List snapshots
restic snapshots

# Verify backup
restic check

# Test restore (to /tmp)
restic restore latest --target /tmp/restore-test
```

### Test 4: Performance Check
```bash
# Check system load
uptime

# Memory usage
free -h

# Disk I/O
iostat -x 1 5

# Network performance
sar -n DEV 1 5
```

## Troubleshooting

### Issue: High CPU Usage
```bash
# Identify top processes
top -o %CPU

# Check system load history
sar -u 1 10
```

### Issue: Disk Space Full
```bash
# Find large files
sudo du -ah / | sort -rh | head -n 20

# Clean package cache
sudo apt clean  # Ubuntu/Debian
sudo yum clean all  # RHEL/CentOS
```

### Issue: Network Connectivity
```bash
# Check network interfaces
ip addr show

# Test connectivity
ping -c 4 8.8.8.8

# Check routing
ip route show

# DNS resolution
nslookup example.com
```

## Next Steps

1. **Document Your Infrastructure**: Create runbooks for common tasks
2. **Set Up Alerting**: Configure Prometheus Alertmanager or Nagios
3. **Disaster Recovery Testing**: Regularly test backup restores
4. **Capacity Planning**: Monitor trends and plan for growth
5. **Team Training**: Ensure team members understand the setup

## Additional Resources

- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [Lynis Documentation](https://cisofy.com/documentation/lynis/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Restic Documentation](https://restic.readthedocs.io/)
- [Linux Performance Analysis](https://www.brendangregg.com/linuxperf.html)
