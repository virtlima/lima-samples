import boto3

s3_bucket = 'aarolima-bucket'
compliance_status = 'NON_COMPLIANT'

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

bucket_tagging = s3_client.get_bucket_tagging(Bucket=s3_bucket)
public_bucket = bucket_tagging['TagSet'][3]['Value']

if compliance_status == 'NON_COMPLIANT' and public_bucket != 'yes':
    s3_client.put_public_access_block(
        Bucket = s3_bucket,
        PublicAccessBlockConfiguration = {
            'BlockPublicAcls': True,
            'IgnorePublicAcls': True,
            'BlockPublicPolicy': True,
            'RestrictPublicBuckets': True
        }
    )
    sns_client.publish(
      TopicArn='arn:aws:sns:us-east-1:024357338510:ConfigRuleNotify',
      Message='''S3 Bucket named {} was made public and is used for a non Public App.\n 
      Public Access has been blocked on the bucket'''.format(s3_bucket),
      Subject='S3 Bucket Made Public'
    )
elif compliance_status == 'NON_COMPLIANT' and public_bucket == 'yes':
    print('This bucket should be public')
    sns_client.publish(
      TopicArn='arn:aws:sns:us-east-1:024357338510:ConfigRuleNotify',
      Message='''S3 Bucket named {} is used for a Public App.\n 
      No Action will be taken, check compliance rule'''.format(s3_bucket),
      Subject='S3 Bucket Made Public'
    )
else:
    print('Bucket is compliant')
    sns_client.publish(
      TopicArn='arn:aws:sns:us-east-1:024357338510:ConfigRuleNotify',
      Message='S3 Bucket named {} is compliant.\n'.format(s3_bucket),
      Subject='S3 Bucket Changed State to compliant'
    )