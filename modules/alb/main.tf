# Public-facing by design — this is the front door. Only 443 and a
# redirect-only 80 are open; nothing reaches the ECS tasks directly.
resource "aws_security_group" "alb" {
  name_prefix = "app-${var.environment_name}-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # only ever used to redirect to 443, never served directly
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The ALB itself is public-facing, but the ECS tasks are private. The ALB
# needs to be able to reach the tasks, so the ECS service's security group
# is allowed to receive traffic from the ALB's security group.
# The deletion_protection flag is true in prod so that the ALB can't be accidentally destroyed by a terraform destroy command.

resource "aws_lb" "this" {
  name                       = "app-${var.environment_name}"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = true # mitigates request smuggling via malformed headers
  idle_timeout               = 120   # seconds before the ALB closes an idle connection to a client
}

# target_type = "ip" because the service runs on Fargate (awsvpc mode) —
# targets are task ENIs, not EC2 instances.
# The health check path is configurable, but defaults to /health. The ALB will consider a target healthy if it returns a 200 response code.

resource "aws_lb_target_group" "app" {
  name        = "app-${var.environment_name}"
  port        = var.container_port
  protocol    = "HTTP" # TLS terminates at the ALB; ALB-to-task traffic stays inside the VPC
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  deregistration_delay = 30 # seconds to drain in-flight requests before a task is removed
}

# The ALB has two listeners: 443 for HTTPS traffic, and 80 for HTTP traffic that is redirected to 443. 
#The SSL policy disables old TLS 1.0/1.1 protocols, and the ACM certificate is used for HTTPS termination.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # disables old TLS 1.0/1.1
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Port 80 exists only to redirect — it never forwards traffic to the app.
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}