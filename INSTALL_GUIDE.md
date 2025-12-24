# 🚀 Complete Installation Guide

Step-by-step guide for deploying OpenVPN server with Admin Panel on a fresh server.

## ⚠️ Important: Installation Order

**YOU MUST install OpenVPN server FIRST**, then install the admin panel.

The admin panel is a management interface for an existing OpenVPN server - it cannot function without it.

## 📋 Prerequisites

- Fresh Linux server (Ubuntu 22.04+, Debian 11+, CentOS 9+)
- Root access
- Public IP address
- Ports 1194 (or custom) and 5000 accessible

## 🔧 Step 1: Install OpenVPN Server

```bash
# Download the official OpenVPN installer
curl -O https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh

# Run the installer
sudo bash openvpn-install.sh
```

**Follow the prompts:**
1. Select your server's public IP
2. Choose protocol (TCP recommended for reliability, UDP for speed)
3. Choose port (default 1194 or custom port like 1059)
4. Select DNS servers (Google DNS, Cloudflare, etc.)
5. (Optional) Create your first client

**The installer will:**
- ✅ Install OpenVPN package
- ✅ Generate Certificate Authority (CA)
- ✅ Generate server certificates and keys
- ✅ Create server configuration
- ✅ Configure IP forwarding and NAT
- ✅ Setup firewall rules
- ✅ Start and enable OpenVPN service

**Verify installation:**
```bash
sudo systemctl status openvpn-server@server
# Should show "Active: active (running)"

# Verify certificates were created
ls -la /etc/openvpn/server/
# Should see: ca.crt, server.crt, server.key, tc.key, dh.pem, crl.pem
```

**🚨 DO NOT PROCEED if OpenVPN is not running!**

---

## 🎨 Step 2: Install Admin Panel

Now that OpenVPN server is running, install the admin panel.

### Option A: Management Menu (Recommended)

```bash
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/manage.sh | sudo bash
```

Select **option 1** (Install OpenVPN Admin Panel)

### Option B: One-Line Direct Install

```bash
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/install_repository.sh | sudo bash
```

### Option C: Clone and Install

```bash
git clone https://github.com/amirhkfar/open_vpn_admin.git
cd open_vpn_admin
sudo bash install.sh
```

**The admin panel installer will:**
- ✅ Check if OpenVPN is installed
- ✅ Install Python 3 and dependencies
- ✅ Clone the admin panel repository
- ✅ Create Python virtual environment
- ✅ Generate random admin credentials
- ✅ Create systemd service
- ✅ Configure firewall for port 5000
- ✅ Start admin panel service

---

## 🔑 Step 3: Access Admin Panel

After successful installation, you'll see:

```
=====================================
Installation Complete!
=====================================

Admin Panel URL: http://YOUR_IP:5000
Username: admin
Password: RandomlyGenerated123==

IMPORTANT: Save these credentials!
```

**Access the panel:**
1. Open browser: `http://YOUR_SERVER_IP:5000`
2. Login with provided credentials

**Retrieve credentials later:**
```bash
sudo cat /root/.openvpn-admin-credentials
```

---

## ✅ Step 4: Verify Everything Works

### Check Services Status

```bash
# OpenVPN server (must be running)
sudo systemctl status openvpn-server@server

# Admin panel (must be running)
sudo systemctl status openvpn-admin
```

Both should show **"Active: active (running)"**

### Create Test Client

1. Login to admin panel
2. Navigate to **"Clients"** page
3. Click **"Add Client"**
4. Enter client name (e.g., "test-client")
5. Set expiry date or leave blank
6. Click **"Add Client"**
7. Download the `.ovpn` file
8. Test with OpenVPN client app

---

## 🛠️ Management & Maintenance

### Using the Management Menu

The management menu provides all operations in one place:

```bash
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/manage.sh | sudo bash
```

**Available options:**
- **1** - Install Admin Panel
- **2** - Update Admin Panel (with auto-backup)
- **3** - Uninstall Admin Panel
- **4** - Restart Service
- **5** - View Status
- **6** - View Logs
- **7** - Show Credentials
- **8** - Reinstall (complete fresh install)
- **9** - Exit

### Manual Service Commands

```bash
# Restart admin panel
sudo systemctl restart openvpn-admin

# Stop admin panel
sudo systemctl stop openvpn-admin

# View admin panel logs
sudo journalctl -u openvpn-admin -f

# Restart OpenVPN server
sudo systemctl restart openvpn-server@server

# View OpenVPN logs
sudo journalctl -u openvpn-server@server -f
```

### Update Admin Panel

```bash
# Via management menu
sudo bash manage.sh  # Select option 2

# Or directly
sudo /opt/openvpn-admin/update.sh
```

Update script automatically:
- Creates backup before updating
- Pulls latest code from GitHub
- Updates Python dependencies
- Preserves your configuration
- Restarts the service

### Uninstall Admin Panel

```bash
# Via management menu
sudo bash manage.sh  # Select option 3

# Or directly
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/uninstall.sh | sudo bash
```

**Note:** Uninstalling admin panel does NOT remove OpenVPN server.

---

## 🔥 Firewall Configuration

### Ubuntu/Debian (UFW)

```bash
# Admin panel
sudo ufw allow 5000/tcp

# OpenVPN (adjust port if you chose different)
sudo ufw allow 1194/udp  # or 1194/tcp if you chose TCP

# Enable firewall
sudo ufw enable
```

### CentOS/Fedora (firewalld)

```bash
# Admin panel
sudo firewall-cmd --permanent --add-port=5000/tcp

# OpenVPN
sudo firewall-cmd --permanent --add-port=1194/udp

# Reload firewall
sudo firewall-cmd --reload
```

