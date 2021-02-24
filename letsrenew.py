#!/usr/bin/env python3
#
# LetsRenew
#
# Wrapper to automate renewal of Let's Encrypt certificates on AWS EC2
# instances.  Letsrenew will temporarily open up the attached Security Group,
# perform the certificate renewal, restart services as needed, and revert the
# Security Group. Actions will only be taken if the certificate is due for
# renewal as defined in the configuration section.
#
# Author(s): Cody Buell
#
# Requisite: - python3
#            - pip3: requests boto3
#            - certbot|certbot-auto
#            - certificate already configured at least once
#            - managed policy attached to ec2 iam role
#              {
#                  "Version": "2012-10-17",
#                  "Statement": [
#                      {
#                          "Sid": "ManageInboundSecurityGroupRules",
#                          "Effect": "Allow",
#                          "Action": [
#                              "ec2:RevokeSecurityGroupIngress",
#                              "ec2:AuthorizeSecurityGroupIngress",
#                              "ec2:UpdateSecurityGroupRuleDescriptionsIngress"
#                          ],
#                          "Resource": "arn:aws:ec2:*:*:security-group/*"
#                      },
#                      {
#                          "Sid": "DescribeSecurityGroups",
#                          "Effect": "Allow",
#                          "Action": "ec2:DescribeSecurityGroups",
#                          "Resource": "*"
#                      }
#                  ]
#              }
#            - /etc/logrotate.d/letsrenew (optional)
#              /var/log/letsrenew.log {
#                rotate 2
#                missingok
#                notifempty
#                monthly
#              }
#            - set domain, pre_command, and post_command in config section
#
# Resources: 
#
# Usage: python3 letsrenew.py
#        0 1 * * * /usr/local/bin/letsrenew.py > /var/log/letsrenew 2>&1

import os
import ssl
import sys
import boto3
import socket
import requests
import logging as l
import datetime as dt

################################################################################
##                                                                            ##
##  Configuration                                                             ##
##                                                                            ##
################################################################################

# domain to renew
domain = 'mydomain.tld'

# threshold for when certificate should be renewed in seconds
threshold = 5 * 24 * 60 * 60

# pre command (services to stop, host prep work, etc)
pre_command = """
    echo "pre command"
  """

# post command (movement of certs, services to start, etc)
post_command = """
    echo "post command"
  """

# tempoary security group rule for domain ownership verification
temp_rule=[
        {
            'FromPort': 80,
            'ToPort': 80,
            'IpProtocol': 'tcp',
            'IpRanges': [
                {
                    'CidrIp': '0.0.0.0/0',
                    'Description': 'temp-letsrenew-rule',
                    },
                ]
            }
        ]

# configure logging level and format
l.basicConfig(
        level=l.INFO,
        format='%(asctime)s %(levelname)-8s %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        )

################################################################################
##                                                                            ##
##  Functions                                                                 ##
##                                                                            ##
################################################################################

def request(method_type: str, url: str, headers: dict, *args: dict) -> requests.Response:
    """Run a POST or GET request"""
    method_type = method_type.lower()
    try:
        if method_type == "post":
            l.debug('Running post request to {}'.format(url))
            return requests.post(url, headers=headers, data=args[0])
        if method_type == "get":
            l.debug('Running get request to {}'.format(url))
            return requests.get(url, headers=headers, data=args[0])
    except requests.RequestException as e:
        sys.exit(e)

def run_cmd(cmd: str) -> str:
    """Run command against the OS"""
    l.debug('Running command: {}'.format(cmd))
    out = (os.popen(cmd).read())
    return out.rstrip()

def ssl_expiration(hostname: str) -> (dt.datetime, dt.datetime, int):
    """Get the datetime of a certificates expiration."""
    # define the certificate date format
    ssl_date_fmt = r'%b %d %H:%M:%S %Y %Z'

    # configure our socket
    context = ssl.create_default_context()
    conn    = context.wrap_socket(
        socket.socket(socket.AF_INET),
        server_hostname=hostname,
    )
    conn.settimeout(3.0)

    # establish the socket and grab the certificate
    l.debug('Connect to {}'.format(hostname))
    try:
        conn.connect((hostname, 443))
    except Exception as e:
        print(e)
        sys.exit()
    ssl_info = conn.getpeercert()
    conn.close()

    # parse the expiration into some dates and measures
    expiration  = dt.datetime.strptime(ssl_info['notAfter'], ssl_date_fmt)
    remaining   = expiration - dt.datetime.utcnow()
    seconds_rem = int(remaining.total_seconds())

    return expiration, remaining, seconds_rem

def get_security_group_by_name(ec2: 'boto3 ec2 client', name: str) -> 'sg id':
    """Get the id of a SecurityGroup from the name."""
    ec2 = boto3.client('ec2')
    resp = ec2.describe_security_groups(
            Filters=[
                dict(Name='group-name', Values=[name])
                ]
            )
    
    return resp['SecurityGroups'][0]['GroupId']

def add_rule_to_security_group(ec2: 'boto3 ec2 client', security_group: str):
    """Add temp rule to the specified SecurityGroup."""
    sg  = ec2.SecurityGroup(security_group)
    sg.authorize_ingress(DryRun=False, IpPermissions=temp_rule)

def remove_rule_from_security_group(ec2: 'boto3 ec2 client', security_group: str):
    """Remove temp rule from the specified SecurityGroup."""
    sg  = ec2.SecurityGroup(security_group)
    sg.revoke_ingress(DryRun=False, IpPermissions=temp_rule)

################################################################################
##                                                                            ##
##  Run                                                                       ##
##                                                                            ##
################################################################################

if __name__ == "__main__":
    _, _, seconds_left = ssl_expiration(sys.argv[1])
    # if we are under our threshold for time remaining on cert run our renewal
    if seconds_left < threshold:
        # execute the pre-command
        print('Running pre-command')
        out = run_cmd(pre_command)
        print(out)

        # get the region of the ec2 instance we are running on
        resp = request('get', 'http://169.254.169.254/latest/dynamic/instance-identity/document', {}, {})
        region = resp.json()['region']

        # initialialize boto3
        ec2 = boto3.client('ec2')

        # get the security groups attached to this node
        resp = request('get', 'http://169.254.169.254/latest/meta-data/security-groups', {}, {})
        security_group = get_security_group_by_name(ec2, resp.text)

        # temporarily open up the security group port 80 to the world, tag rule to easily identify
        add_rule_to_security_group(ec2, security_group)

        # perform certificate renewal for the domain
        out = run_cmd(f"""
            certbot -d {domain} --standalone certonly
            #certbot-auto -d {domain} --standalone certonly
        """

        # delete out the temoprary security group rule using the tag to identify
        remove_rule_from_security_group(ec2, security_group)

        # TODO: parse renewal output for location of new certificates

        # execute the post command
        print('Running post-command')
        out = run_cmd(pre_command)
        print(out)
