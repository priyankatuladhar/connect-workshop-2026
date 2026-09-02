import json
import os
import re
import random
import boto3
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource('dynamodb')

PATIENTS_TABLE = os.environ['PATIENTS_TABLE_NAME']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}

# E.164: leading + and 8-15 digits
PHONE_RE = re.compile(r'^\+[1-9]\d{7,14}$')


def handler(event, context):
    """
    register_new_patient — create a patient account.

    Only the caller's name and phone number are collected. No date of birth,
    address, or other sensitive detail is required — the row is keyed on a
    generated patientId and the phone number is the lookup key (phone-index).

    Input (API Gateway proxy — JSON body):
      firstName    (required)
      lastName     (required)
      phoneNumber  (required, E.164 — normally the caller's ANI)

    Output:
      success            (bool)
      patientId          (str)   e.g. "P-482917"
      firstName, lastName, phoneNumber
      createdAt          (ISO 8601)
      alreadyRegistered  (bool)  true when a record for this phone already existed
    """
    try:
        body = json.loads(event.get('body') or '{}')
        first_name = (body.get('firstName') or '').strip()
        last_name = (body.get('lastName') or '').strip()
        phone_number = (body.get('phoneNumber') or '').strip()

        if not first_name or not last_name or not phone_number:
            return _resp(400, {
                'success': False,
                'error': 'firstName, lastName and phoneNumber are required',
            })

        if not PHONE_RE.match(phone_number):
            return _resp(400, {
                'success': False,
                'error': 'phoneNumber must be E.164 format, e.g. +16505551234',
            })

        table = dynamodb.Table(PATIENTS_TABLE)

        # Idempotency: if this phone already has a record, return it unchanged.
        existing = table.query(
            IndexName='phone-index',
            KeyConditionExpression=Key('phoneNumber').eq(phone_number),
            Limit=1,
        ).get('Items', [])
        if existing:
            p = existing[0]
            print(f'register_new_patient: phone already registered as {p["patientId"]}')
            return _resp(200, {
                'success': True,
                'alreadyRegistered': True,
                'patientId': p['patientId'],
                'firstName': p.get('firstName', ''),
                'lastName': p.get('lastName', ''),
                'phoneNumber': p.get('phoneNumber', ''),
                'createdAt': p.get('createdAt', ''),
            })

        patient_id = _new_patient_id(table)
        now = datetime.now(timezone.utc).isoformat()

        item = {
            'patientId': patient_id,
            'firstName': first_name,
            'lastName': last_name,
            'phoneNumber': phone_number,
            'dateOfBirth': '',
            'email': '',
            'createdAt': now,
            'source': 'ivr-registration',
        }

        table.put_item(
            Item=item,
            ConditionExpression=Attr('patientId').not_exists(),
        )
        print(f'register_new_patient: created {patient_id} for phone ending {phone_number[-4:]}')

        return _resp(200, {
            'success': True,
            'alreadyRegistered': False,
            'patientId': patient_id,
            'firstName': first_name,
            'lastName': last_name,
            'phoneNumber': phone_number,
            'createdAt': now,
        })

    except Exception as e:
        print(f'register_new_patient error: {e}')
        return _resp(500, {'success': False, 'error': 'Internal error — please try again'})


def _new_patient_id(table):
    """P- + 6 random digits, checked for collision (up to 5 attempts)."""
    for _ in range(5):
        candidate = f'P-{random.randint(100000, 999999)}'
        hit = table.get_item(
            Key={'patientId': candidate},
            ProjectionExpression='patientId',
        ).get('Item')
        if not hit:
            return candidate
    raise RuntimeError('could not allocate a unique patientId')


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
