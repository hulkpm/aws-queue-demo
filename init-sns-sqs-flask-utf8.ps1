#临时执行 Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 设置项目路径
$projectPath = "sns-sqs-flask-demo"
$terraformPath = "$projectPath\terraform"
$scriptsPath = "$projectPath\scripts"
$flaskAppPath = "$projectPath\flask-app"
$templatesPath = "$flaskAppPath\templates"

# 创建目录
New-Item -Path $projectPath -ItemType Directory -Force | Out-Null
New-Item -Path $terraformPath -ItemType Directory -Force | Out-Null
New-Item -Path $scriptsPath -ItemType Directory -Force | Out-Null
New-Item -Path $flaskAppPath -ItemType Directory -Force | Out-Null
New-Item -Path $templatesPath -ItemType Directory -Force | Out-Null

# === 第一步：Terraform 配置（只创建 SNS 和 SQS）

$mainTfStep1 = @"
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

output "sns_topic_arn" {
  value = aws_sns_topic.demo_topic.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.demo_queue.url
}
"@

Set-Content -Path "$terraformPath\main.tf" -Value $mainTfStep1 -Encoding utf8

# variables.tf (空)
$variablesTf = "# Add your variables here"
Set-Content -Path "$terraformPath\variables.tf" -Value $variablesTf -Encoding utf8

# outputs.tf (留空先)
Set-Content -Path "$terraformPath\outputs.tf" -Value "" -Encoding utf8

# 清理之前的 user-data 脚本，留空先（后续注入）
Set-Content -Path "$scriptsPath\ec2-userdata.sh" -Value "" -Encoding utf8

# 创建 flask-app 模板文件（无依赖可先创建）
$snsgenHtml = @"
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
"@
Set-Content -Path "$templatesPath\snsgen.html" -Value $snsgenHtml -Encoding utf8

$consumeHtml = @"
<!DOCTYPE html>
<html>
<head><title>Consume Message</title></head>
<body>
    <h1>Message Consumed!</h1>
    <a href="/">Go back</a>
</body>
</html>
"@
Set-Content -Path "$templatesPath\consume.html" -Value $consumeHtml -Encoding utf8

$requirementsTxt = @"
Flask
boto3
"@
Set-Content -Path "$flaskAppPath\requirements.txt" -Value $requirementsTxt -Encoding utf8

Write-Host "第一步完成：SNS 和 SQS Terraform 配置已生成。"
Write-Host "请执行以下命令部署 SNS 和 SQS："
Write-Host "cd $terraformPath"
Write-Host "terraform init"
Write-Host "terraform apply -auto-approve"

Write-Host "`n部署完成后，运行以下命令来获取 SNS 和 SQS 输出："
Write-Host "terraform output -json | Out-File ..\sns-sqs-output.json"

Write-Host "`n然后运行此脚本的第二步：更新 Terraform 配置并部署 EC2。"

# -----------------------------------------------
# === 第二步：函数：更新 main.tf，注入用户数据并创建 EC2
function DeployEC2WithUserData {
    param(
        [string]$snsArn,
        [string]$sqsUrl
    )

    # 生成 EC2 User Data 脚本
    $userData = @"
#!/bin/bash
yum update -y
yum install -y python3 shadow-utils
pip3 install flask boto3

# 设置 ec2-user 密码为 wozaila
echo 'ec2-user:wozaila' | chpasswd

# 修改 sshd_config 允许密码登录
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

mkdir -p /home/ec2-user/flask-app
cd /home/ec2-user/flask-app

cat > app.py << EOF
from flask import Flask, render_template, request
import boto3

app = Flask(__name__)
sqs = boto3.client('sqs', region_name='us-east-1')
sns = boto3.client('sns', region_name='us-east-1')
queue_url = "$sqsUrl"

@app.route('/')
def index():
    messages = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=20)
    return render_template('snsgen.html', messages=messages.get('Messages', []))

@app.route('/send', methods=['POST'])
def send_message():
    msg = request.form['message']
    sns.publish(
        TopicArn='$snsArn',
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
"@

    Set-Content -Path "$scriptsPath\ec2-userdata.sh" -Value $userData -Encoding utf8

    # 生成完整的 main.tf（包含 EC2 实例）
    $mainTfStep2 = @"
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
            "Resource": "\${aws_sqs_queue.demo_queue.arn}",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "\${aws_sns_topic.demo_topic.arn}"
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
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  key_name      = "your-key-name" # 请替换为你的密钥对名称
  security_groups = [aws_security_group.ec2_sg.name]
  user_data = file("\${path.module}/../scripts/ec2-userdata.sh")

  tags = {
    Name = "FlaskDemoEC2"
  }
}

output "ec2_public_ip" {
  value = aws_instance.flask_ec2.public_ip
}
"@

    Set-Content -Path "$terraformPath\main.tf" -Value $mainTfStep2 -Encoding utf8

    Write-Host "第二步 Terraform 配置已生成，包含 EC2 实例。"
    Write-Host "请执行以下命令部署 EC2 实例："
    Write-Host "cd $terraformPath"
    Write-Host "terraform init"
    Write-Host "terraform apply -auto-approve"
}

# 供用户调用示例（部署第二步）：
# DeployEC2WithUserData -snsArn "arn:aws:sns:..." -sqsUrl "https://sqs.us-east-1.amazonaws.com/xxxx/queue.fifo"
