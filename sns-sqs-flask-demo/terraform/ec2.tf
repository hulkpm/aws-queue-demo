resource "aws_security_group" "ec2_sg" {
  name_prefix = "flask-sg"
  description = "Allow inbound HTTP & SSH"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "flask_ec2" {
  ami           = "ami-0c02fb55956c7d316" # Amazon Linux 2
  instance_type = "t2.micro"
  #key_name      = "your-key-name"         # 请替换成你自己的 EC2 key pair 名称
  security_groups = [aws_security_group.ec2_sg.name]

  user_data = <<EOF
#!/bin/bash
echo "Setting up Flask App..."
yum update -y
yum install -y python3 git
pip3 install flask boto3

设置密码登录（慎用，仅限测试）
echo 'ec2-user:wozaila' | chpasswd
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
systemctl restart sshd

# 创建 Flask App
mkdir /home/ec2-user/flask-app
cd /home/ec2-user/flask-app

cat > app.py <<PYEOF
from flask import Flask, render_template, request
import boto3

app = Flask(__name__)
sqs = boto3.client('sqs', region_name='us-east-1')
sns = boto3.client('sns', region_name='us-east-1')

queue_url = "${var.sqs_queue_url}"
topic_arn = "${var.sns_topic_arn}"

@app.route('/')
def index():
    messages = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)
    return render_template('snsgen.html', messages=messages.get('Messages', []))

@app.route('/send', methods=['POST'])
def send():
    msg = request.form['message']
    sns.publish(TopicArn=topic_arn, Message=msg)
    return 'Message sent'

@app.route('/consume', methods=['POST'])
def consume():
    receipt = request.form['receipt_handle']
    sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt)
    return 'Message deleted'

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
PYEOF

mkdir templates
cat > templates/snsgen.html <<HTEOF
<!DOCTYPE html>
<html>
<head><title>SNS Message Generator</title></head>
<body>
    <h1>Send Message</h1>
    <form method="POST" action="/send">
        <textarea name="message" rows="4" cols="50"></textarea><br>
        <button type="submit">Send</button>
    </form>

    <h2>Messages in SQS</h2>
    <ul>
    {% for msg in messages %}
        <li>{{ msg.Body }}
            <form action="/consume" method="POST">
                <input type="hidden" name="receipt_handle" value="{{ msg.ReceiptHandle }}">
                <button type="submit">Consume</button>
            </form>
        </li>
    {% endfor %}
    </ul>
</body>
</html>
HTEOF

python3 app.py &
EOF

  tags = {
    Name = "FlaskAppEC2"
  }
}

output "ec2_public_ip" {
  value = aws_instance.flask_ec2.public_ip
}
