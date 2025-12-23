#!/usr/bin/env python3
"""
OpenVPN Admin Panel - Lightweight web interface for OpenVPN client management
Compatible with https://github.com/Nyr/openvpn-install
"""

from flask import Flask, render_template, request, jsonify, send_file, flash, redirect, url_for, Response
from functools import wraps
import os
import subprocess
import re
from datetime import datetime
import secrets
import base64

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# Configuration
OPENVPN_DIR = "/etc/openvpn/server"
EASYRSA_DIR = f"{OPENVPN_DIR}/easy-rsa"
CLIENT_CONFIG_DIR = "/root"  # Where .ovpn files are generated
OPENVPN_STATUS = "/var/log/openvpn/status.log"

# Simple authentication (change these!)
ADMIN_USERNAME = os.getenv("ADMIN_USER", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASS", "changeme")


def requires_auth(f):
    """Decorator for routes that require authentication"""
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or auth.username != ADMIN_USERNAME or auth.password != ADMIN_PASSWORD:
            return ('Authentication required', 401, {
                'WWW-Authenticate': 'Basic realm="OpenVPN Admin"'
            })
        return f(*args, **kwargs)
    return decorated


def run_command(cmd, shell=False):
    """Execute shell command and return output"""
    try:
        # Add /usr/bin and /bin to PATH for systemctl and other commands
        env = os.environ.copy()
        env['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        
        result = subprocess.run(
            cmd,
            shell=shell,
            capture_output=True,
            text=True,
            check=True,
            env=env
        )
        return result.stdout, None
    except subprocess.CalledProcessError as e:
        return None, e.stderr
    except FileNotFoundError as e:
        return None, str(e)


def parse_openvpn_date(date_str):
    """Parse OpenVPN date format (YYMMDDHHMMSSZ) to readable format"""
    try:
        # Format: YYMMDDHHMMSSZ
        year = int('20' + date_str[0:2])
        month = int(date_str[2:4])
        day = int(date_str[4:6])
        return f"{year}-{month:02d}-{day:02d}"
    except:
        return date_str[:8]


def get_clients():
    """Get list of all clients from OpenVPN index.txt"""
    index_file = f"{EASYRSA_DIR}/pki/index.txt"
    clients = []
    
    if not os.path.exists(index_file):
        return clients
    
    try:
        with open(index_file, 'r') as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 6:
                    status = 'Active' if parts[0] == 'V' else 'Revoked'
                    expiry = parts[1]
                    revoke_date = parts[2] if parts[0] == 'R' and parts[2] else ''
                    serial = parts[3]
                    name_part = parts[5]  # DN is in the 6th field (index 5)
                    
                    # Extract client name from DN
                    match = re.search(r'CN=([^/]+)', name_part)
                    if match:
                        name = match.group(1)
                        if name != 'server':  # Skip server cert
                            clients.append({
                                'name': name,
                                'status': status,
                                'expiry': expiry,
                                'expiry_formatted': parse_openvpn_date(expiry),
                                'revoke_date': revoke_date,
                                'serial': serial
                            })
    except Exception as e:
        print(f"Error reading clients: {e}")
    
    return clients


def get_connected_clients():
    """Parse OpenVPN status log to get connected clients"""
    connected = {}
    
    if not os.path.exists(OPENVPN_STATUS):
        return connected
    
    try:
        with open(OPENVPN_STATUS, 'r') as f:
            in_client_section = False
            in_routing_section = False
            
            for line in f:
                # Check for CLIENT_LIST section
                if line.startswith('HEADER,CLIENT_LIST'):
                    in_client_section = True
                    continue
                elif line.startswith('HEADER,ROUTING_TABLE'):
                    in_client_section = False
                    in_routing_section = True
                    continue
                elif line.startswith('GLOBAL_STATS') or line.startswith('END'):
                    in_client_section = False
                    in_routing_section = False
                    continue
                
                # Parse CLIENT_LIST format
                if in_client_section and line.startswith('CLIENT_LIST,'):
                    parts = line.split(',')
                    if len(parts) >= 8:
                        name = parts[1]
                        real_ip = parts[2]
                        bytes_recv = parts[5]
                        bytes_sent = parts[6]
                        connected_since = parts[7]
                        
                        connected[name] = {
                            'real_ip': real_ip,
                            'bytes_recv': bytes_recv,
                            'bytes_sent': bytes_sent,
                            'connected_since': connected_since
                        }
                
                # Parse ROUTING_TABLE format (fallback)
                if in_routing_section and line.startswith('ROUTING_TABLE,'):
                    parts = line.split(',')
                    if len(parts) >= 5:
                        virtual_ip = parts[1]
                        name = parts[2]
                        real_ip = parts[3]
                        last_ref = parts[4]
                        
                        if name not in connected:
                            connected[name] = {
                                'real_ip': real_ip,
                                'virtual_ip': virtual_ip,
                                'bytes_recv': 'N/A',
                                'bytes_sent': 'N/A',
                                'connected_since': last_ref
                            }
    except Exception as e:
        print(f"Error reading status: {e}")
    
    return connected


def get_server_info():
    """Get OpenVPN server configuration info"""
    config_file = f"{OPENVPN_DIR}/server.conf"
    info = {
        'port': 'N/A',
        'protocol': 'N/A',
        'subnet': '10.8.0.0/24',
        'status': 'Unknown'
    }
    
    # Check service status
    status_out, _ = run_command(['systemctl', 'is-active', 'openvpn-server@server'])
    info['status'] = status_out.strip() if status_out else 'inactive'
    
    if os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                for line in f:
                    if line.startswith('port '):
                        info['port'] = line.split()[1]
                    elif line.startswith('proto '):
                        info['protocol'] = line.split()[1]
                    elif line.startswith('server '):
                        parts = line.split()
                        if len(parts) >= 3:
                            info['subnet'] = f"{parts[1]}/{parts[2]}"
        except Exception as e:
            print(f"Error reading config: {e}")
    
    return info


@app.route('/')
@requires_auth
def index():
    """Main dashboard"""
    clients = get_clients()
    connected = get_connected_clients()
    server_info = get_server_info()
    
    # Merge client data with connection status
    for client in clients:
        client['connected'] = client['name'] in connected
        if client['connected']:
            client['connection'] = connected[client['name']]
    
    stats = {
        'total_clients': len(clients),
        'active_clients': sum(1 for c in clients if c['status'] == 'Active'),
        'revoked_clients': sum(1 for c in clients if c['status'] == 'Revoked'),
        'connected_clients': len(connected)
    }
    
    return render_template('index.html', 
                         clients=clients, 
                         stats=stats, 
                         server_info=server_info)


@app.route('/api/clients')
@requires_auth
def api_clients():
    """API endpoint to get all clients"""
    clients = get_clients()
    connected = get_connected_clients()
    
    for client in clients:
        client['connected'] = client['name'] in connected
        if client['connected']:
            client['connection'] = connected[client['name']]
    
    return jsonify(clients)


@app.route('/api/add_client', methods=['POST'])
@requires_auth
def add_client():
    """Add a new OpenVPN client"""
    data = request.get_json()
    client_name = data.get('name', '').strip()
    expiry_days = data.get('expiry_days', 3650)  # Default 10 years
    allow_duplicate = data.get('allow_duplicate', False)  # Allow multiple connections
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    # Validate expiry days
    try:
        expiry_days = int(expiry_days)
        if expiry_days < 1 or expiry_days > 7300:  # Max 20 years
            return jsonify({'success': False, 'message': 'Expiry days must be between 1 and 7300'}), 400
    except (ValueError, TypeError):
        return jsonify({'success': False, 'message': 'Invalid expiry days'}), 400
    
    # Sanitize client name
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    
    # Check if client already exists
    index_file = f"{EASYRSA_DIR}/pki/index.txt"
    if os.path.exists(index_file):
        with open(index_file, 'r') as f:
            if f"CN={client_name}" in f.read():
                return jsonify({'success': False, 'message': 'Client already exists'}), 400
    
    # Create client certificate
    cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days={expiry_days} build-client-full {client_name} nopass"
    stdout, stderr = run_command(cmd, shell=True)
    
    if stderr:
        return jsonify({'success': False, 'message': f'Error creating client: {stderr}'}), 500
    
    # Generate .ovpn file
    # Try using inline file first, if not exists, build it manually
    inline_file = f"{EASYRSA_DIR}/pki/inline/{client_name}.inline"
    if os.path.exists(inline_file):
        ovpn_cmd = f"grep -vh '^#' {OPENVPN_DIR}/client-common.txt {inline_file} > {CLIENT_CONFIG_DIR}/{client_name}.ovpn"
        stdout, stderr = run_command(ovpn_cmd, shell=True)
    else:
        # Build .ovpn manually from certificate files
        ca_file = f"{OPENVPN_DIR}/ca.crt"
        cert_file = f"{EASYRSA_DIR}/pki/issued/{client_name}.crt"
        key_file = f"{EASYRSA_DIR}/pki/private/{client_name}.key"
        tls_key = f"{OPENVPN_DIR}/tc.key"
        
        # Create config with embedded certificates
        build_cmd = f"""cat {OPENVPN_DIR}/client-common.txt > {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<ca>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
cat {ca_file} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</ca>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<cert>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
openssl x509 -in {cert_file} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</cert>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<key>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
cat {key_file} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</key>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<tls-crypt>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
cat {tls_key} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</tls-crypt>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn"""
        
        stdout, stderr = run_command(build_cmd, shell=True)
        
        if stderr:
            return jsonify({'success': False, 'message': f'Error generating config: {stderr}'}), 500
    
    # Add duplicate-cn directive if multiple connections allowed
    if allow_duplicate:
        add_dup_cmd = f"echo 'duplicate-cn' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn"
        run_command(add_dup_cmd, shell=True)
    
    return jsonify({
        'success': True, 
        'message': f'Client {client_name} created successfully',
        'client_name': client_name
    })


@app.route('/api/edit_client', methods=['POST'])
@requires_auth
def edit_client():
    """Edit client configuration (enable/disable duplicate-cn)"""
    data = request.get_json()
    client_name = data.get('name', '').strip()
    allow_duplicate = data.get('allow_duplicate', False)
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    # Sanitize client name
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    config_file = f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
    
    if not os.path.exists(config_file):
        return jsonify({'success': False, 'message': 'Client config not found'}), 404
    
    try:
        # Read current config
        with open(config_file, 'r') as f:
            lines = f.readlines()
        
        # Remove existing duplicate-cn line
        lines = [line for line in lines if not line.strip().startswith('duplicate-cn')]
        
        # Add duplicate-cn if requested
        if allow_duplicate:
            lines.append('duplicate-cn\n')
        
        # Write back
        with open(config_file, 'w') as f:
            f.writelines(lines)
        
        status = 'enabled' if allow_duplicate else 'disabled'
        return jsonify({
            'success': True,
            'message': f'Multiple connections {status} for {client_name}'
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/revoke_client', methods=['POST'])
@requires_auth
def revoke_client():
    """Revoke an OpenVPN client certificate"""
    data = request.get_json()
    client_name = data.get('name', '').strip()
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    # Revoke the certificate
    cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch revoke {client_name}"
    stdout, stderr = run_command(cmd, shell=True)
    
    if stderr and 'error' in stderr.lower():
        return jsonify({'success': False, 'message': f'Error revoking client: {stderr}'}), 500
    
    # Regenerate CRL
    cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days=3650 gen-crl"
    run_command(cmd, shell=True)
    
    # Update CRL
    cmd = f"cp {EASYRSA_DIR}/pki/crl.pem {OPENVPN_DIR}/crl.pem && chown nobody:nogroup {OPENVPN_DIR}/crl.pem 2>/dev/null || chown nobody:nobody {OPENVPN_DIR}/crl.pem"
    run_command(cmd, shell=True)
    
    return jsonify({
        'success': True, 
        'message': f'Client {client_name} revoked successfully'
    })


@app.route('/api/download_config/<client_name>')
@requires_auth
def download_config(client_name):
    """Download .ovpn configuration file"""
    # Sanitize filename
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    config_file = f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
    
    if not os.path.exists(config_file):
        return jsonify({'success': False, 'message': 'Configuration file not found'}), 404
    
    return send_file(config_file, 
                    as_attachment=True, 
                    download_name=f"{client_name}.ovpn",
                    mimetype='application/x-openvpn-profile')


@app.route('/api/config_base64/<client_name>')
@requires_auth
def config_base64(client_name):
    """Get configuration file as base64 encoded string"""
    # Sanitize filename
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    config_file = f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
    
    if not os.path.exists(config_file):
        return jsonify({'success': False, 'message': 'Configuration file not found'}), 404
    
    try:
        with open(config_file, 'rb') as f:
            config_content = f.read()
            base64_content = base64.b64encode(config_content).decode('utf-8')
            
        return jsonify({
            'success': True,
            'client_name': client_name,
            'base64': base64_content,
            'size': len(config_content)
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/client_info/<client_name>')
@requires_auth
def client_info(client_name):
    """Get client configuration info"""
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    config_file = f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
    
    if not os.path.exists(config_file):
        return jsonify({'success': False, 'message': 'Config not found'}), 404
    
    try:
        with open(config_file, 'r') as f:
            content = f.read()
            has_duplicate_cn = 'duplicate-cn' in content
        
        return jsonify({
            'success': True,
            'client_name': client_name,
            'allow_duplicate': has_duplicate_cn
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/extend_expiry', methods=['POST'])
@requires_auth
def extend_expiry():
    """Extend certificate expiration for a client"""
    data = request.get_json()
    client_name = data.get('name', '').strip()
    extend_days = int(data.get('days', 365))
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    # Sanitize client name
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    
    try:
        # Renew the certificate
        renew_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days={extend_days} renew {client_name} nopass"
        run_command(renew_cmd, shell=True)
        
        # Regenerate the .ovpn file
        inline_file = f"{EASYRSA_DIR}/pki/inline/{client_name}.inline"
        
        if os.path.exists(inline_file):
            ovpn_cmd = f"grep -vh '^#' {OPENVPN_DIR}/client-common.txt {inline_file} > {CLIENT_CONFIG_DIR}/{client_name}.ovpn"
        else:
            # Build manually
            ca_file = f"{OPENVPN_DIR}/ca.crt"
            cert_file = f"{EASYRSA_DIR}/pki/issued/{client_name}.crt"
            key_file = f"{EASYRSA_DIR}/pki/private/{client_name}.key"
            tc_file = f"{OPENVPN_DIR}/tc.key"
            
            ovpn_cmd = f"""cat {OPENVPN_DIR}/client-common.txt > {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<ca>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
cat {ca_file} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</ca>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<cert>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
openssl x509 -in {cert_file} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</cert>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<key>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
cat {key_file} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</key>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '<tls-crypt>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
cat {tc_file} >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn
echo '</tls-crypt>' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn"""
        
        run_command(ovpn_cmd, shell=True)
        
        return jsonify({
            'success': True,
            'message': f'Certificate for {client_name} extended by {extend_days} days'
        })
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error extending expiry: {str(e)}'}), 500


@app.route('/api/delete_client', methods=['POST'])
@requires_auth
def delete_client():
    """Completely delete a client (revoke and remove all files)"""
    data = request.get_json()
    client_name = data.get('name', '').strip()
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    # Sanitize client name
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    
    try:
        # First revoke the certificate if it's still valid
        revoke_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch revoke {client_name} 2>/dev/null || true"
        run_command(revoke_cmd, shell=True)
        
        # Regenerate CRL
        crl_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days=3650 gen-crl"
        run_command(crl_cmd, shell=True)
        
        # Update CRL
        update_crl_cmd = f"cp {EASYRSA_DIR}/pki/crl.pem {OPENVPN_DIR}/crl.pem && chown nobody:nogroup {OPENVPN_DIR}/crl.pem 2>/dev/null || chown nobody:nobody {OPENVPN_DIR}/crl.pem"
        run_command(update_crl_cmd, shell=True)
        
        # Delete all client files
        files_to_delete = [
            f"{EASYRSA_DIR}/pki/issued/{client_name}.crt",
            f"{EASYRSA_DIR}/pki/private/{client_name}.key",
            f"{EASYRSA_DIR}/pki/reqs/{client_name}.req",
            f"{EASYRSA_DIR}/pki/inline/{client_name}.inline",
            f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
        ]
        
        for file_path in files_to_delete:
            if os.path.exists(file_path):
                os.remove(file_path)
        
        # Remove from index.txt by creating a new file without this client
        index_file = f"{EASYRSA_DIR}/pki/index.txt"
        if os.path.exists(index_file):
            with open(index_file, 'r') as f:
                lines = f.readlines()
            
            with open(index_file, 'w') as f:
                for line in lines:
                    if f'/CN={client_name}' not in line:
                        f.write(line)
        
        return jsonify({
            'success': True, 
            'message': f'Client {client_name} completely deleted'
        })
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error deleting client: {str(e)}'}), 500


@app.route('/api/server/restart', methods=['POST'])
@requires_auth
def restart_server():
    """Restart OpenVPN server"""
    stdout, stderr = run_command(['systemctl', 'restart', 'openvpn-server@server'])
    
    if stderr:
        return jsonify({'success': False, 'message': f'Error restarting server: {stderr}'}), 500
    
    return jsonify({'success': True, 'message': 'Server restarted successfully'})


@app.route('/api/server/status')
@requires_auth
def server_status():
    """Get server status and statistics"""
    server_info = get_server_info()
    connected = get_connected_clients()
    
    return jsonify({
        'server_info': server_info,
        'connected_count': len(connected),
        'connected_clients': connected
    })


if __name__ == '__main__':
    # Enable status logging if not already enabled
    config_file = f"{OPENVPN_DIR}/server.conf"
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            content = f.read()
            if 'status /var/log/openvpn/status.log' not in content:
                print("Note: Add 'status /var/log/openvpn/status.log' to server.conf for connection monitoring")
    
    # Run the app
    app.run(host='0.0.0.0', port=5000, debug=False)
