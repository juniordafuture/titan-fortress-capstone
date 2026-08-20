provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "tkh_fortress" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "TKH-Fortress-VPC"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.tkh_fortress.id
  tags = {
    Name = "TKH-Internet-Gateway"
  }
}

resource "aws_subnet" "public_courtyard" {
  vpc_id                   = aws_vpc.tkh_fortress.id
  cidr_block               = "10.0.1.0/24"
  # trivy:ignore:AVD-AWS-0164 -- intentional: this subnet hosts the required public-facing web server
  map_public_ip_on_launch  = true
  tags = {
    Name = "Public-Courtyard"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.tkh_fortress.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "Public-Route-Table"
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_courtyard.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Allow HTTP and restricted SSH access"
  vpc_id      = aws_vpc.tkh_fortress.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from home IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["148.75.195.246/32"]
  }

  # trivy:ignore:AVD-AWS-0104 -- intentional: outbound access required for yum to reach AWS package repos
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "TKH-Web-Server-SG"
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_courtyard.id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-USERDATA
              #!/bin/bash
              yum install -y httpd
              systemctl start httpd
              USERDATA

  tags = {
    Name = "TKH-Web-Server"
  }
}
