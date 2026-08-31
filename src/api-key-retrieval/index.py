import json
import boto3
import cfnresponse

def handler(event, context):
    try:
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return
        api_key_id = event['ResourceProperties']['ApiKeyId']
        client = boto3.client('apigateway')
        response = client.get_api_key(apiKey=api_key_id, includeValue=True)
        cfnresponse.send(event, context, cfnresponse.SUCCESS,
                         {'ApiKeyValue': response['value']})
    except Exception as e:
        print(f'ApiKey retrieval error: {e}')
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': str(e)})
