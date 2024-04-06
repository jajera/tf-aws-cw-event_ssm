variable "use_case" {
  default = "tf-aws-cw_ssm"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_resourcegroups_group" "rg" {
  name        = "tf-rg-example-${random_string.suffix.result}"
  description = "Resource Group for ${var.use_case}"

  resource_query {
    query = <<JSON
    {
      "ResourceTypeFilters": [
        "AWS::AllSupported"
      ],
      "TagFilters": [
        {
          "Key": "UseCase",
          "Values": [
            "${var.use_case}"
          ]
        }
      ]
    }
    JSON
  }

  tags = {
    Name    = "tf-rg-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_role" "sfn" {
  name = "tf-iam-role-sfn-example-${random_string.suffix.result}"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name    = "tf-iam-role-sfn-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_policy" "cw_log_grp" {
  name ="tf-iam-policy-cw-log-grp-example-${random_string.suffix.result}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = "tf-iam-policy-cw-log-grp-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_role_policy_attachment" "cw_log_grp" {
  role       = aws_iam_role.sfn.name
  policy_arn = aws_iam_policy.cw_log_grp.arn
}

resource "aws_sfn_state_machine" "example" {
  name       = "tf-sfn-state-machine-example-${random_string.suffix.result}"
  role_arn   = aws_iam_role.sfn.arn
  type       = "EXPRESS"
  definition = <<EOF
{
  "Comment": "An AWS Step Functions state machine that reads a value from SSM Parameter Store and writes a new value.",
  "StartAt": "ReadAmiImageId",
  "States": {
    "ReadAmiImageId": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:ssm:getParameter",
      "Parameters": {
        "Name": "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
      },
      "ResultPath": "$.ParameterResult",
      "Next": "WriteAmiImageIdToLocal"
    },
    "WriteAmiImageIdToLocal": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:ssm:putParameter",
      "Parameters": {
        "Name": "/current/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2",
        "Value.$": "States.JsonToString($.ParameterResult.Parameter.Value)",
        "Type": "String",
        "Overwrite": true
      },
      "ResultPath": "$.NextResult",
      "End": true
    }
  }
}
EOF

  logging_configuration {
    include_execution_data = true
    level                  = "ALL"
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs.arn}:*"
  }

  tracing_configuration {
    enabled = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.cw_log_grp
  ]

  tags = {
    Name    = "tf-sfn-state-machine-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_cloudwatch_log_group" "sfn_logs" {
  name = "/aws/vendedlogs/states/example-${random_string.suffix.result}"

  tags = {
    Name    = "tf-log-group-sfn-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_cloudwatch_event_rule" "example" {
  name = "tf-cw-event-rule-example-${random_string.suffix.result}"

  event_pattern = jsonencode({
    "source" : ["aws.ssm"],
    "detail-type" : ["Parameter Store Change"],
    "resources" = ["arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"],
    "detail" : {
      "operation" : ["Create", "Update"]
    }
  })

  tags = {
    Name    = "tf-cw-event-rule-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_role" "eventbridge" {
  name = "tf-iam-role-eventbridge-example-${random_string.suffix.result}"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name    = "tf-iam-role-eventbridge-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

data "aws_iam_policy_document" "eventbridge_invoke" {
  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution"
    ]
    resources = [
      "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:tf-sfn-state-machine-example-${random_string.suffix.result}"
    ]
  }
}

resource "aws_iam_policy" "eventbridge_invoke" {
  name   = "tf-iam-policy-eventbridge-invoke-example-${random_string.suffix.result}"
  policy = data.aws_iam_policy_document.eventbridge_invoke.json

  tags = {
    Name    = "tf-iam-policy-eventbridge-invoke-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_role_policy_attachment" "eventbridge_invoke" {
  role       = aws_iam_role.eventbridge.name
  policy_arn = aws_iam_policy.eventbridge_invoke.arn
}

resource "aws_cloudwatch_event_target" "example" {
  rule      = aws_cloudwatch_event_rule.example.name
  target_id = "SendToStepFunction"
  arn       = aws_sfn_state_machine.example.arn
  role_arn  = aws_iam_role.eventbridge.arn
}

resource "aws_iam_policy" "ssm_put" {
  name = "tf-iam-policy-ssm-put-example-${random_string.suffix.result}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ssm:PutParameter"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/*"
      }
    ]
  })

  tags = {
    Name    = "tf-iam-policy-ssm-put-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_role_policy_attachment" "ssm_put" {
  role       = aws_iam_role.sfn.name
  policy_arn = aws_iam_policy.ssm_put.arn
}

resource "aws_iam_policy" "ssm_get" {
  name = "tf-iam-policy-ssm-get-example-${random_string.suffix.result}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ssm:GetParameter"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
      }
    ]
  })

  tags = {
    Name    = "tf-iam-policy-ssm-get-example-${random_string.suffix.result}"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_role_policy_attachment" "ssm_get" {
  role       = aws_iam_role.sfn.name
  policy_arn = aws_iam_policy.ssm_get.arn
}
