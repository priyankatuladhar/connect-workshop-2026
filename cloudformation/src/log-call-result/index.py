import json
import os
import uuid
from datetime import datetime, timezone
import boto3

dynamodb = boto3.resource('dynamodb')

CALL_LOGS_TABLE = os.environ['CALL_LOGS_TABLE_NAME']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        patient_id = body.get('patientId', 'UNKNOWN').strip()
        contact_id = body.get('contactId', '').strip()
        outcome = body.get('outcome', 'unknown').strip()
        summary = body.get('summary', '').strip()

        now = datetime.now(timezone.utc)
        call_id = f'CALL-{now.strftime("%Y%m%d%H%M%S")}-{patient_id[:10]}-{uuid.uuid4().hex[:6].upper()}'

        item = {
            'callId': call_id,
            'patientId': patient_id,
            'outcome': outcome,
            'createdAt': now.isoformat(),
        }
        if contact_id:
            item['contactId'] = contact_id
        if summary:
            item['summary'] = summary
        if body.get('startTime'):
            item['startTime'] = body['startTime']
        if body.get('endTime'):
            item['endTime'] = body['endTime']
        if body.get('durationSeconds') is not None:
            item['durationSeconds'] = int(body['durationSeconds'])

        dynamodb.Table(CALL_LOGS_TABLE).put_item(Item=item)
        print(f'log_call_result: logged {call_id} outcome={outcome} patient={patient_id}')

        return _resp(200, {'success': True, 'callId': call_id})

    except Exception as e:
        print(f'log_call_result error: {e}')
        return _resp(500, {'success': False, 'error': 'Internal error'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
