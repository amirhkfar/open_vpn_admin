from flask import Flask, render_template, jsonify, request, redirect, url_for, session, send_file
import subprocess
import re
import os
from datetime import datetime, timedelta
from functools import wraps
import secrets
import json

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(hours=24)

# Configuration
ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin')
EASYRSA_DIR = '/etc/openvpn/server/easy-rsa'
OPENVPN_DIR = '/etc/openvpn/server'
CLIENT_CONFIG_DIR = '/root'
STATUS_LOG = '/var/log/openvpn/status.log'
STATS_FILE = '/opt/openvpn-admin/client_stats.json'

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

def run_command(cmd, shell=False):
    """Run a shell command and return output"""
    env = os.environ.copy()
    env['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    
    if shell:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, env=env)
    else:
        result = subprocess.run(cmd.split(), capture_output=True, text=True, env=env)
    return result.stdout, result.stderr, result.returncode

def parse_openvpn_date(date_str):
    """Convert OpenVPN date format (YYMMDDHHMMSSZ) to readable date (YYYY-MM-DD)"""
    try:
        dt = datetime.strptime(date_str, '%y%m%d%H%M%SZ')
        return dt.strftime('%Y-%m-%d')
    except:
        return date_str

def format_bytes(bytes_val):
    """Convert bytes to human readable format"""
    try:
        bytes_val = int(bytes_val)
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_val < 1024.0:
                return f"{bytes_val:.2f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:.2f} PB"
    except:
        return "0 B"

