from flask import Flask, render_template, request, redirect, url_for
import boto3
import hashlib
from datetime import datetime

app = Flask(__name__)

# 配置你的 SNS 和 SQS
sns = boto3.client('sns', region_name='us-east-1')
sqs = boto3.client('sqs', region_name='us-east-1')

topic_arn = 'arn:aws:sns:us-east-1:598330827496:demo-topic.fifo'
queue_url = 'https://sqs.us-east-1.amazonaws.com/598330827496/do-queue.fifo'

@app.template_filter('datetimeformat')
def datetimeformat(value):
    return datetime.fromtimestamp(value).strftime('%Y-%m-%d %H:%M:%S')

@app.route('/')
def index():
    messages = []

    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=1,
        AttributeNames=['All']
    )

    if 'Messages' in response:
        messages = response['Messages']

    return render_template('index.html', messages=messages)

@app.route('/consume')
def consume():
    messages = []

    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=1,
        AttributeNames=['All']
    )

    if 'Messages' in response:
        messages = response['Messages']

    return render_template('consume.html', messages=messages)

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

@app.route('/delete', methods=['POST'])
def delete():
    receipt_handle = request.form.get('receipt_handle')
    if receipt_handle:
        sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
