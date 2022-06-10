import boto3
import json
import re

s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Copy ALPR .json file from prod
    SFTP bucket to dev SFTP bucket
    """
    key = event['Records'][0]['s3']['object']['key']
    src = event['Records'][0]['s3']['bucket']['name']

    if not key.endswith('.json'):
        return lambda_result('File not JSON!')

    dest = re.sub(r'-prod$', '-dev', src)
    if dest == src:
        return lambda_result('File exists!')

    copy = {'Bucket': src, 'Key': key}
    s3_client.copy_object(CopySource=copy,
                          Bucket=dest,
                          Key=key)
    return lambda_result('File copied.')


def lambda_result(body, status=200):
    return {
        'statusCode': status,
        'body': json.dumps(body),
    }
