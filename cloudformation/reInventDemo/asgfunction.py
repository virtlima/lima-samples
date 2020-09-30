import json
import logging
import boto3

def start_ssmautomation(event, docname):
    ssm_cl = boto3.client('ssm')
    asg_name = event['detail']['AutoScalingGroupName']
    instance_id = event['detail']['EC2InstanceId']
    lch_name = event['detail']['LifecycleHookName']
    start_automation = ssm_cl.start_automation_execution(
        DocumentName= docname,
        Parameters={
            'ASGName': [
                asg_name
            ],
            'ConfigBucket': [
                config_bucket
            ],
            'InstanceId': [
                instance_id
            ],
            'LCHName': [
                lch_name
            ]
        },
    )

def handler(event, context):
    ssm_cl = boto3.client('ssm')
    autoscale_cl = boto3.client('autoscaling')
    try:
        if event['detail']['LifecycleTransition'] =='autoscaling:EC2_INSTANCE_LAUNCHING':
            start_ssmautomation(event, docname)
        elif event['detail']['LifecycleTransition'] == 'autoscaling:EC2_INSTANCE_TERMINATING':
            start_ssmautomation(event, docname)
    except Exception as e:
        logging.error('Exception: %s' % e, exc_info=True)
        autoscale_cl.complete_lifecycle_action(
            LifecycleHookName= event['detail']['LifecycleHookName'],
            AutoScalingGroupName= event['detail']['AutoScalingGroupName'],
            LifecycleActionResult='ABANDON',
            InstanceId= event['detail']['EC2InstanceId']
        )

