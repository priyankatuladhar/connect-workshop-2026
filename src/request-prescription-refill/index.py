import json
import os
import uuid
from datetime import datetime, timezone
import boto3

dynamodb = boto3.resource('dynamodb')

PRESCRIPTION_REQUESTS_TABLE = os.environ['PRESCRIPTION_REQUESTS_TABLE_NAME']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        patient_id = body.get('patientId', '').strip()
        medication_name = body.get('medicationName', '').strip()
        prescription_id = body.get('prescriptionId', '').strip()
        dosage = body.get('dosage', '').strip()
        quantity = body.get('quantity', '').strip()

        if not patient_id or not medication_name:
            return _resp(400, {'success': False, 'error': 'patientId and medicationName are required'})

        now = datetime.now(timezone.utc)
        request_id = f'RX-{now.strftime("%Y%m%d")}-{patient_id}-{uuid.uuid4().hex[:6].upper()}'

        item = {
            'requestId': request_id,
            'patientId': patient_id,
            'medicationName': medication_name,
            'status': 'pending_review',
            'createdAt': now.isoformat(),
        }
        if prescription_id:
            item['prescriptionId'] = prescription_id
        if dosage:
            item['dosage'] = dosage
        if quantity:
            item['quantity'] = quantity

        dynamodb.Table(PRESCRIPTION_REQUESTS_TABLE).put_item(Item=item)
        print(f'request_prescription_refill: created {request_id} for patient {patient_id}')

        return _resp(200, {
            'success': True,
            'requestId': request_id,
            'medicationName': medication_name,
            'status': 'pending_review',
            'message': (
                'Your prescription refill request has been submitted and is pending '
                'pharmacist review. You will be contacted when it is ready.'
            ),
        })

    except Exception as e:
        print(f'request_prescription_refill error: {e}')
        return _resp(500, {'success': False, 'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
