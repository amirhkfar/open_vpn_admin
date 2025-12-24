# 🔐 OpenVPN Admin Panel

A lightweight, web-based administration panel for managing OpenVPN clients. Compatible with the popular [openvpn-install](https://github.com/Nyr/openvpn-install) script.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.8+-blue.svg)
![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)

## ✨ Features

### 📊 Dashboard & Monitoring
- **Real-time Statistics** - Total clients, connected users, upload/download speeds
- **Server Information** - Monitor server status, IP, port, and protocol
- **Live Connection Tracking** - See which clients are online with IP addresses
- **Bandwidth Monitoring** - Track data usage per client (Upload/Download in B/KB/MB/GB/TB)
- **Auto-refresh** - Dashboard updates every 30 seconds

### 👥 Client Management
- **Add Clients** - Create new VPN clients with custom expiry dates
- **Edit Clients** - Modify existing client settings (multi-connection support)
- **Extend Expiry** - Renew certificate expiration for existing clients
- **Revoke Clients** - Disable client certificates instantly
- **Full Delete** - Completely remove clients and all their files
- **Multi-Connection Control** - Enable/disable duplicate connections per client

### 📥 Configuration Export
- **Download Configs** - Download `.ovpn` configuration files
- **Base64 Export** - Get client config as base64 encoded string
- **Inline Configurations** - All certificates embedded in config files

### 🎨 Modern Interface
- **3x-ui Inspired Design** - Clean, dark sidebar navigation
- **Inter Font** - Professional typography throughout
- **Purple Gradient Theme** - Beautiful color scheme (#667eea → #764ba2)
- **Responsive Layout** - Works on desktop, tablet, and mobile
- **Session-based Authentication** - Secure login with 24-hour sessions
- **Action Dropdown Menus** - Clean, organized client actions

## 📋 Requirements

- Linux server (Ubuntu 22.04+, Debian 11+, CentOS 9+, Fedora, AlmaLinux, Rocky Linux)
- OpenVPN server installed via [openvpn-install.sh](https://github.com/Nyr/openvpn-install)
- Python 3.8 or higher
- Root access

## 🚀 Quick Installation

### 1. Install OpenVPN Server (if not already installed)

```bash
curl -O https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh
sudo bash openvpn-install.sh
```

### 2. Install OpenVPN Admin Panel

#### One-Line Installation (Recommended)
```bash
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/install_repository.sh | sudo bash
```

#### Or Manual Clone and Install
```bash
# Clone the repository
git clone https://github.com/amirhkfar/open_vpn_admin.git openvpn-admin
cd openvpn-admin

# Run the installation script
sudo bash install.sh
```

The installer will:
- Install Python dependencies
- Create a virtual environment
- Generate random admin credentials
- Configure OpenVPN status logging
- Create and start a systemd service
- Configure firewall rules

### 3. Access the Panel

Open your browser and navigate to:
```
http://YOUR_SERVER_IP:5000
```

Default credentials will be displayed after installation. You can also view them anytime:
```bash
sudo cat /root/.openvpn-admin-credentials
```

## 🛠️ Management

### Interactive Management Menu

Use the management script for easy control:

```bash
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/manage.sh | sudo bash
```

Or if you cloned the repository:
```bash
sudo bash manage.sh
```

The management menu provides:
- **Install** - Install OpenVPN Admin Panel
- **Update** - Update to the latest version (with auto-backup)
- **Uninstall** - Remove the admin panel completely
- **Restart** - Restart the admin panel service
- **Status** - View service status
- **Logs** - View recent logs
- **Credentials** - Show admin login credentials
- **Reinstall** - Complete reinstall (uninstall + install)

## 🔄 Updating

### Via Management Menu (Recommended)
```bash
sudo bash manage.sh
# Select option 2 for Update
```

### Automatic Update

Check for updates and install automatically:

```bash
sudo /opt/openvpn-admin/update.sh
```

The update script will:
- ✓ Check for new versions on GitHub
- ✓ Create automatic backup before updating
- ✓ Preserve your settings (.env file)
- ✓ Preserve bandwidth statistics
- ✓ Update dependencies
- ✓ Restart the service

### Manual Update

```bash
cd /opt/openvpn-admin
git pull origin main
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart openvpn-admin
```
## 🗑️ Uninstalling

### Via Management Menu (Recommended)
```bash
sudo bash manage.sh
# Select option 3 for Uninstall
```

### Direct Uninstall
```bash
curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/uninstall.sh | sudo bash
```

Or if you cloned the repository:
```bash
sudo bash uninstall.sh
```

The uninstaller will remove:
- Admin panel directory (`/opt/openvpn-admin`)
- Service file (`openvpn-admin.service`)
- Credentials file
- Log files

**Note:** OpenVPN server and its configuration will NOT be removed. To remove OpenVPN server, use the OpenVPN uninstaller separately.
## �🔧 Manual Installation

If you prefer manual installation:

```bash
# Install dependencies
sudo apt-get update  # For Ubuntu/Debian
sudo apt-get install -y python3 python3-pip python3-venv

# Create installation directory
sudo mkdir -p /opt/openvpn-admin
cd /opt/openvpn-admin

# Copy files
sudo cp app.py requirements.txt /opt/openvpn-admin/
sudo cp -r templates /opt/openvpn-admin/

# Create virtual environment
sudo python3 -m venv venv
sudo venv/bin/pip install -r requirements.txt

# Create configuration file
sudo cat > .env <<EOF
ADMIN_USER=admin
ADMIN_PASS=your-secure-password
FLASK_HOST=0.0.0.0
FLASK_PORT=5000
EOF

# Enable status logging in OpenVPN
echo "status /var/log/openvpn/status.log" | sudo tee -a /etc/openvpn/server/server.conf
sudo mkdir -p /var/log/openvpn
sudo systemctl restart openvpn-server@server

# Create systemd service
sudo cat > /etc/systemd/system/openvpn-admin.service <<EOF
[Unit]
Description=OpenVPN Admin Panel
After=network.target openvpn-server@server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/openvpn-admin
Environment="PATH=/opt/openvpn-admin/venv/bin"
EnvironmentFile=/opt/openvpn-admin/.env
ExecStart=/opt/openvpn-admin/venv/bin/python /opt/openvpn-admin/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start the service
sudo systemctl daemon-reload
sudo systemctl enable openvpn-admin
sudo systemctl start openvpn-admin

# Open firewall port
sudo firewall-cmd --permanent --add-port=5000/tcp  # For firewalld
sudo firewall-cmd --reload
# OR
sudo ufw allow 5000/tcp  # For UFW
```

## 🎯 Usage

### Managing Clients

1. **Add a Client**
   - Click "Add Client" button
   - Enter client name (letters, numbers, hyphens, underscores only)
   - Click "Create Client"
   - Download the `.ovpn` configuration file

2. **Revoke a Client**
   - Find the client in the table
   - Click "Revoke" button
   - Confirm the action

3. **Download Configuration**
   - Click "Download" button next to any active client
   - Send the `.ovpn` file to your user

### Monitoring

The dashboard shows:
- Total number of clients
- Active (non-revoked) clients
- Currently connected clients
- Revoked clients
- Real-time connection status

The connection status refreshes automatically every 30 seconds.

## ⚙️ Configuration

Edit `/opt/openvpn-admin/.env` to change settings:

```bash
# Admin credentials
ADMIN_USER=admin
ADMIN_PASS=your-secure-password

# Server settings
FLASK_HOST=0.0.0.0
FLASK_PORT=5000
```

After changing configuration:
```bash
sudo systemctl restart openvpn-admin
```

## 🔒 Security Recommendations

1. **Change Default Password**
   ```bash
   sudo nano /opt/openvpn-admin/.env
   # Change ADMIN_PASS value
   sudo systemctl restart openvpn-admin
   ```

2. **Use HTTPS** (recommended for production)
   - Set up a reverse proxy with Nginx/Apache
   - Use Let's Encrypt for SSL certificates

3. **Firewall Configuration**
   ```bash
   # Only allow access from specific IP
   sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="YOUR_IP" port protocol="tcp" port="5000" accept'
   sudo firewall-cmd --reload
   ```

4. **Change Default Port**
   - Edit `FLASK_PORT` in `.env`
   - Update firewall rules
   - Restart service

## 🛠️ Troubleshooting

### Service won't start
```bash
# Check service status
sudo systemctl status openvpn-admin

# View logs
sudo journalctl -u openvpn-admin -n 50
```

### Can't see connected clients
Ensure status logging is enabled:
```bash
grep "status" /etc/openvpn/server/server.conf
# Should show: status /var/log/openvpn/status.log

# If not present, add it:
echo "status /var/log/openvpn/status.log" | sudo tee -a /etc/openvpn/server/server.conf
sudo systemctl restart openvpn-server@server
```

### Permission errors
The service runs as root to access OpenVPN files. Ensure:
```bash
ls -la /etc/openvpn/server/
ls -la /etc/openvpn/server/easy-rsa/
```

### Can't access from browser
Check firewall:
```bash
# For firewalld
sudo firewall-cmd --list-all

# For UFW
sudo ufw status
```

## 📁 File Structure

```
openvpn-admin/
├── app.py                 # Main Flask application
├── requirements.txt       # Python dependencies
├── install.sh            # Installation script
├── .env.example          # Example configuration
├── .gitignore            # Git ignore file
├── README.md             # This file
└── templates/
    └── index.html        # Web interface template
```

## 🔄 Useful Commands

```bash
# Service management
sudo systemctl start openvpn-admin
sudo systemctl stop openvpn-admin
sudo systemctl restart openvpn-admin
sudo systemctl status openvpn-admin

# View logs
sudo journalctl -u openvpn-admin -f

# Check OpenVPN server
sudo systemctl status openvpn-server@server

# View OpenVPN logs
sudo journalctl -u openvpn-server@server -f
```

## 🔄 Updating

```bash
cd openvpn-admin
git pull
sudo systemctl restart openvpn-admin
```

## 🗑️ Uninstallation

```bash
# Stop and disable service
sudo systemctl stop openvpn-admin
sudo systemctl disable openvpn-admin

# Remove files
sudo rm /etc/systemd/system/openvpn-admin.service
sudo rm -rf /opt/openvpn-admin

# Reload systemd
sudo systemctl daemon-reload

# Remove firewall rule
sudo firewall-cmd --permanent --remove-port=5000/tcp
sudo firewall-cmd --reload
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📜 License

This project is licensed under the MIT License.

## 🙏 Acknowledgments

- [Nyr/openvpn-install](https://github.com/Nyr/openvpn-install) - The awesome OpenVPN installation script
- Flask - Web framework
- All contributors and users

## ⚠️ Disclaimer

This software is provided as-is. Always test in a non-production environment first. Make sure to keep your admin credentials secure and use HTTPS in production environments.

## 📞 Support

If you encounter issues:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review logs: `sudo journalctl -u openvpn-admin -n 100`
3. Open an issue on GitHub

---

Made with ❤️ for the OpenVPN community
