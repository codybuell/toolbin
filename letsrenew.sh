#!/bin/bash
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
# Requisite: - jq
#            - aws-cli properly configured
#            - certbot
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
# Usage: ./letsrenew.sh
#        0 1 * * * /usr/local/bin/letsrenew.sh > /var/log/letsrenew.sh 2>&1

################################################################################
##                                                                            ##
##  Configuration                                                             ##
##                                                                            ##
################################################################################

DOMAIN='mydomain.tld'           # domain to renew
THRESHOLD=7                     # threshold in days for when to renew certificate

LOGLEVEL=0                      # log calls <= LOGLEVEL will print out to screen
USELOGFILE='true'               # log output to log files [true|false]
LOGFILE='/var/log/letsrenew'    # fully pathed out log file

# preparation before certificate renewal
pre_command() {
  echo "pre command"
}

# cleanup/configuration after certificate renewal
post_command() {
  echo "post command"
}

################################################################################
##                                                                            ##
##  Functions                                                                 ##
##                                                                            ##
################################################################################

## Log
 #
 # Helper function to output standardized and colorized log messages.
 # Example: log 1 info "Informational message"
 #
 # @param
 #  LOG_LEVEL (int): 0 1 or 2 to indicate when this log is printed
 #  LOG_TYPE (string): one of info|warn|error|fatal
 #  LOG_MSG (quoted string): freehand message
 #  LOG_MSG_RHS (quoted string): right-hand side log message (optional)
## @return VOID
log() {
  LOG_LEVEL=$1
  LOG_TYPE=$2
  LOG_MSG=$3
  LOG_MSG_RHS=$4
  PFRESET='\033[0m'
  TIMESTAMP=$(date +"%F_%T")
  PAD_C=$(printf '%0.1s' "."{1..80})
  PAD_L=60

  # set color codes
  case $LOG_TYPE in
    info )
      PFCOLOR='\033[0;32m'     # green
      ;;
    warn )
      PFCOLOR='\033[0;36m'     # teal
      ;;
    error )
      PFCOLOR='\033[0;33m'     # yellow
      ;;
    fatal )
      PFCOLOR='\033[0;31m'     # red
      ;;
    * )
      PFCOLOR='\033[0m'        # default
      ;;
  esac

  print_it_out() {
    # if right side is supplied then columnate
    if [ -n "$LOG_MSG_RHS" ]; then
      printf "%-29s%s %*.*s ${PFCOLOR}%s${PFRESET}\n" "${TIMESTAMP} (${LOG_TYPE})" "${LOG_MSG}" 0 $((PAD_L - ${#LOG_MSG} - ${#LOG_MSG_RHS} )) "$PAD_C" "$LOG_MSG_RHS"
    else
      printf "${PFCOLOR}%-29s%s${PFRESET}\n" "${TIMESTAMP} (${LOG_TYPE})" "${LOG_MSG}"
    fi
  }

  # $LOGLEVEL is the global setting, $LOG_LEVEL is the level of this particular message
  if [[ $LOGLEVEL -ge $LOG_LEVEL ]]; then
    # restore output handles
    set_redirects 2
    print_it_out $PFCOLOR $PFRESET
    # reset log level
    set_redirects $LOGLEVEL
  elif [[ "$USELOGFILE" == "true" ]]; then
    PFCOLOR=""
    PFRESET=""
    eval 'print_it_out >> $LOGFILE'
  fi
}

##
 # Set Redirects
 #
 # Configure output based on verbosity level. Create file descriptor 6 and 7 to
 # backup stdout and stderr, and perform appropriate file descriptor meddling /
 # juggling to get desired output. Avoid using fd5 as there are known issues
 # with subshells.
 #
 #  0 - no output except calls to log with a value of 0
 #  1 - not output except calls to log with a value of 0 or 1
 #  2 - verbose output, all command std out and std error
 #
 # @param 
 #   LEVEL (int): desired log level
## @return VOID
set_redirects() {
  case $1 in
    0|1 )
      if [[ "$USELOGFILE" == "true" ]]; then
        eval 'exec 6>&1 1>>$LOGFILE'
        eval 'exec 7>&2 2>>$LOGFILE'
      else
        exec 6>&1 1>/dev/null
        exec 7>&2 2>/dev/null
      fi
      ;;
    2 )
      # if fd6 is being used
      [[ "$(uname)" == "Darwin" ]] && FD6=$(ls -1 /dev/fd | grep -c '^6$') || FD6=$(ls -1 /proc/$$/fd | grep -c '^6$')
      if [[ $FD6 -eq 1 ]]; then
        # restore output handles and output per normal
        exec 1>&6
        # remove the file descriptor
        exec 6>&-
      fi
      # if fd7 is being used
      [[ "$(uname)" == "Darwin" ]] && FD7=$(ls -1 /dev/fd | grep -c '^7$') || FD7=$(ls -1 /proc/$$/fd | grep -c '^7$')
      if [[ $FD7 -eq 1 ]]; then
        # restore output handles and output per normal
        exec 2>&7
        # remove the file descriptor
        exec 7>&-
      fi
      ;;
  esac
}

