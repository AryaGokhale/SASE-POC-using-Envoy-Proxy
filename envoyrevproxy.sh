#!/bin/bash
# Install Envoy (official Ubuntu package)
wget -O- https://apt.envoyproxy.io/signing.key | sudo gpg --dearmor -o /etc/apt/keyrings/envoy-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/envoy-keyring.gpg] https://apt.envoyproxy.io jammy main" | sudo tee /etc/apt/sources.list.d/envoy.list
sudo apt-get update
sudo apt-get install envoy
envoy --version

#Reverse proxy config 
#tee write to std output (terminal) and to file 
#change the socket address 
sudo tee /etc/envoy/envoy.yaml > /dev/null <<EOF
 
static_resources:
  listeners:
  - name: envoy_proxy_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 80
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          codec_type: AUTO
          route_config:
            name: proxy_to_sidecar_route
            virtual_hosts:
              - name: backend
                domains: ["*"]
                routes:
                  - match: { prefix: "/hello" }
                    route: 
                      cluster: hello_service
                      prefix_rewrite: "/"
                  - match: {prefix: "/gameserver"}
                    route: 
                      cluster: game_service
                      prefix_rewrite: "/"
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  - name: hello_service
    type: LOGICAL_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: hello_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${APP1_IP}
                port_value: 8000
  - name: game_service
    type: LOGICAL_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: game_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${APP2_IP}
                port_value: 8000

admin:
  access_log_path: /tmp/admin_access.log
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF

# # Start Envoy
# --- Systemd unit for Envoy ---
cat <<EOF | sudo tee /etc/systemd/system/envoy.service
[Unit]
Description=Envoy Reverse Proxy
After=network.target
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

echo "[INFO] Envoy Reverse Proxy setup complete at $(date)"