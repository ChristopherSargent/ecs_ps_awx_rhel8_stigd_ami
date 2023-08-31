# Our default security group to access EC2 instances over SSH and HTTP.
resource "aws_security_group" "default" {
  name        = "ps-awx01-terraform-sg"
  description = "Used in the terraform"
  vpc_id      = var.vpc_id

  # SSH access from HH and VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All traffic from ps-awx01-terraform-sg-alb
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.alb.id]
  }
}

# alb security group.
resource "aws_security_group" "alb" {
  name        = "ps-awx01-terraform-sg-alb"
  description = "Terraform load balancer security group"
  vpc_id      = var.vpc_id

  # ALB HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_alb_ingress_cidr
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# AWS application load balancer.
resource "aws_alb" "alb" {
  name            = "ps-awx01-terraform-alb"
  subnets         = var.subnets
  security_groups = [aws_security_group.alb.id]
}

# Target group alb 443.
resource "aws_alb_target_group" "group" {
  name     = "ps-awx01-terraform-tg-alb"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = var.vpc_id

  stickiness {
    type = "lb_cookie"
  }

  # Alter the destination of the health check to be the login page.
  health_check {
    path = "/#/login"
    port = 443
  }
}

# alb listener https.
resource "aws_alb_listener" "listener_https" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    target_group_arn = aws_alb_target_group.group.arn
    type             = "forward"
  }
}

# ec2 instance
resource "aws_instance" "ps-awx01-terraform-ec2" {
  ami                         = "ami-0467aa727fd3deae5"
  associate_public_ip_address = false
  availability_zone           = "us-gov-west-1a"
  enclave_options {
    enabled = false
  }

  get_password_data                    = false
  hibernation                          = false
  instance_initiated_shutdown_behavior = "stop"
  instance_type                        = var.instance_type
  ipv6_address_count                   = 0
  key_name                             = "ECE-Installer-20200811_010627"

  maintenance_options {
    auto_recovery = "default"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = "1"
    http_tokens                 = "optional"
    instance_metadata_tags      = "disabled"
  }

  monitoring = true

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.kms_key_id
    volume_size           = 128
    volume_type           = "gp2"
  }

  source_dest_check = true
  subnet_id         = element(var.subnets, 0)

  tags = {
    Environment = "PS"
    Name        = "ps-awx01-terraform-ec2"
  }

  tags_all = {
    Environment = "PS"
    Name        = "ps-awx01-terraform-ec2"
  }

  tenancy                = "default"
  vpc_security_group_ids = [aws_security_group.default.id]
}

# Register EC2 instance to Target Group
resource "aws_lb_target_group_attachment" "register" {
  target_group_arn = aws_alb_target_group.group.arn
  target_id        = aws_instance.ps-awx01-terraform-ec2.id
  port             = 443
}
