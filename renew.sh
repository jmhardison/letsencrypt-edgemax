#!/bin/bash

#
# BEGIN Configurable variables
#

cert_root_dir=/config/auth/letsencrypt
challenge_dir=/var/www/htdocs/.well-known/acme-challenge
working_dir=/config/letsencrypt

le_account_key="$cert_root_dir/letsencrypt_account.key"
domain_key="$cert_root_dir/domain.key"
domain_csr="$cert_root_dir/domain.csr"
signed_cert="$cert_root_dir/signed_cert.crt"
ssl_cert="$cert_root_dir/ssl_cert.pem"
le_intermediate_ca="$cert_root_dir/le_intermediate_ca.pem"

acme_tiny_url="https://raw.githubusercontent.com/diafygi/acme-tiny/fcb7cd6f66e951eeae76ff2f48d8ad3e40da37ef/acme_tiny.py"

#
# END Configurable variables
#

# http://stackoverflow.com/a/21128172
implicit_yes=''
ignore_version_err=''

while getopts ':yi' flag; do
    case "${flag}" in
        y) implicit_yes='true' ;;
        i) ignore_version_err='true' ;;
        *) echo "Unexpected option -$OPTARG" && exit 1 ;;
    esac
done

#
# BEGIN Utility functions
#

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

