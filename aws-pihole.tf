provider "aws" {
  region = "eu-west-2"
}

resource "aws_vpc" "pihole-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "pihole-vpc"
  }
}

resource "aws_internet_gateway" "pihole-igw" {
  vpc_id = aws_vpc.pihole-vpc.id

  tags = {
    Name = "pihole-igw"
  }
}

resource "aws_route_table" "pihole-rt" {
  vpc_id = aws_vpc.pihole-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pihole-igw.id
  }

  tags = {
    Name = "pihole-rt"
  }
}

resource "aws_subnet" "pihole-public-subnet" {
  vpc_id                  = aws_vpc.pihole-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "pihole public subnet"
  }
}

resource "aws_subnet" "pihole-private-subnet" {
  vpc_id     = aws_vpc.pihole-vpc.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "pihole private subnet"
  }
}

# Associate the route table to the public subnet
resource "aws_route_table_association" "rt-igw-association" {
  # Public subnet ID
  subnet_id = aws_subnet.pihole-public-subnet.id

  # Route table ID
  route_table_id = aws_route_table.pihole-rt.id
}

resource "aws_eip" "pihole-eip" {
  instance = aws_instance.pihole.id
  vpc      = true

  tags = {
    Name = "pihole elastic IP"
  }
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"] 
}

data "aws_region" "current" {}

resource "aws_instance" "pihole" {
  ami           = data.aws_ami.amazon-linux-2.id
  instance_type = "t2.micro"
  key_name      = "eupihole"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.pihole-public-subnet.id
  vpc_security_group_ids      = [aws_security_group.pihole-sg.id]
  depends_on = [
    aws_internet_gateway.pihole-igw
  ]

  tags = {
    Name = "pihole"
  }

  user_data = <<-EOF
              #!/bin/bash
              cd /home/ec2-user
              yum update
              yum install -y docker python3-pip && pip3 install docker-compose
              systemctl enable docker.service
              systemctl start docker.service
              mkdir -p /home/ec2-user/scripts/docker
              cd /home/ec2-user/scripts/docker
              usermod -a -G docker ec2-user
              newgrp docker
              wget https://raw.githubusercontent.com/pheistman/dockerpihole/master/docker-compose.yml
              docker-compose up -d
              EOF
}

resource "aws_security_group" "pihole-sg" {
  name   = "pihole-sg"
  vpc_id = aws_vpc.pihole-vpc.id
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TCP DNS resolution from home IP only"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "UDP DNS resolution from home IP only"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "portainer-container-gui"
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "Allow all traffic to port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

output "instance_public_ip" {
  value       = aws_instance.pihole.public_ip
  description = "pihole public IP"
}