################################################################################
##                                                                            ##
##  Initialization                                                            ##
##                                                                            ##
################################################################################

if [[ "$USELOGFILE" == "true" ]]; then
  rm $LOGFILE &> /dev/null
  # if uselogfile, create target file with tee and point stdout and stderr to it
  # >(...) creates a target file / pid? that our file descriptors can point to
  # tee then handles splitting output to the terminal and a file
  exec 1> >(tee -a $LOGFILE)
  exec 2> >(tee -a $LOGFILE)

  # go the extra mile and strip ansi colors from output going into logfile
  # TODO: correct order of output, log 0 messages in this case get appended to
  # the end of the logfile rather than appearing in order of execution
  # if [[ "$(uname)" == "Darwin" ]] && which gsed &> /dev/null; then
  #   exec 1> >(tee >(gsed 's/\x1B\[[0-9;]*m//g' >> $LOGFILE))
  #   exec 2> >(tee >(gsed 's/\x1B\[[0-9;]*m//g' >> $LOGFILE))
  # else
  #   exec 1> >(tee >(sed  's/\x1B\[[0-9;]*m//g' >> $LOGFILE))
  #   exec 2> >(tee >(sed  's/\x1B\[[0-9;]*m//g' >> $LOGFILE))
  # fi
fi

# this needs to be called first
set_redirects $LOGLEVEL

################################################################################
##                                                                            ##
##  Run                                                                       ##
##                                                                            ##
################################################################################

log 0 info "starting letsrenew"

# determine how many days we have left on our certificate
DAYSLEFT=`certbot certificates --cert-name $DOMAIN 2>&1 | grep -i days | sed 's/^.*VALID: \([0-9]*\) .*$/\1/'`
log 0 info "$DAYSLEFT days remaining for $DOMAIN"

# if we are under our threshold then proceed with renewal
if [[ $DAYSLEFT -lt $THRESHOLD ]]; then

  log 0 info "less than $THRESHOLD days remaning, starting renewal"

  # grab security group id attached to this host
  REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`
  SGID=`aws ec2 describe-security-groups --region $REGION --filters Name=group-name,Values=$(curl -s http://169.254.169.254/latest/meta-data/security-groups) --query 'SecurityGroups[*].GroupId' --output text`

  # open it up to the world, tag rule as temp-letsencrypt
  aws ec2 authorize-security-group-ingress \
      --region $REGION \
      --group-id $SGID \
      --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="temp-letsencrypt"}]'

  # prepare the host by running the pre-commands
  pre_command

  # renew the certificate
  certbot -d $DOMAIN --standalone certonly

  # revoke temp rule that opens to the world
  aws ec2 revoke-security-group-ingress \
      --region $REGION \
      --group-id $SGID \
      --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="temp-letsencrypt"}]'

  # reconfigure the host by running the post-commands
  post_command

else
  log 0 info "more than $THRESHOLD days remaining, not renewing"
fi

# kludgy workaround to clean out ansi color codes from log file
if [[ "$(uname)" == "Darwin" ]] && which gsed &> /dev/null; then
  gsed -i 's/\x1B\[[0-9;]*m//g' $LOGFILE
else
  sed -i 's/\x1B\[[0-9;]*m//g' $LOGFILE
fi
