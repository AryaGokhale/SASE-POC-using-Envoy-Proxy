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
    #image_id = "ami-004f01eab3cd7e439" 
    image_id = data.aws_ami.ubuntu.id
    # iam_instance_profile {
    #   name = "ecsInstanceRole"
    # }

    #general purpose ssd 

    block_device_mappings {
        device_name = "/dev/sda1"
        ebs {
          volume_size = 30
          volume_type = "gp3"
        }
    }

    # network_interfaces {
    #     associate_public_ip_address = true
    #     security_groups = [aws_security_group.envoy_sg.id]
    #     delete_on_termination = true
    # }

    tag_specifications {
      resource_type = "instance"
      tags = {
        Name = "ecs_instance"
      }
    }

    #user data
    user_data = base64encode(file("${path.module}/helloworld_server.sh"))
}

resource "aws_instance" "ecs_instance" {
    count = 1
    subnet_id = aws_subnet.public_subnet[0].id
    launch_template {
        id = aws_launch_template.ecs_launch_template.id
        version = "$Latest" #refers to the latest version of launch template

    }
    tags = {
        Name = "ecs template instance"
    }
}