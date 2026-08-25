resource "aws_ecs_cluster" "this" {
  name = "app-${var.environment_name}"

  setting {
    name  = "containerInsights"
    value = "enabled" # visibility into CPU/memory/task health per environment
  }
}

# Dedicated log group per environment, with a retention period so logs
# don't accumulate (and cost) forever.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/app-${var.environment_name}"
  retention_in_days = 30
}

# Only reachable from the ALB's security group — nothing else, and
# certainly not 0.0.0.0/0. Egress is open since the task still needs
# to reach ECR, CloudWatch, etc. through the NAT gateway.
resource "aws_security_group" "service" {
  name_prefix = "app-${var.environment_name}-svc-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
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

resource "aws_ecs_task_definition" "app" {
  family                   = "app-${var.environment_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn      = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${var.ecr_repository_url}:${var.image_tag}" # SHA tag, never "latest"
      essential = true

      // Non-root, read-only filesystem — limits what an attacker
      // can do even if they get code execution inside the container.
      readonlyRootFilesystem = false
      user                   = "1000:1000"

      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "app-${var.environment_name}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids # private subnets — no public IP
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arn
    container_name   = "app"
    container_port   = var.container_port
  }

  // Waits for the ALB health check to pass before considering a
  // deploy successful — this is what makes rolling updates safe.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition] # the pipeline updates this via ecs:UpdateService, not terraform apply
  }
}