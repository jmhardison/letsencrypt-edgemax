#!/bin/bash

set -e

working_dir="/config/letsencrypt"

# Make sure we're root
if [ $EUID -ne 0 ]; then
    echo This script must be run as root!
    exit 1
fi

mkdir -p "$working_dir"

echo Downloading files to $working_dir...

pushd "$working_dir" > /dev/null

curl "https://raw.githubusercontent.com/mgbowen/letsencrypt-edgemax/master/renew.sh" > renew.sh
curl "https://raw.githubusercontent.com/mgbowen/letsencrypt-edgemax/master/lighttpd.conf.patch" > lighttpd.conf.patch
curl "https://raw.githubusercontent.com/mgbowen/letsencrypt-edgemax/master/ubnt-gen-lighty-conf.sh.patch" > ubnt-gen-lighty-conf.sh.patch

chmod +x renew.sh
./renew.sh "$@"

popd > /dev/null
