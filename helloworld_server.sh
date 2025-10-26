#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/setup.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[INFO] Starting instance bootstrap at $(date)"

# Wait for networking (DNS + NAT gateway) 
for i in {1..6}; do
  if ping -c1 -W2 google.com >/dev/null 2>&1; then
    echo "[INFO] Network ready"
    break
  fi
  echo "[WARN] Network not ready yet... retrying ($i/6)"
  sleep 10
done

# Update base system 
echo "[INFO] Updating apt packages"
sudo apt-get update -y

# Install dependencies & NGINX 
sudo apt-get install -y curl wget gnupg2 apt-transport-https lsb-release ca-certificates nginx

echo "[INFO] Starting NGINX"
sudo systemctl enable nginx
sudo systemctl restart nginx

# Create Hello World page 
echo "Hello World from $(hostname)" | sudo tee /var/www/html/index.html
echo "[INFO] Hello World page created"

# Install Envoy 
echo "[INFO] Installing Envoy"
curl -sL 'https://apt.envoyproxy.io/signing.key' | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/envoy.gpg
echo "deb [arch=$(dpkg --print-architecture)] https://apt.envoyproxy.io $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/envoy.list

# Retry apt-get install if first attempt fails (network may still be warming)
for i in {1..3}; do
  if sudo apt-get update -y && sudo apt-get install -y envoy; then
    echo "[INFO] Envoy installed successfully"
    break
  fi
  echo "[WARN] Envoy install attempt $i failed; retrying..."
  sleep 10
done

# Configure Envoy sidecar 
sudo mkdir -p /etc/envoy

sudo tee /etc/envoy/envoy.yaml > /dev/null <<'EOF'
static_resources:
  listeners:
  - name: sidecar_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8000
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: sidecar_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: nginx_service
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route: { cluster: hello_web }
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  clusters:
  - name: hello_web
    connect_timeout: 0.25s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: hello_web
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 80
admin:
  access_log_path: /tmp/admin_access.log
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF


# --- Systemd unit for Envoy ---
cat <<EOF | sudo tee /etc/systemd/system/envoy.service
[Unit]
Description=Envoy Sidecar Proxy for Hello World
After=network.target nginx.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/envoy -c /etc/envoy/envoy.yaml --log-level info
Restart=always
RestartSec=5s
User=root
StandardOutput=append:/var/log/envoy.log
StandardError=append:/var/log/envoy.err.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable envoy
sudo systemctl start envoy

echo "[INFO] Hello World sidecar setup complete at $(date)"