from flask import Flask, render_template, request, redirect, url_for
import boto3
import hashlib
import time

app = Flask(__name__)

# Replace with your own
topic_arn = 'arn:aws:sns:us-east-1:598330827496:demo-topic.fifo'
queue_url = 'https://sqs.us-east-1.amazonaws.com/598330827496/demo-queue.fifo'

sns = boto3.client('sns', region_name='us-east-1')
sqs = boto3.client('sqs', region_name='us-east-1')

# Format timestamp for HTML
@app.template_filter('datetimeformat')
def datetimeformat(value):
    return time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(value))

@app.route('/')
def index():
    deleted = request.args.get('deleted')  # ← 添加这行
    try:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=1,
            AttributeNames=['All'],
            MessageAttributeNames=['All'] 
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
    group_id = request.form.get('group_id', 'default')  # 默认值 fallback
    try:
        sns.publish(
            TopicArn=topic_arn,
            Message=msg,
            MessageGroupId=group_id,
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
        return render_template('consume.html', messages=messages, 
                                               group_ids=group_ids,
                                               selected_group_id=selected_group_id,
                                               error=error)

    return render_template('consume.html', messages=messages)
@app.route('/delete', methods=['POST'])
def delete_message():
    receipt_handle = request.form.get('receipt_handle')
    if not receipt_handle:
        return "Missing receipt handle", 400

    try:
        sqs.delete_message(
            QueueUrl=queue_url,
            ReceiptHandle=receipt_handle
        )
    except Exception as e:
        return f"Error deleting message: {str(e)}", 500

    return redirect(url_for('index', deleted='1'))


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
