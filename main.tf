terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# AMI oficial de Ubuntu 24.04 LTS
data "aws_ami" "ubuntu_2404" {
  owners      = ["099720109477"]
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# VPC por defecto
data "aws_vpc" "default" {
  default = true
}

# Subnets de la VPC por defecto
data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#Security Group para Base de Datos
resource "aws_security_group" "mysql_firewall" {
  name   = "mysql_firewall"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MySQL desde la VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  ingress {
    description = "ICMP ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "mysql_firewall" }
}

#Security Group para FTP
resource "aws_security_group" "vsftpd_firewall" {
  name   = "vsftpd_firewall"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FTP control"
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FTP pasivo datos"
    from_port   = 40000
    to_port     = 40100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vsftpd_firewall" }
}


#Instancia BD
resource "aws_instance" "ubuntu_bd" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnets.default_subnets.ids[0]
  vpc_security_group_ids = [aws_security_group.mysql_firewall.id]
  key_name               = "vockey"

  user_data = file("${path.module}/scripts/mysql.sh")

  tags = { Name = "mariadb_tf" }
}

#Instancia FTP
resource "aws_instance" "ubuntu_ftp" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnets.default_subnets.ids[0]
  vpc_security_group_ids = [aws_security_group.vsftpd_firewall.id]
  key_name               = "vockey"

  user_data = templatefile("${path.module}/scripts/ftp.sh", {
    ftp_public_ip = aws_eip.ftp_eip.public_ip,
    bd_private_ip = aws_instance.ubuntu_bd.private_ip
  })

  tags = { Name = "vsftpd_tf" }

}

#Elastic IP para FTP
resource "aws_eip" "ftp_eip" {
  domain = "vpc"
  tags   = { Name = "vsftpd_tf_eip" }
}


resource "aws_eip_association" "ftp_eip_assoc" {
  instance_id   = aws_instance.ubuntu_ftp.id
  allocation_id = aws_eip.ftp_eip.id
}


#Información de las instancias
output "bd_public_ip" {
  value = aws_instance.ubuntu_bd.public_ip
}

output "bd_private_ip" {
  value = aws_instance.ubuntu_bd.private_ip
}

output "ftp_public_ip" {
  value = aws_eip.ftp_eip.public_ip
}

output "ftp_private_ip" {
  value = aws_instance.ubuntu_ftp.private_ip
}

output "ftp_elastic_ip" {
  value = aws_eip.ftp_eip.public_ip
}

output "subnet_id_used" {
  value = aws_instance.ubuntu_bd.subnet_id
}