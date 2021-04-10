#!/usr/bin/env python3
#
# Slack Notification
#
# Send a slack message to specified channel. Works with libraries available in
# AWS Lambda.
#
# Author(s): Cody Buell
#
# Requisite: python3
#            SLACK_WEBHOOK env var
#
# Resources: https://urllib3.readthedocs.io/en/latest/user-guide.html
#            https://api.slack.com/messaging/webhooks
#
# Usage: ./slack_notifications.py

import os
import json
import urllib3

SLACK_WEBHOOK  = os.getenv('SLACK_WEBHOOK')

slack_payload = json.dumps({
    'channel': '#test',
    'username': 'devops',
    'icon_emoji': ':hubot:',
    'text': 'Hello Slack!',
})


def lambda_handler(event: dict, context: dict) -> dict:
    http = urllib3.PoolManager()
    resp = http.request('POST', SLACK_WEBHOOK, headers={'Content-Type': 'application/json'}, body=slack_payload)
    return {
        'statusCode': resp.status,
        'body': json.dumps(slack_payload)
    }


if __name__ == "__main__":
    lambda_handler({}, {})
