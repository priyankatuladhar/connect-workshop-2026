import os
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

PATIENTS_TABLE = os.environ['PATIENTS_TABLE_NAME']


def handler(event, context):
    """
    Invoked DIRECTLY by the Contact Flow — NOT via API Gateway.

    Amazon Connect passes the caller phone number in:
      event['Details']['ContactData']['CustomerEndpoint']['Address']

    Return value must be a flat dict of string key→string value.
    Connect merges these as contact attributes for use in the flow and
    later by UpdateQSessionFunction.
    """
    try:
        contact_data = event.get('Details', {}).get('ContactData', {})
        phone_number = contact_data.get('CustomerEndpoint', {}).get('Address', '').strip()

        if not phone_number:
            print('customer_lookup: no phone number in event')
            return _not_found()

        table = dynamodb.Table(PATIENTS_TABLE)
        result = table.query(
            IndexName='phone-index',
            KeyConditionExpression=Key('phoneNumber').eq(phone_number),
            Limit=1,
        )
        items = result.get('Items', [])
        if not items:
            print(f'customer_lookup: no patient for phone ending {phone_number[-4:]}')
            return _not_found()

        patient = items[0]
        print(f'customer_lookup: found patient {patient["patientId"]}')

        # All values must be strings for Connect contact attributes
        return {
            'patientFound': 'true',
            'patientId': str(patient.get('patientId', '')),
            'firstName': str(patient.get('firstName', '')),
            'lastName': str(patient.get('lastName', '')),
            'phoneNumber': str(patient.get('phoneNumber', '')),
            'email': str(patient.get('email', '')),
        }

    except Exception as e:
        print(f'customer_lookup error: {e}')
        return _not_found()


def _not_found():
    return {
        'patientFound': 'false',
        'patientId': '',
        'firstName': '',
        'lastName': '',
        'phoneNumber': '',
        'email': '',
    }
