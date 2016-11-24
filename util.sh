#!/bin/bash

function ensure_version() {
    # Make sure we're on a version higher than 1.8.5 (Build 4884695)
    if [ "$ignore_version_err" != "true" ]; then
        build_id=`vbash -ic "show version" | grep "Build ID:" | awk -F' ' '{print $3}'`
        
        if [ "$build_id" > 4884694 ]; then
            echo ERROR: This script is designed to use with EdgeOS firmware v1.8.5 (Build 4884695)
            echo or higher. It will not function properly with firmware older than this, but it may
            echo function with firmware newer than this. In either case, this script may not work on
            echo your system.
            echo
            echo To eliminate this error, pass the \"-i\" flag to this script.
            
            exit 1
        fi
    fi
}

function ensure_patch() {
    # Ensure we have patch
    which patch > /dev/null || echo_and_exit "Error: patch not found! Install it from apt-get and try again."
}

function restart_web_gui() {
    # https://community.ubnt.com/t5/EdgeMAX/GUI-restart-via-ssh/m-p/898366#M34391
    pid=`ps -e | grep lighttpd | awk '{print $1;}'`
    if [ "$pid" != "" ]; then kill $pid; fi
    /usr/sbin/lighttpd -f /etc/lighttpd/lighttpd.conf
}

function patch_if_necessary() {
    if [ ! -e "$2" ]; then
        echo Error: patch file $2 not found!
        exit 1
    fi
    
    if [ -e "$1.orig" ]; then
        # Make sure we can do a reverse patch to ensure our
        # patch was actually applied
        patch -p0 -N -R --dry-run --silent "$1" < "$2" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo File $1 is already patched, skipping...
            return 0
        else
            echo WARNING: File $1 was not patched successfully, or changes have \
                     been made to the patched areas!
            return 0
        fi
    fi
    
    patch -p0 -N --backup --suffix=.orig "$1" < "$2"
    return $?
}

# Arguments:
#     $1: Prompt to display to the user.
#     $2: true if the prompt should be accepted automatically, anything else otherwise.
function prompt_for_yes_or_exit() {
    if [ "$2" == "true" ]; then echo "$1 (y/n) y"; return 0; fi
    
    # http://stackoverflow.com/a/226724
    while true; do
        read -p "$1 (y/n) " result
        case $result in
            [Yy]* ) break;;
            [Nn]* ) exit 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

function echo_and_exit() {
    printf "$1\n"
    exit 1
}
