#!/usr/bin/env python3
#
# Lambda 302
#
# Python code to be used in AWS Lambda, called by AWS API Gateway Lambda proxy,
# to handle redirects based on subdomains. The first subdomain of the called
# url is redirected to a file of the same name within the specified S3 bucket.
#
# Author(s): Cody Buell
#
# Requisite:
#
# Resources:
#
# Usage:


import json


def lambda_handler(event, context):
    # define our target S3 bucket
    bucket = "my-bucket-name"

    # get the first subdomain from the url used to call this script
    resource = event['headers']['Host'].split('.')[0]

    # craft our 302 response to redirect to the specified S3 bucket
    response = {
        "statusCode": 302,
        "headers": {
            'Location': 'https://' + bucket + '.s3.amazonaws.com/' + resource
        }
    }

    # define any json body we want to also pass back and append it to response
    data = {}
    response["body"] = json.dumps(data)

    return response
