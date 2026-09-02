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
    """
    verify_identity — identity gate before any PHI is returned or any booking action.

    Two verification methods:
      - "dob"        : phone number + date of birth match (seeded patients).
      - "phone_only" : the record has no date of birth on file (patient was
                       registered through the IVR, name + phone only). The
                       caller's phone number is already proven by the carrier
                       (ANI), so a phone match — plus a last-name check when a
                       lastName is supplied — is sufficient.

    Input (API Gateway proxy — JSON body):
      phoneNumber  (required, E.164)
      dateOfBirth  (required only for records that have a DOB on file)
      lastName     (optional, used for the phone_only check)
    """
    try:
        body = json.loads(event.get('body') or '{}')
        phone_number = (body.get('phoneNumber') or '').strip()
        date_of_birth = (body.get('dateOfBirth') or '').strip()
        last_name = (body.get('lastName') or '').strip()

        if not phone_number:
            return _resp(400, {'verified': False, 'error': 'phoneNumber is required'})

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
        stored_dob = (patient.get('dateOfBirth') or '').strip()

        if stored_dob:
            # Standard check — phone + DOB.
            if not date_of_birth:
                return _resp(200, {'verified': False, 'reason': 'dob_required'})
            if stored_dob != date_of_birth:
                print(f'verify_identity: DOB mismatch for patient {patient["patientId"]}')
                return _resp(200, {'verified': False, 'reason': 'dob_mismatch'})
            method = 'dob'
        else:
            # No DOB on file (IVR-registered) — phone match is the proof.
            # If a last name was supplied, it must match.
            if last_name and last_name.lower() != (patient.get('lastName') or '').strip().lower():
                print(f'verify_identity: last-name mismatch for patient {patient["patientId"]}')
                return _resp(200, {'verified': False, 'reason': 'name_mismatch'})
            method = 'phone_only'

        print(f'verify_identity: verified patient {patient["patientId"]} via {method}')
        return _resp(200, {
            'verified': True,
            'verificationMethod': method,
            'patientId': patient['patientId'],
            'firstName': patient.get('firstName', ''),
            'lastName': patient.get('lastName', ''),
        })

    except Exception as e:
        print(f'verify_identity error: {e}')
        return _resp(500, {'verified': False, 'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
