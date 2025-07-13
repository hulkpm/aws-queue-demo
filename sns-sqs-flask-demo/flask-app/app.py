from flask import Flask, render_template, request, redirect, url_for
import boto3
import hashlib
from datetime import datetime

app = Flask(__name__)

sqs = boto3.client('sqs', region_name='us-east-1')
sns = boto3.client('sns', region_name='us-east-1')

queue_url = "https://sqs.us-east-1.amazonaws.com/598330827496/demo-queue.fifo"
topic_arn = "arn:aws:sns:us-east-1:598330827496:demo-topic.fifo"

# Jinja2过滤器，格式化时间戳
@app.template_filter('datetimeformat')
def datetimeformat(value):
    return datetime.fromtimestamp(value).strftime('%Y-%m-%d %H:%M:%S')

@app.route('/')
def index():
    # 接收SQS消息，带上时间戳等属性
    messages_response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        MessageAttributeNames=['All'],
        AttributeNames=['All']
    )
    messages = messages_response.get('Messages', [])
    return render_template('index.html', messages=messages)

@app.route('/send', methods=['POST'])
def send():
    msg = request.form['message']
    dedup_id = hashlib.sha256(msg.encode()).hexdigest()
    sns.publish(
        TopicArn=topic_arn,
        Message=msg,
        MessageGroupId="default",  # FIFO主题必需
        MessageDeduplicationId=dedup_id
    )
    return redirect(url_for('index'))

@app.route('/consume')
def consume():
    # 获取SQS消息列表，供页面显示
    messages_response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        MessageAttributeNames=['All'],
        AttributeNames=['All']
    )
    messages = messages_response.get('Messages', [])
    return render_template('consume.html', messages=messages)

@app.route('/consume/delete', methods=['POST'])
def delete_message():
    receipt_handle = request.form['receipt_handle']
    try:
        sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)
        msg = 'Message deleted successfully.'
    except Exception as e:
        msg = f'Error deleting message: {e}'
    # 删除完跳回consume页，带提示（这里简单用query参数）
    return redirect(url_for('consume'))

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000, debug=True)