function prompt_for_yes_or_exit() {
    if [ $implicit_yes == "true" ]; then echo "$1 (y/n) y"; return 0; fi
    
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

#
# END Utility functions
#

# Set up a Vyatta configuration session
#
# http://vyos.net/wiki/Cli-shell-api
SET=${vyatta_sbindir}/my_set
DELETE=${vyatta_sbindir}/my_delete
COMMIT=${vyatta_sbindir}/my_commit
SAVE=${vyatta_sbindir}/vyatta-save-config.pl

# Obtain session environment
session_env=$(cli-shell-api getSessionEnv $PPID)

# Evaluate environment string
eval $session_env

# Setup and validate the session
cli-shell-api setupSession
cli-shell-api inSession || echo_and_exit "Something went wrong!"

should_popd=""

function atexit() {
    cli-shell-api teardownSession
    if [ "$should_popd" == "true" ]; then popd > /dev/null; fi
}

trap atexit EXIT

#
# Script start
#

# Ensure we have patch
if ! which patch > /dev/null; then
    echo "Error: patch not found! Install it from apt-get and try again."
    exit 1
fi

# Make sure we have a place to store things
mkdir -p "$working_dir" || echo_and_exit "Could not create the working directory!"
mkdir -p "$cert_root_dir" || echo_and_exit "Could not create the Let's Encrypt directory!"

pushd "$working_dir" > /dev/null
should_popd="true"

# Make sure we're on a good version
if [ "$ignore_version_err" != "true" ]; then
    version=`vbash -ic "show version" | grep Version: | awk -F' ' '{print $2}'`
    
    if [ "$version" != "v1.8.5" ]; then
        echo ERROR: This script is designed to use with EdgeMAX firmware v1.8.5. It will
        echo not function properly with firmware older than this, but it may function with
        echo firmware newer than this. In either case, this script may not work on your
        echo system.
        echo
        echo To eliminate this error, pass the \"-i\" flag to this script.
        
        exit 1
    fi
fi

if [ ! -e "acme_tiny.py" ]; then
    curl "$acme_tiny_url" > acme_tiny.py
fi

# Generate an account key, if needed
if [ ! -e "$le_account_key" ]; then
    echo Generating a Let\'s Encrypt account key. This may take a bit...
    openssl genrsa 4096 > "$le_account_key"
else
    echo Using the Let\'s Encrypt account key at $le_account_key
fi

# Generate a private key for the domain, if needed
if [ ! -e "$domain_key" ]; then
    echo Generating a domain private key. This may take a bit...
    openssl genrsa 4096 > "$domain_key"
else
    echo Using the domain key at $le_account_key
fi

# Generate a CSR for the domain, if needed
if [ ! -e "$domain_csr" ]; then
    read -p "Enter the FQDN for your router: " fqdn

    openssl req -new -sha256 -key "$domain_key" -subj "/CN=$fqdn" > "$domain_csr"
else
    fqdn=$(openssl req -noout -in "$domain_csr" -subject | sed -n '/^subject/s/^.*CN=//p')
    
    echo Using the CSR at $domain_csr for domain $fqdn
fi

# Create a directory for the challenge files
mkdir -p "$challenge_dir"

#
# Patch configuration files
#
echo Patching configuration files, if necessary...

# Make sure we can patch files
which patch > /dev/null || echo_and_exit "Error: patch is not installed!"

# Patch some lighttpd configuration files to allow the Let's Encrypt ACME
# server to read our challenge file. This is required because the EdgeMAX Web
# GUI redirects all URLs from HTTP to HTTPS, and Let's Encrypt requires HTTP
# access over port 80.
patch_if_necessary /usr/sbin/ubnt-gen-lighty-conf.sh ubnt-gen-lighty-conf.sh.patch \
    || echo_and_exit "Error: could not patch ubnt-gen-lighty-conf.sh!"

patch_if_necessary /etc/lighttpd/lighttpd.conf lighttpd.conf.patch \
    || echo_and_exit "Error: could not patch ubnt-gen-lighty-conf.sh!"

# Regenerate the lighttpd configuration and restart it to reflect our patches
#
# Delete any cert-file or ca-file settings if they're already set, to prevent
# errors during the generation script
echo Regenerating configuration files...

if cli-shell-api exists service gui cert-file; then
    $DELETE service gui cert-file
fi

if cli-shell-api exists service gui ca-file; then
    $DELETE service gui ca-file
fi

$(/usr/sbin/ubnt-gen-lighty-conf.sh)

echo Restarting Web GUI...
restart_web_gui

#
# Make sure we can access our challenges
#
echo Ensuring proper web server configuration...

challenge_url="http://$fqdn:80/.well-known/acme-challenge/test"
challenge_test_file="$challenge_dir/test"

echo HelloWorld > "$challenge_test_file"
challenge_resp=$(curl -sS $challenge_url)

# Clean up our test file
rm "$challenge_test_file"

# Make sure the web server is properly serving ACME challenges
if [ "$challenge_resp" != "HelloWorld" ]; then
    echo Warning: could not validate that the ACME challenge folder is accessible!
    echo
    echo Tried to access $challenge_url
    echo This was the response:
    echo
    printf "$challenge_resp\n"
    echo
    
    prompt_for_yes_or_exit "Do you want to continue anyways?"
fi

echo Validated!

# Create a unique identifier for the rule so we don't inadvertently delete
# a rule that we actually want to keep
iptable_rule_uuid=`cat /proc/sys/kernel/random/uuid`

iptable_rule_args="-p tcp --dport 80 -j ACCEPT -m comment --comment \'$iptable_rule_uuid\'"

#
# Open the firewall to port 80
#
echo ===============================================================================
echo "                                !!! WARNING !!!"
echo
echo " Your EdgeMAX's firewall will be opened for a short time to allow the Let's"
echo " Encrypt servers to validate that you own your domain. Specifically, this"
echo " script will open port 80 for the duration of the validation."
echo
echo " The following iptables rule will be added to your firewall:"
echo
echo "     iptables -I INPUT 1 $iptable_rule_args\n"
echo
echo " This rule will be removed once the validation completes, or if the script"
echo " exits at any point. This port will also be opened temporarily every time"
echo " the certificate is renewed."
echo ===============================================================================
echo

prompt_for_yes_or_exit "Are you sure you want to do this?"

# Make sure the iptables rule is always removed when the
# script exits, even if an error occurs
function iptables_delete_rule() {
    iptables -D INPUT $iptable_rule_args
    return $?
}

function iptables_atexit() {
    iptables_delete_rule
    atexit
}

trap iptables_atexit EXIT

# Actually open the firewall
iptables -I INPUT 1 $iptable_rule_args

echo Firewall rule that opens port 80 has been added.

#
# Everything's all set up, let's issue the certificate
#
python acme_tiny.py --account-key "$le_account_key" --csr "$domain_csr" \
    --acme-dir "$challenge_dir" > "$signed_cert" \
        || echo_and_exit "Error: could not issue certificate!"

#
# Close the firewall and restore our old exit trap
#
iptables_delete_rule \
    || echo_and_exit "Error: The previously added iptables rule could not be deleted!"

# Restore the old trap
trap atexit EXIT

echo The previously added firewall rule has been removed.

#
# Set up the Web GUI with the newly generated certificate
#

# Combine the signed certificate and the private key
cat "$signed_cert" "$domain_key" > "$ssl_cert"

# Get Let's Encrypt's intermediate CA certificate
echo Downloading Let\'s Encrypt\'s intermediate CA certificate...
curl -Ss https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem > "$le_intermediate_ca" \
    || echo_and_exit "\nCould not download Let's Encrypt's intermediate CA certificate!"

# Make sure permissions are all good
echo Ensuring permissions...
chown -R root:root "$cert_root_dir"
chmod -R 0400 "$cert_root_dir"

# Change the router configuration to point to both of these files
echo Updating router configuration...

cli-shell-api exists service gui cert-file && $DELETE service gui cert-file
cli-shell-api exists service gui ca-file && $DELETE service gui ca-file

$SET service gui cert-file "$ssl_cert"
$SET service gui ca-file "$le_intermediate_ca"

echo Committing and saving...
$COMMIT
$SAVE

# Finally, reload the Web GUI
echo Restarting Web GUI...
restart_web_gui

echo Done! Your router should now be equipped with a Let\'s Encrypt SSL certificate.
