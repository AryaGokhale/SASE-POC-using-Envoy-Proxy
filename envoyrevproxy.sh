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
              - match: { prefix: "/" }
                route: { cluster: backend_service }
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  - name: backend_service
    type: LOGICAL_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: backend_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${SIDECAR_IP}
                port_value: 8000

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