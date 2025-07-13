import boto3
from botocore.exceptions import ClientError
from flask import Flask, render_template, request, redirect, url_for
import hashlib
import time
from datetime import datetime

app = Flask(__name__)

sqs = boto3.client('sqs', region_name='us-east-1')
sns = boto3.client('sns', region_name='us-east-1')

topic_arn = 'arn:aws:sns:us-east-1:598330827496:demo-topic.fifo'
queue_url = 'https://sqs.us-east-1.amazonaws.com/598330827496/do-queue.fifo'

# 日期格式化 filter
@app.template_filter('datetimeformat')
def datetimeformat(value):
    return datetime.fromtimestamp(value).strftime('%Y-%m-%d %H:%M:%S')

def check_resources():
    try:
        # 试着获取队列属性，如果不存在会抛异常
        sqs.get_queue_attributes(QueueUrl=queue_url, AttributeNames=['All'])
        return True
    except ClientError as e:
        print(f"[ERROR] check_resources: {e}")
        return False

@app.route('/')
def index():
    error = None
    messages = []

    if not check_resources():
        error = "队列不存在或名称错误"
    else:
        try:
            response = sqs.receive_message(
                QueueUrl=queue_url,
                AttributeNames=['All'],
                MaxNumberOfMessages=10,
                WaitTimeSeconds=1
            )
            messages = response.get('Messages', [])
        except ClientError as e:
            error = f"SQS 错误: {str(e)}"

    return render_template('index.html', messages=messages, error=error)

@app.route('/send', methods=['POST'])
def send():
    msg = request.form['message']
    print(f"Sending message: {msg}")
    dedup_id = hashlib.sha256(msg.encode()).hexdigest()
    response = sns.publish(
        TopicArn=topic_arn,
        Message=msg,
        MessageGroupId="default",
        MessageDeduplicationId=dedup_id
    )
    print(response)
    return redirect(url_for('index'))

@app.route('/consume')
def consume():
    error = None
    messages = []

    if not check_resources():
        error = "队列不存在或名称错误"
    else:
        try:
            response = sqs.receive_message(
                QueueUrl=queue_url,
                AttributeNames=['All'],
                MaxNumberOfMessages=10,
                WaitTimeSeconds=1
            )
            messages = response.get('Messages', [])
        except ClientError as e:
            error = f"SQS 错误: {str(e)}"

    return render_template('consume.html', messages=messages, error=error)
