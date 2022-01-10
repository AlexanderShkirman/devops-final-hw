terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
        region = "eu-central-1"
        shared_credentials_file = "~/.aws/credentials"
}

resource "aws_vpc" "myvpc" {
  cidr_block = "10.12.0.0/16"
}

resource "aws_subnet" "public-01" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.12.0.0/18"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-01"
  }
}

resource "aws_subnet" "public-02" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.12.64.0/18"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-02"
  }
}

resource "aws_internet_gateway" "myigw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "myigw"
  }
}

resource "aws_route_table" "myrt" {
  vpc_id = aws_vpc.myvpc.id

  route = [
    {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.myigw.id
      carrier_gateway_id         = ""
      destination_prefix_list_id = ""
      egress_only_gateway_id     = ""
      instance_id                = ""
      ipv6_cidr_block            = ""
      local_gateway_id           = ""
      nat_gateway_id             = ""
      network_interface_id       = ""
      transit_gateway_id         = ""
      vpc_endpoint_id            = ""
      vpc_peering_connection_id  = ""
    }
  ]

  tags = {
    Name = "myroutetable"
  }
}


resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.myvpc.id
  route_table_id = aws_route_table.myrt.id
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "allow web inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress = [
    {
      description      = "web from world"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]

egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]

  tags = {
    Name = "allow_web"
  }
}

resource "aws_security_group" "allow_elb" {
  name        = "allow_elb"
  description = "Allow ELB inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress = [
    {
      description      = "From ELB to EC2"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = []
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = [aws_security_group.allow_web.id]
      self = false
    }
  ]
egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]


  tags = {
    Name = "allow_elb"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress = [
    {
      description      = "SSH from World"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]
egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]


  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_lb" "mylb" {
  name               = "myloadbalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_web.id]
  subnets            = [aws_subnet.public-01.id, aws_subnet.public-02.id ]

  enable_deletion_protection = false
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.mylb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mytg.arn
  }
}

resource "aws_lb_target_group" "mytg" {
  name        = "mytargetgroup"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.myvpc.id
}

resource "aws_lb_target_group_attachment" "testpython" {
  target_group_arn = aws_lb_target_group.mytg.arn
  target_id        = aws_instance.nginx_ec2.id
  port             = 80
}

resource "aws_key_pair" "ec2" {
  key_name   = "ec2"
  public_key = file("~/.ssh/ec2.pub")
}

resource "aws_instance" "nginx_ec2" {
  ami                    = "ami-05d34d340fb1d89e5"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.ec2.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id, aws_security_group.allow_elb.id]
  subnet_id              = aws_subnet.public-01.id
  root_block_device {
    volume_size          = 8
  }
  
user_data = <<-EOT
      #!/bin/bash
      sudo sudo amazon-linux-extras list | grep nginx
      sudo sudo amazon-linux-extras enable nginx1
      sudo sudo yum clean metadata
      sudo yum -y install nginx
      sudo systemctl start nginx
      echo "Shkirman Alexander</h1>" | sudo tee /usr/share/nginx/html/index.html
     EOT

  tags = {
    Name = "nginx_ec2"
  }
}


