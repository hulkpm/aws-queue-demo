provider "aws" {
  region = "us-east-1"
}

resource "aws_sns_topic" "demo_topic" {
  name = "demo-topic.fifo"
  fifo_topic = true
  content_based_deduplication = true
}


resource "aws_sqs_queue" "demo_queue" {
  name = "demo-queue.fifo"
  fifo_queue = true
  content_based_deduplication = true
}

resource "aws_sqs_queue_policy" "demo_queue_policy" {
  queue_url = aws_sqs_queue.demo_queue.url
  policy    = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "sns.amazonaws.com"
            },
            "Action": "SQS:SendMessage",
            "Resource": "",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": ""
                }
            }
        }
    ]
}
POLICY
}

resource "aws_sns_topic_subscription" "demo_topic_subscription" {
  topic_arn = aws_sns_topic.demo_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.demo_queue.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.demo_topic.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.demo_queue.url
}
