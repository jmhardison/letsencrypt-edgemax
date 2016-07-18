#!/bin/vbash

# http://stackoverflow.com/a/21128172
ignore_version_err=''
test=''

while getopts ':it' flag; do
    case "${flag}" in
        i) ignore_version_err='true' ;;
        t) ;; # Will be passed through to renew.sh
        *) echo "Unexpected option -$OPTARG" && exit 1 ;;
    esac
done

# Make sure we're root
if [ $EUID -ne 0 ]; then
    echo This script must be run as root!
    exit 1
fi

# Bring in our configuration and utilities
script_dir=`dirname $0`
source $script_dir/config.sh
source $script_dir/util.sh

ensure_patch
ensure_version

# Create the install and certificate directory
mkdir -p "$install_dir"  || echo_and_exit "Could not create the installation directory!"
mkdir -p "$cert_root_dir" || echo_and_exit "Could not create the Let's Encrypt directory!"

# Copy needed files to the install directory
cp renew.sh $install_dir/renew.sh || echo_and_exit "Could not copy renew.sh to $install_dir!"
cp util.sh $install_dir/util.sh || echo_and_exit "Could not copy util.sh to $install_dir!"
cp config.sh $install_dir/config.sh || echo_and_exit "Could not copy config.sh to $install_dir!"

chmod +x $install_dir/renew.sh $install_dir/util.sh $install_dir/config.sh

# Download the ACME client script
echo Downloading acme_tiny.py...
curl "$acme_tiny_url" > $install_dir/acme_tiny.py

# Patch some lighttpd configuration files to allow the Let's Encrypt ACME
# server to read our challenge file. This is required because the EdgeMAX Web
# GUI redirects all URLs from HTTP to HTTPS, and Let's Encrypt requires HTTP
# access over port 80.
patch_if_necessary /usr/sbin/ubnt-gen-lighty-conf.sh ubnt-gen-lighty-conf.sh.patch \
    || echo_and_exit "Error: could not patch ubnt-gen-lighty-conf.sh!"

patch_if_necessary /etc/lighttpd/lighttpd.conf lighttpd.conf.patch \
    || echo_and_exit "Error: could not patch ubnt-gen-lighty-conf.sh!"

# Enter a Vyatta configure session for regenerating config files
source /opt/vyatta/etc/functions/script-template

configure

function atexit() {
    configure_exit
}

trap atexit EXIT

# Regenerate the lighttpd configuration and restart it to reflect our patches
echo Regenerating configuration files...

$(/usr/sbin/ubnt-gen-lighty-conf.sh)

echo Restarting Web GUI...
restart_web_gui

# Run the renewal script, which will generate the keys, etc. that we need
# -n flag is so the renew script doesn't restart the web GUI unnecesarially
chmod +x renew.sh
$install_dir/renew.sh "$@" -n

# Change the router configuration to point to the generated certificate files
echo Updating router configuration...

set service gui cert-file "$ssl_cert"
set service gui ca-file "$le_intermediate_ca"

commit
save

echo Restarting Web GUI...
restart_web_gui
