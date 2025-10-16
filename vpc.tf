#VPC & Networking

resource "aws_vpc" "envoy_vpc" {
    
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "envoy vpc"
    }
    enable_dns_support = true
    enable_dns_hostnames = true
}

#add nat for ecs and envoy 

resource "aws_subnet" "public_subnet" {
    count = length(var.public_subnet)
    vpc_id = aws_vpc.envoy_vpc.id
    cidr_block = var.public_subnet[count.index]
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true #assign public IP to instances launched in this subnet
    tags = {
        Name = "envoy public subnet"
    }
}

resource "aws_subnet" "private_subnet" {
    count = length(var.private_subnet)
    vpc_id = aws_vpc.envoy_vpc.id
    cidr_block = var.private_subnet[count.index]
    availability_zone = "us-east-1a"

    tags = {
        Name = "envoy private subnet"
    }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.envoy_vpc.id
  tags = { 
    Name = "envoy internet gateway"
  }  
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.envoy_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "envoy public route table"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count = length(var.public_subnet)
  subnet_id = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}


#really bad config will change
resource "aws_security_group" "envoy_sg" {
  name        = "envoy_sg"
  description = "Allow inbound traffic for Envoy"
  vpc_id = aws_vpc.envoy_vpc.id

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all inbound traffic"
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}