import json
import os
from datetime import datetime, timezone
import boto3
from boto3.dynamodb.conditions import Attr

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
        new_slot_id = body.get('newSlotId', '').strip()

        if not appointment_id or not new_slot_id:
            return _resp(400, {'success': False, 'error': 'appointmentId and newSlotId are required'})

        appts_table = dynamodb.Table(APPOINTMENTS_TABLE)
        slots_table = dynamodb.Table(SLOTS_TABLE)

        # Fetch existing appointment
        existing = appts_table.get_item(Key={'appointmentId': appointment_id}).get('Item')
        if not existing:
            return _resp(404, {'success': False, 'error': 'Appointment not found'})
        if existing.get('status') != 'confirmed':
            return _resp(409, {'success': False, 'error': f"Cannot reschedule — appointment status is '{existing['status']}'"})

        old_slot_id = existing['slotId']

        # Book new slot atomically — reject if not available
        try:
            slots_table.update_item(
                Key={'slotId': new_slot_id},
                UpdateExpression='SET #s = :booked',
                ConditionExpression=Attr('status').eq('available'),
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={':booked': 'booked'},
            )
        except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
            return _resp(409, {'success': False, 'error': 'The new slot is no longer available. Please choose another.'})

        # Fetch new slot details
        new_slot = slots_table.get_item(Key={'slotId': new_slot_id}).get('Item', {})

        # Update appointment record
        appts_table.update_item(
            Key={'appointmentId': appointment_id},
            UpdateExpression=(
                'SET slotId = :ns, appointmentDate = :nd, startTime = :nt, '
                'endTime = :ne, updatedAt = :ua'
            ),
            ExpressionAttributeValues={
                ':ns': new_slot_id,
                ':nd': new_slot.get('appointmentDate', existing['appointmentDate']),
                ':nt': new_slot.get('startTime', existing['startTime']),
                ':ne': new_slot.get('endTime', ''),
                ':ua': datetime.now(timezone.utc).isoformat(),
            },
        )

        # Free old slot
        try:
            slots_table.update_item(
                Key={'slotId': old_slot_id},
                UpdateExpression='SET #s = :available',
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={':available': 'available'},
            )
        except Exception as free_err:
            print(f'reschedule_appointment: failed to free old slot {old_slot_id} (non-fatal): {free_err}')

        print(f'reschedule_appointment: rescheduled {appointment_id} to slot {new_slot_id}')
        return _resp(200, {
            'success': True,
            'appointmentId': appointment_id,
            'newAppointmentDate': new_slot.get('appointmentDate', ''),
            'newStartTime': new_slot.get('startTime', ''),
            'status': 'confirmed',
        })

    except Exception as e:
        print(f'reschedule_appointment error: {e}')
        return _resp(500, {'success': False, 'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
