#!/bin/bash

# 创建项目目录结构
mkdir -p sns-sqs-flask-demo/terraform
mkdir -p sns-sqs-flask-demo/scripts
mkdir -p sns-sqs-flask-demo/flask-app/templates

# 创建 terraform/main.tf
cat <<EOF > sns-sqs-flask-demo/terraform/main.tf
provider "aws" {
  region = "us-east-1"
}

resource "aws_sns_topic" "demo_topic" {
  name = "demo-topic"
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
            "Resource": "${aws_sqs_queue.demo_queue.arn}",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "${aws_sns_topic.demo_topic.arn}"
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

resource "aws_security_group" "ec2_sg" {
  name_prefix = "flask-sg"
  description = "Allow inbound HTTP & SSH"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "flask_ec2" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI (us-east-1)
  instance_type = "t2.micro"
  key_name      = "your-key-name"  # 替换为你的 EC2 SSH 密钥对名称
  security_groups = [aws_security_group.ec2_sg.name]
  user_data = file("./scripts/ec2-userdata.sh")

  tags = {
    Name = "FlaskDemoEC2"
  }
}
EOF

# 创建 terraform/variables.tf
cat <<EOF > sns-sqs-flask-demo/terraform/variables.tf
# Add your variables here
EOF

# 创建 terraform/outputs.tf
cat <<EOF > sns-sqs-flask-demo/terraform/outputs.tf
output "ec2_public_ip" {
  value = aws_instance.flask_ec2.public_ip
}
EOF

# 创建 scripts/ec2-userdata.sh
cat <<EOF > sns-sqs-flask-demo/scripts/ec2-userdata.sh
#!/bin/bash
# 安装 Flask 和其他依赖
yum update -y
yum install -y python3
pip3 install flask boto3

# 启动 Flask 应用
mkdir /home/ec2-user/flask-app
cd /home/ec2-user/flask-app
cat << 'EOF' > app.py
from flask import Flask, render_template, request
import boto3

app = Flask(__name__)
sqs = boto3.client('sqs', region_name='us-east-1')
sns = boto3.client('sns', region_name='us-east-1')
queue_url = "https://sqs.us-east-1.amazonaws.com/598330827496/demo-queue.fifo"

@app.route('/')
def index():
    messages = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=20)
    return render_template('snsgen.html', messages=messages.get('Messages', []))

@app.route('/send', methods=['POST'])
def send_message():
    msg = request.form['message']
    sns.publish(
        TopicArn='arn:aws:sns:us-east-1:598330827496:demo-topic',
        Message=msg
    )
    return 'Message sent to SNS'

@app.route('/consume', methods=['POST'])
def consume_message():
    receipt_handle = request.form['receipt_handle']
    sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=receipt_handle
    )
    return 'Message deleted'

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
EOF

cat << 'EOF' > sns-sqs-flask-demo/flask-app/templates/snsgen.html
<!DOCTYPE html>
<html>
<head><title>SNS Message Generator</title></head>
<body>
    <h1>Send a message to SNS</h1>
    <form action="/send" method="POST">
        <textarea name="message" rows="4" cols="50"></textarea><br>
        <button type="submit">Send</button>
    </form>

    <h2>Messages in SQS</h2>
    <ul>
        {% for msg in messages %}
            <li>{{ msg.Body }} <form action="/consume" method="POST"><input type="hidden" name="receipt_handle" value="{{ msg.ReceiptHandle }}"><button type="submit">Consume</button></form></li>
        {% endfor %}
    </ul>
</body>
</html>
EOF

cat << 'EOF' > sns-sqs-flask-demo/flask-app/templates/consume.html
<!DOCTYPE html>
<html>
<head><title>Consume Message</title></head>
<body>
    <h1>Message Consumed!</h1>
    <a href="/">Go back</a>
</body>
</html>
EOF

# 创建 requirements.txt
cat <<EOF > sns-sqs-flask-demo/flask-app/requirements.txt
Flask
boto3
EOF

# 完成
echo "项目初始化完毕。现在，你可以进入 terraform 目录并运行 terraform 命令来创建 AWS 资源。"