import json
import os
from datetime import date, timedelta
import boto3
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource('dynamodb')

SLOTS_TABLE = os.environ['AVAILABLE_SLOTS_TABLE_NAME']
PROVIDERS_TABLE = os.environ['PROVIDERS_TABLE_NAME']

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
}


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        specialty = body.get('specialty', '').strip()
        preferred_date = body.get('preferredDate', '').strip()
        num_days = min(int(body.get('numberOfDays', 7)), 30)

        slots_table = dynamodb.Table(SLOTS_TABLE)

        if specialty:
            # Query by specialty-date GSI for efficiency
            start = preferred_date if preferred_date else date.today().isoformat()
            end = (date.fromisoformat(start) + timedelta(days=num_days)).isoformat()
            result = slots_table.query(
                IndexName='specialty-date-index',
                KeyConditionExpression=(
                    Key('specialty').eq(specialty) &
                    Key('appointmentDate').between(start, end)
                ),
                FilterExpression=Attr('status').eq('available'),
            )
            slots = result.get('Items', [])
        else:
            # Scan with date filter — only used when no specialty given
            start = preferred_date if preferred_date else date.today().isoformat()
            end = (date.fromisoformat(start) + timedelta(days=num_days)).isoformat()
            result = slots_table.scan(
                FilterExpression=(
                    Attr('status').eq('available') &
                    Attr('appointmentDate').between(start, end)
                ),
            )
            slots = result.get('Items', [])

        # Enrich with provider name
        provider_cache = {}
        providers_table = dynamodb.Table(PROVIDERS_TABLE)
        enriched = []
        for slot in slots:
            pid = slot.get('providerId', '')
            if pid not in provider_cache:
                pr = providers_table.get_item(Key={'providerId': pid})
                provider_cache[pid] = pr.get('Item', {})
            provider = provider_cache[pid]
            enriched.append({
                'slotId': slot['slotId'],
                'providerId': pid,
                'providerName': provider.get('name', 'Unknown Provider'),
                'specialty': slot.get('specialty', specialty),
                'appointmentDate': slot['appointmentDate'],
                'startTime': slot['startTime'],
                'endTime': slot.get('endTime', ''),
            })

        enriched.sort(key=lambda s: (s['appointmentDate'], s['startTime']))
        print(f'check_available_slots: returning {len(enriched)} slots')
        return _resp(200, {'availableSlots': enriched, 'totalCount': len(enriched)})

    except Exception as e:
        print(f'check_available_slots error: {e}')
        return _resp(500, {'error': 'Internal error — please try again'})


def _resp(status, body):
    return {'statusCode': status, 'headers': HEADERS, 'body': json.dumps(body)}
