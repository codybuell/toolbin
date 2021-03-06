#!/bin/bash
#
# Redirects
#
# An example of how to use fd redirects to control (script) output / logging.
# Supports OSX and Linux. If USELOGFILE is set to true, all output regardless
# of loglevel will be output to the LOGFILE. Any LOGLEVEL < 2 will only output
# calls to the log function with a level <= to its value. A LOGLEVEL of 2 will
# output all stdout and stderr to the terminal.
#
# Author(s): Cody Buell
#
# Requisite: gsed (optional: if on osx to remove color codes from log file)
#
# Resources: 
#
# Usage: ./redirects.sh

################################################################################
##                                                                            ##
##  Configuration                                                             ##
##                                                                            ##
################################################################################

LOGLEVEL=0                      # log calls <= LOGLEVEL will print out to screen
USELOGFILE='true'               # log output to log files [true|false]
LOGFILE='redirects.out'         # fully pathed out log file

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
log () {
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
set_redirects () {
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

# sample log messages
log 0 info "info log level 0"
log 0 warn "warn log level 0"
log 0 error "error log level 0"
log 0 fatal "fatal log level 0"
log 0 info "left hand side" "right hand side"
log 1 info "Log level 1"
log 2 info "Log level 2"

# a command with stderr output
curl https://google.crm

# general stdout output
echo "test echo output"
ls -l

# kludgy workaround to clean out ansi color codes from log file
if [[ "$(uname)" == "Darwin" ]] && which gsed &> /dev/null; then
  gsed -i 's/\x1B\[[0-9;]*m//g' $LOGFILE
else
  sed -i 's/\x1B\[[0-9;]*m//g' $LOGFILE
fi