---

## 🚨 Troubleshooting

### Problem: Admin Panel Shows "Server Status: Stopped"

**Diagnosis:**
```bash
sudo systemctl status openvpn-server@server
sudo journalctl -u openvpn-server@server -n 50
```

**Common causes:**
1. **Missing certificates** - Reinstall OpenVPN:
   ```bash
   sudo bash openvpn-install.sh
   ```

2. **Configuration error** - Check config:
   ```bash
   sudo cat /etc/openvpn/server/server.conf
   ```

3. **Port already in use** - Check:
   ```bash
   sudo netstat -tlnp | grep 1194
   ```

### Problem: Cannot Access Admin Panel (Connection Refused)

**Check if service is running:**
```bash
sudo systemctl status openvpn-admin
```

**If not running, check logs:**
```bash
sudo journalctl -u openvpn-admin -n 50
```

**Check if port is listening:**
```bash
sudo netstat -tlnp | grep 5000
```

**Reinstall admin panel:**
```bash
sudo bash manage.sh  # Select option 8 (Reinstall)
```

### Problem: Clients Cannot Connect to VPN

1. **Verify OpenVPN is running:**
   ```bash
   sudo systemctl status openvpn-server@server
   ```

2. **Check OpenVPN logs:**
   ```bash
   sudo tail -f /var/log/openvpn/status.log
   sudo journalctl -u openvpn-server@server -f
   ```

3. **Verify firewall allows OpenVPN port:**
   ```bash
   sudo ufw status | grep 1194
   ```

4. **Check IP forwarding:**
   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   # Should show: 1
   ```

### Problem: "Permission Denied" Errors

Admin panel runs as root to manage OpenVPN. Verify:

```bash
# Check service user
sudo systemctl show openvpn-admin | grep User
# Should show: User=root

# Check file permissions
ls -la /opt/openvpn-admin
ls -la /etc/openvpn/server
```

---

## 🔐 Security Best Practices

### 1. Change Admin Password

```bash
sudo nano /opt/openvpn-admin/.env
# Change ADMIN_PASSWORD value
sudo systemctl restart openvpn-admin
```

### 2. Restrict Admin Panel Access

**Limit to specific IP:**
```bash
# UFW example
sudo ufw delete allow 5000/tcp
sudo ufw allow from YOUR_IP to any port 5000
```

### 3. Use Reverse Proxy with SSL

**Nginx with Let's Encrypt:**
```nginx
server {
    listen 443 ssl;
    server_name vpn.yourdomain.com;
    
    ssl_certificate /etc/letsencrypt/live/vpn.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vpn.yourdomain.com/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Change admin panel to listen on localhost only:
```bash
sudo nano /opt/openvpn-admin/app.py
# Change: app.run(host='0.0.0.0', port=5000)
# To: app.run(host='127.0.0.1', port=5000)
sudo systemctl restart openvpn-admin
```

### 4. Regular Updates

```bash
# Update admin panel
sudo /opt/openvpn-admin/update.sh

# Update system
sudo apt update && sudo apt upgrade -y
```

---

## 📦 Complete Fresh Installation Script

For automated deployment on a fresh server:

```bash
#!/bin/bash
# Complete OpenVPN + Admin Panel Installation

set -e

echo "=== Installing OpenVPN Server ==="
curl -O https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh
sudo bash openvpn-install.sh

echo "=== Verifying OpenVPN ==="
sudo systemctl status openvpn-server@server --no-pager

echo "=== Installing Admin Panel ==="
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/install_repository.sh | sudo bash

echo "=== Saving Credentials ==="
sudo cat /root/.openvpn-admin-credentials | tee ~/admin-credentials.txt

echo "=== Installation Complete ==="
echo "Access admin panel at: http://$(hostname -I | awk '{print $1}'):5000"
echo "Credentials saved to: ~/admin-credentials.txt"
```

---

## 📊 Production Checklist

Before going live:

- [ ] OpenVPN server installed and running
- [ ] OpenVPN certificates verified
- [ ] Admin panel installed and accessible
- [ ] Admin password changed from default
- [ ] Firewall configured properly
- [ ] SSL/TLS configured (recommended)
- [ ] Access restricted by IP (optional)
- [ ] Backup strategy implemented
- [ ] Test client created and tested successfully
- [ ] All credentials saved securely
- [ ] Monitoring configured
- [ ] Documentation saved

---

## 🔄 Backup & Restore

### Backup

```bash
# Complete backup
sudo tar -czf vpn-backup-$(date +%Y%m%d).tar.gz \
    /etc/openvpn/server/ \
    /opt/openvpn-admin/ \
    /root/.openvpn-admin-credentials

# Move to safe location
scp vpn-backup-*.tar.gz user@backup-server:/backups/
```

### Restore

```bash
# Extract backup
sudo tar -xzf vpn-backup-*.tar.gz -C /

# Restart services
sudo systemctl restart openvpn-server@server
sudo systemctl restart openvpn-admin
```

---

## 📞 Support

- **GitHub Issues:** https://github.com/amirhkfar/open_vpn_admin/issues
- **Documentation:** https://github.com/amirhkfar/open_vpn_admin
- **OpenVPN Docs:** https://openvpn.net/community-resources/

---

## ✨ Summary

**Quick install on fresh server:**

```bash
# 1. Install OpenVPN
curl -O https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh && sudo bash openvpn-install.sh

# 2. Install Admin Panel  
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/install_repository.sh | sudo bash

# 3. Access panel
# http://YOUR_IP:5000 (credentials shown after installation)
```

**That's it!** Your OpenVPN server with modern admin panel is ready. 🎉
