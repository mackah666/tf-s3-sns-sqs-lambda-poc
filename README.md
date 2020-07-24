# Terraform S3 to SNS to SQS to Lambda

The following is an AWS infrastructure as code tutorial using Terraform.

The original post can be found [here](https://christiangiacomi.com/posts/terraform-sns-sqs-lambda)

## Architecture

S3 --> SNS --> SQS --> LAMBDA


## Description

The code creates four main resources:

1) An S3 bucket that notifies the SNS topic
2) An SNS topic
3) An SQS queue which subscribes to the SNS topic
4) A Lambda function which subscribes to the SQS queue


Please note that the code is NOT production ready and is only meant as an example.
