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
echo "Setting up Flask App....."
yum update -y
yum install -y python3 git
pip3 install flask boto3

# 克隆你的 GitHub 项目
cd /home/ec2-user
git clone https://github.com/hulkpm/aws-queue-demo.git

#设置密码登录（慎用，仅限测试）
echo 'ec2-user:wozaila' | chpasswd
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
systemctl restart sshd

# 启动 Flask（注意权限和路径）
cd /home/ec2-user/aws-queue-demo/flask-app
nohup python3 app.py > /home/ec2-user/flask.log 2>&1 &
EOF


  tags = {
    Name = "FlaskAppEC2"
  }
}

output "ec2_public_ip" {
  value = aws_instance.flask_ec2.public_ip
}
# 👇 新增拼接输出：Flask App 访问地址
output "demo_url" {
  value = "http://${aws_instance.flask_ec2.public_ip}:5000"
}