def get_clients():
    """Get list of all OpenVPN clients"""
    clients = []
    index_file = f"{EASYRSA_DIR}/pki/index.txt"
    
    if not os.path.exists(index_file):
        return clients
    
    with open(index_file, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 6:
                status = 'Active' if parts[0] == 'V' else 'Revoked'
                expiry_date = parse_openvpn_date(parts[1])
                cn_match = re.search(r'/CN=([^/]+)', parts[5])
                if cn_match:
                    client_name = cn_match.group(1)
                    clients.append({
                        'name': client_name,
                        'status': status,
                        'expiry': expiry_date
                    })
    
    return clients

def get_connected_clients():
    """Get list of currently connected clients with usage data"""
    connected = {}
    
    if not os.path.exists(STATUS_LOG):
        return connected
    
    try:
        with open(STATUS_LOG, 'r') as f:
            lines = f.readlines()
        
        for line in lines:
            # Parse CLIENT_LIST entries - skip header line
            if line.startswith('CLIENT_LIST,') and 'Common Name' not in line:
                parts = line.strip().split(',')
                if len(parts) >= 13:  # Full CLIENT_LIST has 13 fields
                    client_name = parts[1]
                    
                    # Skip UNDEF clients
                    if client_name == 'UNDEF' or not client_name:
                        continue
                    
                    real_address = parts[2]
                    bytes_received = parts[5]
                    bytes_sent = parts[6]
                    connected_since = parts[7]
                    
                    connected[client_name] = {
                        'connected': True,
                        'ip': real_address.split(':')[0] if ':' in real_address else real_address,
                        'bytes_received': int(bytes_received) if bytes_received.isdigit() else 0,
                        'bytes_sent': int(bytes_sent) if bytes_sent.isdigit() else 0,
                        'connected_since': connected_since
                    }
    
    except Exception as e:
        print(f"Error reading status log: {e}")
        import traceback
        traceback.print_exc()
    
    return connected

def load_client_stats():
    """Load cumulative client statistics from file"""
    if os.path.exists(STATS_FILE):
        try:
            with open(STATS_FILE, 'r') as f:
                return json.load(f)
        except:
            pass
    return {}

def save_client_stats(stats):
    """Save cumulative client statistics to file"""
    try:
        with open(STATS_FILE, 'w') as f:
            json.dump(stats, f, indent=2)
    except Exception as e:
        print(f"Error saving stats: {e}")

def update_cumulative_stats():
    """Update cumulative statistics with current session data"""
    cumulative = load_client_stats()
    connected = get_connected_clients()
    
    for client_name, conn_info in connected.items():
        if client_name not in cumulative:
            cumulative[client_name] = {
                'total_sent': 0,
                'total_received': 0,
                'last_sent': 0,
                'last_received': 0
            }
        
        current_sent = conn_info.get('bytes_sent', 0)
        current_received = conn_info.get('bytes_received', 0)
        
        # If current session values are less than last recorded, it's a new session
        # Add the previous session's data to cumulative
        if current_sent < cumulative[client_name]['last_sent']:
            cumulative[client_name]['total_sent'] += cumulative[client_name]['last_sent']
        if current_received < cumulative[client_name]['last_received']:
            cumulative[client_name]['total_received'] += cumulative[client_name]['last_received']
        
        # Update last recorded values
        cumulative[client_name]['last_sent'] = current_sent
        cumulative[client_name]['last_received'] = current_received
    
    save_client_stats(cumulative)
    return cumulative

def get_server_stats():
    """Get overall server statistics"""
    clients = get_clients()
    connected_clients = get_connected_clients()
    
    total = len(clients)
    active = sum(1 for c in clients if c['status'] == 'Active')
    revoked = sum(1 for c in clients if c['status'] == 'Revoked')
    connected = len(connected_clients)
    
    # Calculate total bandwidth
    total_sent = sum(c.get('bytes_sent', 0) for c in connected_clients.values())
    total_received = sum(c.get('bytes_received', 0) for c in connected_clients.values())
    
    # Check server status
    stdout, _, _ = run_command('systemctl is-active openvpn-server@server')
    server_running = stdout.strip() == 'active'
    
    # Get server IP
    stdout, _, _ = run_command('hostname -I')
    server_ip = stdout.strip().split()[0] if stdout.strip() else 'Unknown'
    
    # Get server port and protocol from config
    server_port = 'Unknown'
    server_protocol = 'Unknown'
    config_file = '/etc/openvpn/server/server.conf'
    if os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                for line in f:
                    if line.startswith('port '):
                        server_port = line.split()[1].strip()
                    elif line.startswith('proto '):
                        server_protocol = line.split()[1].strip().upper()
        except:
            pass
    
    return {
        'total_clients': total,
        'active_clients': active,
        'revoked_clients': revoked,
        'connected_clients': connected,
        'server_running': server_running,
        'total_sent': total_sent,
        'total_received': total_received,
        'total_sent_formatted': format_bytes(total_sent),
        'total_received_formatted': format_bytes(total_received),
        'server_ip': server_ip,
        'server_port': server_port,
        'protocol': server_protocol
    }

# Routes
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
            session['logged_in'] = True
            session.permanent = True
            return redirect(url_for('dashboard'))
        else:
            return render_template('login.html', error='Invalid credentials')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def dashboard():
    stats = get_server_stats()
    return render_template('dashboard.html', stats=stats)

@app.route('/clients')
@login_required
def clients_page():
    # Update cumulative stats first
    cumulative_stats = update_cumulative_stats()
    
    clients = get_clients()
    connected_clients = get_connected_clients()
    
    # Calculate totals
    total_cumulative_sent = 0
    total_cumulative_received = 0
    
    # Merge client data with connection info
    for client in clients:
        conn_info = connected_clients.get(client['name'], {})
        client['connected'] = conn_info.get('connected', False)
        client['real_address'] = conn_info.get('ip', '')
        
        # Current session data (only for connected clients)
        current_sent = conn_info.get('bytes_sent', 0) if client['connected'] else 0
        current_received = conn_info.get('bytes_received', 0) if client['connected'] else 0
        
        # Get cumulative data from stats file
        client_cumulative = cumulative_stats.get(client['name'], {})
        # Add current session to the stored cumulative
        cumulative_sent = client_cumulative.get('total_sent', 0) + client_cumulative.get('last_sent', 0)
        cumulative_received = client_cumulative.get('total_received', 0) + client_cumulative.get('last_received', 0)
        
        # Store both current and cumulative
        client['bytes_sent'] = format_bytes(current_sent) if client['connected'] else '-'
        client['bytes_received'] = format_bytes(current_received) if client['connected'] else '-'
        client['cumulative_sent'] = format_bytes(cumulative_sent)
        client['cumulative_received'] = format_bytes(cumulative_received)
        
        # Add to totals
        total_cumulative_sent += cumulative_sent
        total_cumulative_received += cumulative_received
        
        client['expiry_date'] = client.get('expiry', 'N/A')
        
        # Check if client has duplicate-cn enabled
        config_file = f"{CLIENT_CONFIG_DIR}/{client['name']}.ovpn"
        client['allow_multi_connection'] = False
        if os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    content = f.read()
                    client['allow_multi_connection'] = 'duplicate-cn' in content
            except:
                pass
    
    return render_template('clients.html', 
                         clients=clients,
                         total_cumulative_sent=format_bytes(total_cumulative_sent),
                         total_cumulative_received=format_bytes(total_cumulative_received))

# API Routes
@app.route('/api/stats')
@login_required
def api_stats():
    return jsonify(get_server_stats())

@app.route('/api/clients')
@login_required
def api_clients():
    clients = get_clients()
    connected_clients = get_connected_clients()
    
    for client in clients:
        conn_info = connected_clients.get(client['name'], {})
        client['connected'] = conn_info.get('connected', False)
        client['ip'] = conn_info.get('ip', '')
        client['bytes_sent'] = conn_info.get('bytes_sent', 0)
        client['bytes_received'] = conn_info.get('bytes_received', 0)
        client['bytes_sent_formatted'] = format_bytes(conn_info.get('bytes_sent', 0))
        client['bytes_received_formatted'] = format_bytes(conn_info.get('bytes_received', 0))
    
    return jsonify(clients)

@app.route('/api/add_client', methods=['POST'])
@login_required
def add_client():
    data = request.get_json()
    client_name = data.get('name', '').strip()
    expiry_days = int(data.get('expiry_days', 365))
    allow_duplicate = data.get('allow_duplicate', False)
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    
    try:
        # Generate client certificate
        gen_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days={expiry_days} build-client-full {client_name} nopass"
        stdout, stderr, code = run_command(gen_cmd, shell=True)
        
        if code != 0 and 'already exists' not in stderr:
            return jsonify({'success': False, 'message': f'Error creating certificate: {stderr}'}), 500
        
        # Generate config file
        inline_file = f"{EASYRSA_DIR}/pki/inline/{client_name}.inline"
        
        if os.path.exists(inline_file):
            ovpn_cmd = f"grep -vh '^#' {OPENVPN_DIR}/client-common.txt {inline_file} > {CLIENT_CONFIG_DIR}/{client_name}.ovpn"
        else:
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
        
        # Add duplicate-cn if requested
        if allow_duplicate:
            dup_cmd = f"echo 'duplicate-cn' >> {CLIENT_CONFIG_DIR}/{client_name}.ovpn"
            run_command(dup_cmd, shell=True)
        
        return jsonify({'success': True, 'message': f'Client {client_name} created successfully'})
    
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/revoke_client', methods=['POST'])
@login_required
def revoke_client():
    data = request.get_json()
    client_name = data.get('name', '').strip()
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    
    try:
        revoke_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch revoke {client_name}"
        run_command(revoke_cmd, shell=True)
        
        crl_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days=3650 gen-crl"
        run_command(crl_cmd, shell=True)
        
        update_crl_cmd = f"cp {EASYRSA_DIR}/pki/crl.pem {OPENVPN_DIR}/crl.pem && chown nobody:nogroup {OPENVPN_DIR}/crl.pem 2>/dev/null || chown nobody:nobody {OPENVPN_DIR}/crl.pem"
        run_command(update_crl_cmd, shell=True)
        
        return jsonify({'success': True, 'message': f'Client {client_name} revoked successfully'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/delete_client', methods=['POST'])
@login_required
def delete_client():
    data = request.get_json()
    client_name = data.get('name', '').strip()
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    
    try:
        revoke_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch revoke {client_name} 2>/dev/null || true"
        run_command(revoke_cmd, shell=True)
        
        crl_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days=3650 gen-crl"
        run_command(crl_cmd, shell=True)
        
        update_crl_cmd = f"cp {EASYRSA_DIR}/pki/crl.pem {OPENVPN_DIR}/crl.pem && chown nobody:nogroup {OPENVPN_DIR}/crl.pem 2>/dev/null || chown nobody:nobody {OPENVPN_DIR}/crl.pem"
        run_command(update_crl_cmd, shell=True)
        
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
        
        index_file = f"{EASYRSA_DIR}/pki/index.txt"
        if os.path.exists(index_file):
            with open(index_file, 'r') as f:
                lines = f.readlines()
            
            with open(index_file, 'w') as f:
                for line in lines:
                    if f'/CN={client_name}' not in line:
                        f.write(line)
        
        return jsonify({'success': True, 'message': f'Client {client_name} completely deleted'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/edit_client', methods=['POST'])
@login_required
def edit_client():
    data = request.get_json()
    client_name = data.get('name', '').strip()
    allow_duplicate = data.get('allow_duplicate', False)
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    config_file = f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
    
    if not os.path.exists(config_file):
        return jsonify({'success': False, 'message': 'Config file not found'}), 404
    
    try:
        with open(config_file, 'r') as f:
            lines = f.readlines()
        
        has_duplicate_cn = any('duplicate-cn' in line for line in lines)
        
        with open(config_file, 'w') as f:
            for line in lines:
                if 'duplicate-cn' not in line:
                    f.write(line)
            
            if allow_duplicate:
                f.write('duplicate-cn\n')
        
        return jsonify({'success': True, 'message': f'Client {client_name} updated successfully'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/extend_expiry', methods=['POST'])
@login_required
def extend_expiry():
    data = request.get_json()
    client_name = data.get('name', '').strip()
    extend_days = int(data.get('days', 365))
    
    if not client_name:
        return jsonify({'success': False, 'message': 'Client name is required'}), 400
    
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    
    try:
        renew_cmd = f"cd {EASYRSA_DIR} && ./easyrsa --batch --days={extend_days} renew {client_name} nopass"
        run_command(renew_cmd, shell=True)
        
        inline_file = f"{EASYRSA_DIR}/pki/inline/{client_name}.inline"
        
        if os.path.exists(inline_file):
            ovpn_cmd = f"grep -vh '^#' {OPENVPN_DIR}/client-common.txt {inline_file} > {CLIENT_CONFIG_DIR}/{client_name}.ovpn"
        else:
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
        
        return jsonify({'success': True, 'message': f'Certificate for {client_name} extended by {extend_days} days'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/download_config/<client_name>')
@login_required
def download_config(client_name):
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    config_file = f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
    
    if os.path.exists(config_file):
        return send_file(config_file, as_attachment=True, download_name=f"{client_name}.ovpn")
    else:
        return jsonify({'error': 'Config file not found'}), 404

@app.route('/api/config_base64/<client_name>')
@login_required
def config_base64(client_name):
    import base64
    
    client_name = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)
    config_file = f"{CLIENT_CONFIG_DIR}/{client_name}.ovpn"
    
    if os.path.exists(config_file):
        with open(config_file, 'rb') as f:
            content = f.read()
        
        encoded = base64.b64encode(content).decode('utf-8')
        return jsonify({'success': True, 'base64': encoded, 'name': client_name})
    else:
        return jsonify({'success': False, 'message': 'Config file not found'}), 404

@app.route('/api/server/restart', methods=['POST'])
@login_required
def restart_server():
    try:
        run_command('systemctl restart openvpn-server@server', shell=True)
        return jsonify({'success': True, 'message': 'Server restarted successfully'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
