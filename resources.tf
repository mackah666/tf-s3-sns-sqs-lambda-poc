# ---------------------------------------------------------------------------------------------------------------------
# KMS KEY
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kms_key" "symphony_key" {
  description             = "KMS key Symphony non prod environments"
  # deletion_window_in_days = 10
  tags = {
    Name = "Symphony Key"
    Environment = "Non Prod"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS KEY ALIAS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_kms_alias" "symphony_key" {
  name          = "alias/symphony-non-prod-key"
  target_key_id = aws_kms_key.symphony_key.key_id
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "bucket" {
  bucket = "symphony-bucket-0001"
  tags = {
    Name = "Symphony S3 Bucket"
    Environment = "Non Prod"
  }
}
# ---------------------------------------------------------------------------------------------------------------------
# SNS TOPIC
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sns_topic" "symphony_updates" {
    name = "symphony-updates-topic"

    tags = {
    Name = "Symphony Topic"
    Environment = "Non Prod"
  }

    policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[{
        "Effect": "Allow",
        "Principal": {"AWS":"*"},
        "Action": "SNS:Publish",
        "Resource": "arn:aws:sns:*:*:symphony-updates-topic",
        "Condition":{
            "ArnLike":{"aws:SourceArn":"${aws_s3_bucket.bucket.arn}"}
        }
    }]
}
POLICY
}



# ---------------------------------------------------------------------------------------------------------------------
# S3 BUCKET TOPIC NOTIFICATION
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  topic {
    topic_arn     = aws_sns_topic.symphony_updates.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".json"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SQS QUEUE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sqs_queue" "symphony_updates_queue" {
    name = "symphony-updates-queue"
    redrive_policy  = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.symphony_updates_dl_queue.arn}\",\"maxReceiveCount\":5}"
    visibility_timeout_seconds = 300

    tags = {
        Environment = "Non Prod"
    }
}


resource "aws_sqs_queue" "symphony_updates_dl_queue" {
    name = "symphony-updates-dl-queue"
}

# ---------------------------------------------------------------------------------------------------------------------
# SQS POLICY
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sqs_queue_policy" "symphony_updates_queue_policy" {
    queue_url = aws_sqs_queue.symphony_updates_queue.id

    policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.symphony_updates_queue.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_sns_topic.symphony_updates.arn}"
        }
      }
    }
  ]
}
POLICY
}

# ---------------------------------------------------------------------------------------------------------------------
# SNS SUBSCRIPTION
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "symphony_updates_sqs_target" {
    topic_arn = aws_sns_topic.symphony_updates.arn
    protocol  = "sqs"
    endpoint  = aws_sqs_queue.symphony_updates_queue.arn
}



# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA ROLE & POLICIES
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "lambda_role" {
    name = "LambdaRole"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
            "Service": "lambda.amazonaws.com"
        }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_role_logs_policy" {
    name = "LambdaRolePolicy"
    role = aws_iam_role.lambda_role.id
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_role_sqs_policy" {
    name = "AllowSQSPermissions"
    role = aws_iam_role.lambda_role.id
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA FUNCTION
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lambda_function" "symphony_updates_lambda" {
    filename         = "${path.module}/lambda/example.zip"
    function_name    = "symphony_example"
    role             = aws_iam_role.lambda_role.arn
    handler          = "example.handler"
    source_code_hash = data.archive_file.lambda_zip.output_base64sha256
    runtime          = "nodejs12.x"

    environment {
        variables = {
            environment = "development"
        }
    }
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA EVENT SOURCE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lambda_event_source_mapping" "symphony_updates_lambda_event_source" {
    event_source_arn = aws_sqs_queue.symphony_updates_queue.arn
    enabled          = true
    function_name    = aws_lambda_function.symphony_updates_lambda.arn
    batch_size       = 1
}