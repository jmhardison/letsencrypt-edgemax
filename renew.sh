#!/bin/bash

# Make sure we're root
if [ $EUID -ne 0 ]; then
    echo This script must be run as root!
    exit 1
fi

# http://stackoverflow.com/a/21128172
implicit_yes=''
ignore_version_err=''
test=''
no_gui_restart=''

while getopts ':yitn' flag; do
    case "${flag}" in
        y) implicit_yes='true' ;;
        i) ignore_version_err='true' ;;
        t) test='true' ;;
        n) no_gui_restart='true' ;;
        *) echo "Unexpected option -$OPTARG" && exit 1 ;;
    esac
done

# Bring in our configuration and utilities
script_dir=`dirname $0`
source $script_dir/config.sh
source $script_dir/util.sh

ensure_version

# Move to the directory containing this script
working_dir="`dirname $0`"
pushd "$working_dir" > /dev/null || echo_and_exit "Working directory $working_dir does not exist!"

# Make sure we have a place to store keys, etc.
mkdir -p "$cert_root_dir" || echo_and_exit "Could not create the Let's Encrypt directory!"

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
function generate_csr() {
    if [ "$implicit_yes" == "true" ]; then
        echo_and_exit "Domain CSR is not valid, run this without the -y flag!";
    fi
    
    read -p "Enter the FQDN for your router: " fqdn
    openssl req -new -sha256 -key "$domain_key" -subj "/CN=$fqdn" > "$domain_csr"
}

if [ ! -e "$domain_csr" ]; then
    generate_csr
else
    fqdn=`openssl req -noout -in "$domain_csr" -subject | sed -n '/^subject/s/^.*CN=//p'`

    if [ "$fqdn" == "" ]; then
        generate_csr
    else
        echo Using the CSR at $domain_csr for domain $fqdn
    fi
fi

# Create a directory for the challenge files
mkdir -p "$challenge_dir" \
    || echo_and_exit "Error: could not create challenge directory $challenge_dir!"

#
# Open the firewall to port 80
#

# Create a unique identifier for the rule so we don't inadvertently delete
# a rule that we actually want to keep
iptable_rule_uuid=`cat /proc/sys/kernel/random/uuid`
iptable_rule_args="-p tcp --dport 80 -j ACCEPT -m comment --comment \'$iptable_rule_uuid\'"

echo ===============================================================================
echo "                                !!! WARNING !!!"
echo
echo " Your EdgeMAX's firewall will be opened for a short time to allow the Let's"
echo " Encrypt servers to validate that you own your domain. Specifically, this"
echo " script will open port 80 for the duration of the validation."
echo
echo " The following iptables rule will be added to your firewall:"
echo
printf "     iptables -I INPUT 1 $iptable_rule_args\n"
echo
echo " This rule will be removed once the validation completes, or if the script"
echo " exits at any point. This port will also be opened temporarily every time"
echo " the certificate is renewed."
echo ===============================================================================
echo

prompt_for_yes_or_exit "Are you sure you want to do this?" $implicit_yes

# Make sure the iptables rule is always removed when the
# script exits, even if an error occurs
function iptables_delete_rule() {
    iptables -D INPUT $iptable_rule_args
    return $?
}

function iptables_atexit() {
    iptables_delete_rule
}

trap iptables_atexit EXIT

# Actually open the firewall
iptables -I INPUT 1 $iptable_rule_args

echo Firewall rule that opens port 80 has been added.

#
# Everything's all set up, let's issue the certificate
#
acme_tiny_ca=''
if [ "$test" == "true" ]; then
    acme_tiny_ca="--ca https://acme-staging.api.letsencrypt.org"
    
    echo Using staging ACME server!
fi

python acme_tiny.py --account-key "$le_account_key" --csr "$domain_csr" \
    --acme-dir "$challenge_dir" $acme_tiny_ca > "$signed_cert" \
        || echo_and_exit "Error: could not issue certificate!"

#
# Close the firewall
#
iptables_delete_rule \
    || echo_and_exit "Error: The previously added iptables rule could not be deleted!"

# Remove the trap
trap - EXIT

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

if [ "$no_gui_restart" != "true" ]; then
    # Finally, reload the Web GUI
    echo Restarting Web GUI...
    restart_web_gui
fi

echo Done!
