import json
import os
from datetime import date
import boto3
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource('dynamodb')

APPOINTMENTS_TABLE = os.environ['APPOINTMENTS_TABLE_NAME']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        patient_id = body.get('patientId', '').strip()
        include_past = body.get('includePast', False)

        if not patient_id:
            return _resp(400, {'error': 'patientId is required'})

        table = dynamodb.Table(APPOINTMENTS_TABLE)
        result = table.query(
            IndexName='patientId-index',
            KeyConditionExpression=Key('patientId').eq(patient_id),
            FilterExpression=Attr('status').ne('cancelled'),
        )
        appointments = result.get('Items', [])

        today = date.today().isoformat()
        if not include_past:
            appointments = [a for a in appointments if a.get('appointmentDate', '') >= today]

        appointments.sort(key=lambda a: (a.get('appointmentDate', ''), a.get('startTime', '')))

        print(f'lookup_appointment: {len(appointments)} appointments for patient {patient_id}')
        return _resp(200, {
            'appointments': appointments,
            'totalCount': len(appointments),
        })

    except Exception as e:
        print(f'lookup_appointment error: {e}')
        return _resp(500, {'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
