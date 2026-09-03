# Both roles are assumed by the ECS tasks service — the trust policy
# is identical for both, only the permissions differ.
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# EXECUTION role: used by the ECS agent, not your app code. Pulls the
# image from ECR and ships logs to CloudWatch. AWS ships a managed
# policy for exactly this — no need to hand-write it.
resource "aws_iam_role" "execution" {
  name               = "ecs-task-execution-${var.environment_name}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# TASK role: assumed by YOUR APPLICATION CODE at runtime. Starts with
# zero permissions on purpose — add statements here only as the app
# actually needs specific AWS services, scoped to specific resources.
# Never attach AdministratorAccess or a broad managed policy here.
resource "aws_iam_role" "task" {
  name               = "ecs-task-${var.environment_name}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

# Intentionally empty placeholder policy — replace with statements for
# whatever the app actually calls (e.g. a specific S3 bucket, a specific
# Secrets Manager secret) once you know what that is.
resource "aws_iam_role_policy" "task_placeholder" {
  name = "app-permissions"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*" # narrow this to the specific log group ARN once wired to ecs-service
    }]
  })
}