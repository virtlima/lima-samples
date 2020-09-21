import json
import logging
import threading
import boto3
import cfnresponse
def create_object(bucket, body, key):
    s3 = boto3.client('s3')
    s3.put_object(Body=body,Bucket=bucket, Key=key)
def delete_objects(bucket, key):
    s3 = boto3.resource('s3')
    bucket = s3.Bucket('bucket')
    bucket.objects.filter(Prefix="logs/").delete()
    bucket.delete_objects(Delete={'Objects':[{'Key':key}]})
def timeout(event, context):
    logging.error('Execution is about to time out, sending failure response to CloudFormation')
    cfnresponse.send(event, context, cfnresponse.FAILED, {}, None)
def handler(event, context):
    # make sure we send a failure to CloudFormation if the function is going to timeout
    timer = threading.Timer((context.get_remaining_time_in_millis() / 1000.00) - 0.5, timeout, args=[event, context])
    timer.start()
    print('Received event: %s' % json.dumps(event))
    status = cfnresponse.SUCCESS
    try:
        bucket = event['ResourceProperties']['Bucket']
        body = event['ResourceProperties']['Body']
        key = event['ResourceProperties']['Key']
        if event['RequestType'] == 'Delete':
            delete_objects(bucket)
        else:
            create_object(bucket, body, key)
    except Exception as e:
        logging.error('Exception: %s' % e, exc_info=True)
        status = cfnresponse.FAILED
    finally:
        timer.cancel()
        cfnresponse.send(event, context, status, {}, None)