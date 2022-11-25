terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  cloud {
    organization = "if20b034-terraform-workshop"

    workspaces {
      name = "Terraform-Workshop"
    }
  }
}
variable "AWS_ACCESS_KEY_ID" {
  type    = string
  default = {}
}
variable "AWS_SECRET_ACCESS_KEY" {
  type    = string
  default = {}
}

# Configure the AWS Provider
# Use the AWS provider

provider "aws" {
  region     = "us-east-1"
  access_key = var.AWS_ACCESS_KEY_ID
  secret_key = var.AWS_SECRET_ACCESS_KEY
  token      = "FwoGZXIvYXdzEEkaDGFzLlPohyRqd1gdhyLLARG6ZnH/SbaG0a0DNZVs7v0Bi26HTjJ0h9jSo1OYb5J7Hy7jalHPlcZfb48sYndfhtvKiBROwwJ+wL++SFcnZBDO2iqc1s7k+cGB2JaMA+w8QwOmQif5LS04yvC+dTQX1cfvLHJIhmGa8jBL/WIm3IjeTa83+AOgkvgD0ZZTpeQQaiGs0OBsvodznTe7EwyaMxadPPkHR8U1tIJn93WVh7dA+d4/aNOXFVF/27qMvHa12v4RRUZxVZ5SKYtKDOK6Z1ExPRhVxTiSB/jtKKzk3JsGMi0rBddcDrt/T48DVtY8bnykp/oJ7R59elYbNlQUy2TXq3WBOtXEH5lJfTMIlnc="
}

#	Create a VPC
resource "aws_vpc" "Nuri" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "Terraform3"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.Nuri.id

  tags = {
    Name = "Terraform3"
  }
}

# Create a custom route table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.Nuri.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Terraform3"
  }
}

# Create a subnet
resource "aws_subnet" "su" {
  vpc_id            = aws_vpc.Nuri.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Terraform3"
  }
}
# Associate subnet with route table
resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.su.id
  route_table_id = aws_route_table.rt.id
}

#Create a security group
resource "aws_security_group" "terraform3" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.Nuri.id

  #TCP port 80
  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  #Allow everything
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "Terraform3"
  }
}

#lockup for Ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Create a network interface with an IP in the subnet
resource "aws_network_interface" "ni" {
  subnet_id       = aws_subnet.su.id
  private_ips     = ["10.0.1.10"]
  security_groups = [aws_security_group.terraform3.id]

  # attachment {
  #   instance     = aws_instance.ec2-terraform2.id
  #   device_index = 1
  # }
}

# Assign an elastic IP to the network interface
resource "aws_eip" "oneipe" {
  vpc                       = true
  network_interface         = aws_network_interface.ni.id
  associate_with_private_ip = "10.0.1.10"
  depends_on                = [aws_internet_gateway.gw]
}

# Create an AWS EC2 instance
resource "aws_instance" "ec2-terraform3" {
  #Use Ubuntu
  ami = data.aws_ami.ubuntu.id
  #Use t2.micro
  instance_type = "t2.micro"
  #associate public ip address: true
  # associate_public_ip_address = true
  # vpc_security_group_ids = [aws_security_group.terraform2.id]

  # Create more than one instance
  count = 4
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.ni.id
  }
  #user data: Start an Apache web server (code below)
  user_data = file("userdata.sh")
}

resource "aws_elb" "loadBa" {
  name               = "loadBa-terraform-elb"
  availability_zones = ["us-east-1a"]

  access_logs {
    bucket        = "load"
    bucket_prefix = "ba"
    interval      = 60
  }

  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  # listener {
  #   instance_port      = 8000
  #   instance_protocol  = "http"
  #   lb_port            = 443
  #   lb_protocol        = "https"
  #   ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  # }

  # health_check {
  #   healthy_threshold   = 2
  #   unhealthy_threshold = 2
  #   timeout             = 3
  #   target              = "HTTP:8000/"
  #   interval            = 30
  # }
  instances                   = aws_instance.ec2-terraform3.*.id
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "loadba-terraform-elb"
  }
}

#Output the public DNS address of the instance
output "public_dns" {
  description = "The public DNS name assigned to the instance. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value       = try(aws_elb.loadBa.dns_name, "")
}

# Token = CX6idzbbOR7Xvw.atlasv1.pBZeK4Py8xBUvMFYnwQU13T4VUwZAbkBaaJCjpKXauuX4esQlZSRGkJltOHyih9nNAE
