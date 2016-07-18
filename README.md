# letsencrypt-edgemax
This project is intended to allow an administrator of an Ubiquiti router to obtain a Let's Encrypt SSL certificate for free and install it on their router, with minimal effort. If you're not sure what Let's Encrypt is, you can see information about [what it is](https://letsencrypt.org/) or [how it works](https://letsencrypt.org/how-it-works/).

The wonderful [`acme_tiny`](https://github.com/diafygi/acme-tiny) project is used for interacting with the Let's Encrypt ACME server and is downloaded during the installation process. As of this writing, `acme_tiny` is released under the MIT license.

## How It Works
The installer script does a few things to the router's filesystem and configuration. The most "dangerous" modification is patching two files related to the router's lighttpd server, which are needed to accomodate Let's Encrypt's requirement of a web server listening on port 80 and serving a challenge file from a specific URL. The two files are backed up in their directories and appended with a `.orig` suffix if the changes need to be reversed. The other modifications are strictly new files in the filesystem or configuration changes.

## Modifications
* `/etc/lighttpd/lighttpd.conf` is patched (and backed up) to prevent URL rewriting on the ACME challenge URL.
* `/usr/sbin/ubnt-gen-lighty-conf.sh` is patched (and backed up) to prevent HTTP-to-HTTPS redirection on the ACME challenge URL.
* A new directory, `/config/letsencrypt/`, is created to hold scripts needed for certificate issuance and renewal to function.
* A new directory, `/config/auth/letsencrypt/`, is created to hold a few private keys and certificate files.
* The configuration nodes `service gui cert-file` and `service gui ca-file` are modified to point to the issued SSL certificate and Let's Encrypt intermediate CA certificate, respectively.

## Requirements
* An Ubiquiti router running EdgeOS v1.8.5. Earlier versions will definitely not work, later versions might work.
* A fully qualified domain name (FQDN) with an A record pointing to your router.
* SSH access to your router.

## Installation
1. Open an SSH session into your router.
2. These scripts require that `patch` be installed, and unfortunately, it is not installed in the standard EdgeOS distribution. Fortunately, EdgeOS provides a way to install packages from Debian Wheezy's apt-get repositories. Run the following commands to enable apt-get access:

     ```
    configure
    set system package repository wheezy components 'main contrib non-free'
    set system package repository wheezy distribution wheezy 
    set system package repository wheezy url http://http.us.debian.org/debian
    set system package repository wheezy-security components main
    set system package repository wheezy-security distribution wheezy/updates
    set system package repository wheezy-security url http://security.debian.org
    commit
    save
    exit
    
    sudo apt-get update
    ```
    
    (Command listing from [Ubiquiti's knowledge base](https://help.ubnt.com/hc/en-us/articles/205202560-EdgeMAX-Add-other-Debian-packages-to-EdgeOS))
3. Install patch by running the following:

    ```
    sudo apt-get install patch
    ```
    
    Answer Yes to any prompts that come up.
4. Now you need to actually download the installation scripts. I'm going to show you how to do so using `git`, but if you want to use a different way, that's perfectly fine as well; the scripts themselves don't have a dependency on `git` being installed.

  Install `git` from `apt-get` by executing the following:

  ```
  sudo apt-get install git
  ```
  
  Then, clone the repository and move into its directory using the following:
  
  ```
  cd ~
  git clone https://github.com/mgbowen/letsencrypt-edgemax.git
  cd letsencrypt-edgemax
  ```
5. The only thing left to do should simply be to run `install.sh`:

  ```
  sudo ./install.sh
  ```
  
  You'll be prompted a few times for information. these prompts should be fairly self-explanatory. It will then perform all the necessary changes to your router and, after it's done executing, should leave you with a Web GUI that serves a valid Let's Encrypt SSL certificate!

## Usage
```
Usage: renew.sh [-yitn]

        -y: Implicitly answers "yes" to any prompts that appear. If a prompt
            that is not a yes/no question is invoked, the script exits with
            an error code (this occurs when generating a domain CSR and
            should not appear on domain renewals).
        -i: Ignores any firmware version incompatibility warnings.
        -t: Uses the staging ACME server instead of the production one.
            Certificates obtained with this flag are not trusted, but they
            come with a much higher rate limit, which is useful for testing.
        -n: Does not restart the HTTP server after the certificate is renewed.

Usage: install.sh [-it]

        See renew.sh for possible arguments. Note that only the -i and -t flags
        are valid with this script.
```

## TODO
For now, I've only documented on how to get the initial Let's Encrypt certificate. However, SSL certificates from Let's Encrypt are only valid for 90 days, and must be renewed frequently. The scripts are organized such that you should only need to call `renew.sh -y` to renew your certificate with no prompts, and you should be able to place this in a cron job on your router.
