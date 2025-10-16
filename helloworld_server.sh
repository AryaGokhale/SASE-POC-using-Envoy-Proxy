#!/bin/bash
set -e

# Update system

# Install nginx
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx

# Create a hello world page
echo "Hello World from $(hostname)" > /var/www/html/index.html

# Install Envoy (official Ubuntu package)
wget -O- https://apt.envoyproxy.io/signing.key | sudo gpg --dearmor -o /etc/apt/keyrings/envoy-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/envoy-keyring.gpg] https://apt.envoyproxy.io jammy main" | sudo tee /etc/apt/sources.list.d/envoy.list
sudo apt-get update
sudo apt-get install envoy
envoy --version

# Write Envoy config
# mkdir -p /etc/envoy
sudo tee /etc/envoy/envoy.yaml > /dev/null <<'EOF'
static_resources:
  listeners:
  - name: envoy_sidecar_listener
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
    type: LOGICAL_DNS
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


# # Start Envoy
sleep 3
nohup envoy -c /etc/envoy/envoy.yaml --log-level info &