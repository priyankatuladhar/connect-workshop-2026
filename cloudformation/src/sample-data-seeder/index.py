import json
import boto3
import cfnresponse

def handler(event, context):
    try:
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return

        table_name = event['ResourceProperties']['TableName']
        raw = event['ResourceProperties'].get('SampleData', '[]')
        sample_data = json.loads(raw)

        dynamodb = boto3.resource('dynamodb')
        ddb_client = boto3.client('dynamodb')
        table = dynamodb.Table(table_name)

        # Discover all key attributes (table PK/SK + every GSI PK/SK).
        # DynamoDB rejects PutItem if any key attribute is absent or null.
        key_attrs = set()
        try:
            desc = ddb_client.describe_table(TableName=table_name)['Table']
            for k in desc.get('KeySchema', []):
                key_attrs.add(k['AttributeName'])
            for gsi in desc.get('GlobalSecondaryIndexes', []) or []:
                for k in gsi.get('KeySchema', []):
                    key_attrs.add(k['AttributeName'])
        except Exception as e:
            print(f'describe_table error (continuing): {e}')

        seeded, skipped = 0, 0
        for item in sample_data:
            # Strip null / empty-string values — DynamoDB rejects them.
            item = {k: v for k, v in item.items() if v is not None and v != ''}
            missing = [k for k in key_attrs if k not in item]
            if missing:
                print(f'Skipping record missing key attr(s) {missing}: {item}')
                skipped += 1
                continue
            table.put_item(Item=item)
            seeded += 1

        print(f'Seeded {seeded}, skipped {skipped} records in {table_name}')
        cfnresponse.send(event, context, cfnresponse.SUCCESS,
                         {'ItemsSeeded': seeded, 'ItemsSkipped': skipped})

    except Exception as e:
        print(f'Seeder error: {e}')
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': str(e)})
