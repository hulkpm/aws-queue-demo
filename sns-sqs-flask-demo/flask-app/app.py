from flask import Flask, render_template, request, redirect, url_for
import boto3
import hashlib
import time

app = Flask(__name__)

# Replace with your own
topic_arn = 'arn:aws:sns:us-east-1:598330827496:demo-topic.fifo'
queue_url = 'https://sqs.us-east-1.amazonaws.com/598330827496/do-queue.fifo'

sns = boto3.client('sns', region_name='us-east-1')
sqs = boto3.client('sqs', region_name='us-east-1')

# Format timestamp for HTML
@app.template_filter('datetimeformat')
def datetimeformat(value):
    return time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(value))

@app.route('/')
def index():
    try:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=1,
            AttributeNames=['All']
        )
        messages = response.get('Messages', [])
    except Exception as e:
        messages = []
        error = f"Error receiving messages: {str(e)}"
        return render_template('index.html', messages=messages, error=error)

    return render_template('index.html', messages=messages)

@app.route('/send', methods=['POST'])
def send():
    msg = request.form['message']
    dedup_id = hashlib.sha256(msg.encode()).hexdigest()
    try:
        sns.publish(
            TopicArn=topic_arn,
            Message=msg,
            MessageGroupId="default",
            MessageDeduplicationId=dedup_id
        )
    except Exception as e:
        return f"Error sending message: {str(e)}", 500

    return redirect(url_for('index'))

@app.route('/consume')
def consume():
    try:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=1,
            AttributeNames=['All']
        )
        messages = response.get('Messages', [])
    except Exception as e:
        messages = []
        error = f"Queue error: {str(e)}"
        return render_template('consume.html', messages=messages, error=error)

    return render_template('consume.html', messages=messages)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
