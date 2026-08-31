import json
import os
import uuid
from datetime import datetime, timezone
import boto3
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

APPOINTMENTS_TABLE = os.environ['APPOINTMENTS_TABLE_NAME']
SLOTS_TABLE = os.environ['AVAILABLE_SLOTS_TABLE_NAME']
PATIENTS_TABLE = os.environ['PATIENTS_TABLE_NAME']
NOTIFICATION_TOPIC_ARN = os.environ['NOTIFICATION_TOPIC_ARN']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        patient_id = body.get('patientId', '').strip()
        slot_id = body.get('slotId', '').strip()

        if not patient_id or not slot_id:
            return _resp(400, {'success': False, 'error': 'patientId and slotId are required'})

        slots_table = dynamodb.Table(SLOTS_TABLE)

        # Atomic conditional update — prevents double-booking
        try:
            slots_table.update_item(
                Key={'slotId': slot_id},
                UpdateExpression='SET #s = :booked',
                ConditionExpression=Attr('status').eq('available'),
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={':booked': 'booked'},
            )
        except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
            return _resp(409, {'success': False, 'error': 'This slot is no longer available. Please choose another.'})

        # Fetch slot details to populate the appointment record
        slot = slots_table.get_item(Key={'slotId': slot_id}).get('Item', {})

        appointment_id = f'APT-{datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")}-{patient_id}-{uuid.uuid4().hex[:6].upper()}'
        appointment = {
            'appointmentId': appointment_id,
            'patientId': patient_id,
            'providerId': slot.get('providerId', body.get('providerId', '')),
            'slotId': slot_id,
            'appointmentDate': slot.get('appointmentDate', body.get('appointmentDate', '')),
            'startTime': slot.get('startTime', body.get('startTime', '')),
            'endTime': slot.get('endTime', ''),
            'specialty': slot.get('specialty', body.get('specialty', '')),
            'status': 'confirmed',
            'createdAt': datetime.now(timezone.utc).isoformat(),
        }

        dynamodb.Table(APPOINTMENTS_TABLE).put_item(Item=appointment)
        print(f'book_appointment: created {appointment_id} for patient {patient_id}')

        # SNS notification — non-blocking (failure does NOT reverse booking)
        try:
            patient = dynamodb.Table(PATIENTS_TABLE).get_item(Key={'patientId': patient_id}).get('Item', {})
            email = patient.get('email', '')
            if email:
                sns.publish(
                    TopicArn=NOTIFICATION_TOPIC_ARN,
                    Subject='Nepal Medical Care — Appointment Confirmed',
                    Message=(
                        f"Dear {patient.get('firstName', 'Patient')},\n\n"
                        f"Your appointment has been confirmed.\n\n"
                        f"Date: {appointment['appointmentDate']}\n"
                        f"Time: {appointment['startTime']}\n"
                        f"Specialty: {appointment['specialty']}\n"
                        f"Appointment ID: {appointment_id}\n\n"
                        f"Nepal Medical Care"
                    ),
                )
        except Exception as sns_err:
            print(f'book_appointment: SNS notification failed (non-fatal): {sns_err}')

        return _resp(200, {
            'success': True,
            'appointmentId': appointment_id,
            'appointmentDate': appointment['appointmentDate'],
            'startTime': appointment['startTime'],
            'specialty': appointment['specialty'],
            'status': 'confirmed',
        })

    except Exception as e:
        print(f'book_appointment error: {e}')
        return _resp(500, {'success': False, 'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
