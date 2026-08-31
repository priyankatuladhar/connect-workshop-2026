import json
import os
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

PATIENTS_TABLE = os.environ['PATIENTS_TABLE_NAME']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        phone_number = body.get('phoneNumber', '').strip()
        date_of_birth = body.get('dateOfBirth', '').strip()

        if not phone_number or not date_of_birth:
            return _resp(400, {'verified': False, 'error': 'phoneNumber and dateOfBirth are required'})

        table = dynamodb.Table(PATIENTS_TABLE)
        result = table.query(
            IndexName='phone-index',
            KeyConditionExpression=Key('phoneNumber').eq(phone_number),
            Limit=1,
        )

        items = result.get('Items', [])
        if not items:
            print(f'verify_identity: no patient found for phone {phone_number[-4:]}')
            return _resp(200, {'verified': False, 'reason': 'patient_not_found'})

        patient = items[0]
        if patient.get('dateOfBirth') != date_of_birth:
            print(f'verify_identity: DOB mismatch for patient {patient["patientId"]}')
            return _resp(200, {'verified': False, 'reason': 'dob_mismatch'})

        print(f'verify_identity: verified patient {patient["patientId"]}')
        return _resp(200, {
            'verified': True,
            'patientId': patient['patientId'],
            'firstName': patient.get('firstName', ''),
            'lastName': patient.get('lastName', ''),
        })

    except Exception as e:
        print(f'verify_identity error: {e}')
        return _resp(500, {'verified': False, 'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
