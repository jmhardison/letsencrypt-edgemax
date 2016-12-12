#!/bin/bash

# Script to undo EdgeOS modifications from
# the letsencrypt-edgemax script
# by Steve Jenkins (https://www.stevejenkins.com/)

# Make sure we're root
if [ $EUID -ne 0 ]; then
    echo This script must be run as root!
    exit 1
fi

# Bring in our configuration and utilities
script_dir=`dirname $0`
source $script_dir/config.sh
source $script_dir/util.sh

# Undo file patches
mv /etc/lighttpd/lighttpd.conf.orig /etc/lighttpd/lighttpd.conf

mv /usr/sbin/ubnt-gen-lighty-conf.sh.orig /usr/sbin/ubnt-gen-lighty-conf.sh

# Remove directories created by script
rm -rf "$install_dir"

rm -rf "$cert_root_dir"

rm -rf "$challenge_dir"

# Enter a Vyatta configure session for regenerating config files
source /opt/vyatta/etc/functions/script-template

configure

function atexit() {
    configure_exit
}

trap atexit EXIT

# Regenerate the lighttpd configuration and restart it to reflect our uninstall
echo Regenerating configuration files...

$(/usr/sbin/ubnt-gen-lighty-conf.sh)

# Change the router configuration to point to the default certificate
echo Updating router configuration...

delete service gui cert-file
delete service gui ca-file

commit
save

echo Restarting Web GUI...
restart_web_gui
