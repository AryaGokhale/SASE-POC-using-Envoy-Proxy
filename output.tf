output "private_key_pem" {
    value = tls_private_key.key.private_key_pem
    sensitive = true
}

output "proxy_public_ip" {
  value = aws_eip.proxy_eip.public_ip
}

output "app_private_ip" {
  value = aws_instance.app_instance.private_ip
}

