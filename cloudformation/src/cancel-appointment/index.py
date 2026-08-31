import json
import os
from datetime import datetime, timezone
import boto3

dynamodb = boto3.resource('dynamodb')

APPOINTMENTS_TABLE = os.environ['APPOINTMENTS_TABLE_NAME']
SLOTS_TABLE = os.environ['AVAILABLE_SLOTS_TABLE_NAME']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        appointment_id = body.get('appointmentId', '').strip()

        if not appointment_id:
            return _resp(400, {'success': False, 'error': 'appointmentId is required'})

        appts_table = dynamodb.Table(APPOINTMENTS_TABLE)

        existing = appts_table.get_item(Key={'appointmentId': appointment_id}).get('Item')
        if not existing:
            return _resp(404, {'success': False, 'error': 'Appointment not found'})
        if existing.get('status') == 'cancelled':
            return _resp(409, {'success': False, 'error': 'Appointment is already cancelled'})

        slot_id = existing.get('slotId', '')

        # Mark appointment cancelled
        appts_table.update_item(
            Key={'appointmentId': appointment_id},
            UpdateExpression='SET #s = :cancelled, updatedAt = :ua',
            ExpressionAttributeNames={'#s': 'status'},
            ExpressionAttributeValues={
                ':cancelled': 'cancelled',
                ':ua': datetime.now(timezone.utc).isoformat(),
            },
        )

        # Free the slot — non-fatal if it fails (slot may have been reassigned)
        if slot_id and slot_id != 'SL-COMPLETED':
            try:
                dynamodb.Table(SLOTS_TABLE).update_item(
                    Key={'slotId': slot_id},
                    UpdateExpression='SET #s = :available',
                    ExpressionAttributeNames={'#s': 'status'},
                    ExpressionAttributeValues={':available': 'available'},
                )
            except Exception as free_err:
                print(f'cancel_appointment: slot {slot_id} free failed (non-fatal): {free_err}')

        print(f'cancel_appointment: cancelled {appointment_id}')
        return _resp(200, {
            'success': True,
            'appointmentId': appointment_id,
            'status': 'cancelled',
            'message': 'Your appointment has been successfully cancelled.',
        })

    except Exception as e:
        print(f'cancel_appointment error: {e}')
        return _resp(500, {'success': False, 'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
