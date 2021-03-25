#!/bin/bash
#!/bin/bash
#
# BashOpts
#
# Sample script for handling long and short options as well as some level of
# validation. Positional parameters are maintained and ordered sans flagged
# args. One downside is that shortopts can't be combined. -hv will not work,
# instead you must pass -h -v.
#
# Author(s): Cody Buell
#
# Requisite: 
#
# Resources: 
#
# Usage: ./bashopts -h

# set some reasonable defaults
NAME="World"
VERSION="0.0.0"
BOOL="false"

usage () {
  cat <<-ENDOFUSAGE
	usage: $(basename $0) [-hv] [-V|--version] [-n|--name your_name] [-b|--bool boolean]

	  OPTIONS:
	  -h  Print usage for $(basename $0)
    -v  Set verbose output for $(basename $0)
	  -V, --version
        Print out version of $(basename $0) and exit
	  -n <name>, --name <name>
	      Say hello <name>
	  -b <bool>, --bool <bool>
	      Print out <bool>, must be 'true' or 'false', case sensitive

	examples:

	  Print out this message.
	    $(basename $0) -h

	ENDOFUSAGE
  exit ${1}
}

read_opt_w_arg_str() {
  if [ -n "${2}" ] && [ ${2:0:1} != "-" ]; then
    eval $3=$2
  else
    echo "Error: Argument for $1 is missing" >&2
    exit 1
  fi
}

read_opt_w_arg_bool() {
  if [ -n "${2}" ] && [ ${2:0:1} != "-" ]; then
    if [[ "${2}" =~ (true|false) ]]; then
      eval ${3}=${2}
    else
      echo "Error: Argument for ${1} must be 'true' or 'false'" >&2
      exit 1
    fi
  else
    echo "Error: Argument for ${1} is missing" >&2
    exit 1
  fi
}

PARAMS=""
while (( "$#" )); do
  case "$1" in
    -h )
      usage 0
      ;;
    -v)
      set -x
      shift
      ;;
    -V|--version )
      read_opt_w_arg_str $1 $2 VERSION
      shift 2
      ;;
    -n|--name )
      read_opt_w_arg_str $1 $2 NAME
      shift 2
      ;;
    -b|--bool )
      read_opt_w_arg_bool  $1 $2 BOOL
      shift 2
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="${PARAMS} $1"
      shift
      ;;
  esac
done

# re-set positional arguments in their proper place
eval set -- "${PARAMS}"

echo "Hello ${NAME}!"
echo "bool: ${BOOL}"
echo "version: ${VERSION}"
echo "positional parameters: ${PARAMS}"
