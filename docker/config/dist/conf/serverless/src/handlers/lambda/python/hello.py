import json
import sys
import os

def handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f"Hello from Lambda/Python running offline!, Running on Python version: {sys.version} {os.getcwd()}",
            'input': event,
            'context': str(context)
        }, separators=(',', ':'))
    }