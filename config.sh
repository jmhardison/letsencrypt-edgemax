#!/bin/bash

cert_root_dir=/config/auth/letsencrypt
install_dir="/config/letsencrypt"
challenge_dir=/var/www/htdocs/.well-known/acme-challenge

le_account_key="$cert_root_dir/letsencrypt_account.key"
domain_key="$cert_root_dir/domain.key"
domain_csr="$cert_root_dir/domain.csr"
signed_cert="$cert_root_dir/signed_cert.crt"
ssl_cert="$cert_root_dir/ssl_cert.pem"
le_intermediate_ca="$cert_root_dir/le_intermediate_ca.pem"

acme_tiny_url="https://raw.githubusercontent.com/diafygi/acme-tiny/fcb7cd6f66e951eeae76ff2f48d8ad3e40da37ef/acme_tiny.py"
