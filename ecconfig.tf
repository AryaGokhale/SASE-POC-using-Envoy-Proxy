resource "tls_private_key" "key" {
    algorithm = "RSA"
    rsa_bits  = 4096
}

resource "aws_key_pair" "test_server" {
    key_name   = "test_server"
    public_key = tls_private_key.key.public_key_openssh
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_launch_template" "ecs_launch_template" {
    name = "ecs_launch_template"
    instance_type = "t3.micro"
    vpc_security_group_ids = [aws_security_group.envoy_sg.id]
    key_name = aws_key_pair.test_server.key_name
 
    image_id = data.aws_ami.ubuntu.id
    block_device_mappings {
        device_name = "/dev/sda1"
        ebs {
          volume_size = 30
          volume_type = "gp3"
        }
    }

    tag_specifications {
      resource_type = "instance"
      tags = {
        Name = "ecs_instance"
      }
    }
}

resource "aws_instance" "app_instance" {

    subnet_id = aws_subnet.private_subnet[0].id
    launch_template {
        id = aws_launch_template.ecs_launch_template.id
        version = "$Latest" #refers to the latest version of launch template

    }
    tags = {
        Name = "hello_world_service"
    }
    user_data = base64encode(file("${path.module}/helloworld_server.sh"))
}

resource "aws_instance" "app2_instance" {

  subnet_id = aws_subnet.private_subnet[1].id
  launch_template {
    id = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  tags = {
    Name = "game service"
  }

  user_data = base64encode(file("${path.module}/game_service.sh"))
}
resource "aws_instance" "proxy_instance" {
    
    subnet_id = aws_subnet.public_subnet[0].id
    launch_template {
        id = aws_launch_template.ecs_launch_template.id
        version = "$Latest"
    }

    user_data = base64encode(templatefile("${path.module}/envoyrevproxy.sh", {
      APP1_IP = aws_instance.app_instance.private_ip,
      APP2_IP = aws_instance.app2_instance.private_ip
    }))

    tags = {
        Name = "envoy_reverse_proxy"
    }

}

resource "aws_eip" "proxy_eip" {
  domain = "vpc"  
}

resource "aws_eip_association" "proxy_eip_assoc" {
    instance_id = aws_instance.proxy_instance.id
    allocation_id = aws_eip.proxy_eip.id
    
}