#!/usr/bin/env python3
#
# Get Emoji
#
# Script to query the Slack api for a teams custom emoji. Creates a folder
# containing a json listing of the emoji and an images directory containing
# each image file.
#
# Author(s): Cody Buell
#
# Requisite:
#
# Resources:
#
# Usage: export SLACK_TOKEN=[yourslacktoken]; python3 get_emoji.py


import re
import os
import sys
import json
import shutil
import requests


def request(method_type: str, url: str, headers: dict, *args: dict) -> requests.Response:
    """ Requests makes a defined request and returns the response.

    Args:
      method_type (str): [post|get]
      url (str): end point for request
            headers (dict): request headers
            args (dict): data to be posted

    Returns:
            requests.Response
    """
    method_type = method_type.lower()
    try:
        if method_type == "post":
            return requests.post(url, headers=headers, data=args[0])
        if method_type == "get":
            return requests.get(url, headers=headers, data=args[0])
    except requests.RequestException as exception:
        sys.exit(exception)


# build our auth headers
headers = {
    "Authorization": "Bearer " + os.environ["SLACK_TOKEN"]
}

# query slack's api to get our emoji list and convert to dict and json out
resp   = request('get', 'https://slack.com/api/emoji.list', headers, {})
emojii = resp.json()['emoji']

# make slack_emoji/images dirs and store the emoji list
if not os.path.exists('slack_emoji'):
    os.makedirs('slack_emoji')
if not os.path.exists('slack_emoji/images'):
    os.makedirs('slack_emoji/images')
with open('slack_emoji/emoji_list.json', 'w') as f:
    f.write(json.dumps(emojii))

# download all the images, ignore aliases
p = re.compile(r'alias:.*')
for emoji, image in emojii.items():
    m = re.match(p, image)
    if m:
        continue
    e = image.split('.')[-1]
    r = requests.get(image, stream=True)
    if r.status_code == 200:
        r.raw.decode_content = True
        with open('slack_emoji/images/' + emoji + '.' + e, 'wb') as f:
            shutil.copyfileobj(r.raw, f)
        print('Image sucessfully Downloaded: ', emoji + '.' + e)
    else:
        print('Image Couldn\'t be retreived: ', emoji + '.' + e)
    r.close()
