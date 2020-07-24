terraform {
  backend "s3" {
    bucket = "mackah666-s3-bucket"
    key    = "path/to/my/sqs_bucket_key"
    region = "eu-west-1"
  } 
}