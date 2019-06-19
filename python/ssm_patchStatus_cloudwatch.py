def lambda_handler(event, context):
    import boto3
    import datetime
    
    # Set Services Client Connections
    ssmcl = boto3.client('ssm')
    cloudwatchcl = boto3.client('cloudwatch')
    
    # Set Services Client Connections
    ssmcl = boto3.client('ssm')
    cloudwatchcl = boto3.client('cloudwatch')
    
    # Grab Instances Associated with SSM
    
    associated_instances = ssmcl.describe_instance_information()['InstanceInformationList']
    
    ssm_instances = []
    
    for inst in associated_instances:
        ssm_instances.append(inst['InstanceId'])
        
    # Determine Patch Status of SSM instances
    
    patched_instances = []
    
    missing_patches = []
    
    failed_patches = []
    
    for instance in ssm_instances:
        patch = ssmcl.describe_instance_patch_states(
            InstanceIds = [
                instance,
            ]
        )['InstancePatchStates'][0]
        
        if patch['MissingCount'] == 0:
            patched_instances.append(patch['InstanceId'])
        
        elif patch['MissingCount'] != 0:
            missing_patches.append(patch['InstanceId'])
            cloudwatchcl.put_metric_data(
                Namespace = 'Ops/Patches',
                MetricData = [
                    {
                        'MetricName': 'Instances Missing Patches',
                        'Dimensions':[
                            {
                                'Name':'InstanceId',
                                'Value':patch['InstanceId']
                            },
                        ],
                        'Timestamp': datetime.datetime.utcnow(),
                        'Value' : 1.0,
                        'Unit': 'Count'
                        
                    },
                ]
            )
        
        elif patch['FailedCount'] != 0:
            failed_patches.append(patch['InstanceId'])
            cloudwatchcl.put_metric_data(
                Namespace = 'Ops/Patches',
                MetricData = [
                    {
                        'MetricName': 'Instances Failed Patches',
                        'Dimensions':[
                            {
                                'Name':'InstanceId',
                                'Value':patch['InstanceId']
                            },
                        ],
                        'Timestamp': datetime.datetime.utcnow(),
                        'Value' : 1.0,
                        'Unit': 'Count'
                    },
                ]
            )
            
            print 'Patched Instances:{}'.format(len(patched_instances))
            print 'Missing Patches:{}'.format(len(missing_patches))
            print 'Failed Patches:{}'.format(len(failed_patches))
            
            #Publish Result to Cloudwatch
            cloudwatchcl.put_metric_data(
                Namespace = 'Ops/Patches',
                MetricData = [
                    {
                        'MetricName': '# of Patched Instances',
                        'Timestamp': datetime.datetime.utcnow(),
                        'Value' : len(patched_instances),
                        'Unit': 'Count'
                    },
                ]
            )
            
            cloudwatchcl.put_metric_data(
                Namespace = 'Ops/Patches',
                MetricData = [
                    {
                        'MetricName': '# of Instances Missing Patches',
                        'Timestamp': datetime.datetime.utcnow(),
                        'Value' : len(missing_patches),
                        'Unit': 'Count'
                    },
                ]
            )
            
            cloudwatchcl.put_metric_data(
                Namespace = 'Ops/Patches',
                MetricData = [
                    {
                        'MetricName': '# of Instances Failed Patches',
                        'Timestamp': datetime.datetime.utcnow(),
                        'Value' : len(failed_patches),
                        'Unit': 'Count'
                    },
                ]
)
