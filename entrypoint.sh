#!/bin/bash

info() {
    echo "[+] $1"
}

info_dovecot() {
    sed "s/^\(.*\)/[DOVECOT] \1/g"
}

info_postfix() {
    sed "s/^\(.*\)/[POSTFIX] \1/g"
}

check_permissions() {
    # Check permissions for the mail directory.
    chown -R vvmail:vvmail /data/mail

    # Postfix loves its spool dir.
    chown root:root /conf/spool/postfix
    chown postfix:postfix /conf/spool/postfix/private

    # Make sure nobody can read the certificate key.
    chmod 700 /conf/certificates
}

check_dir() {
    if [[ ! -d "$1" ]]; then
        mkdir -p "$1"
    fi
}

check_dirs() {
    # Some shared directories.
    check_dir "/conf/certificates"
    check_dir "/conf/spool/postfix/private"

    # Dovecot config directories.
    check_dir "/conf/dovecot"

    # Postfix config directories.
    check_dir "/conf/postfix"

    # Data directories.
    check_dir "/data/logs"
    check_dir "/data/mail"

    info "Directory check finished."
}

install_dovecot() {
    if [[ -f /.dovecot-installed ]]; then
        return
    fi

    info "Installing Dovecot."

    # Link the config directory and
    # install dovecot with mysql support.
    ln -s /conf/dovecot /etc/dovecot
    apk add -U dovecot dovecot-lmtpd dovecot-mysql

    info "Installed Dovecot."
    touch /.dovecot-installed
}

install_postfix() {
    if [[ -f /.postfix-installed ]]; then
        return
    fi

    info "Installing Postfix."

    # Link the config directory and
    # install postfix with mysql support.
    ln -s /conf/postfix /etc/postfix
    apk add -U postfix postfix-mysql

    info "Installed Postfix."
    touch /.postfix-installed
}

configure_postfix() {
    if [[ -f /.postfix_configured ]]; then
        return
    fi

    # Copy the template files.
    cp -r /template/postfix/* /conf/postfix/

    # Set the hostname.
    sed -i "s/^myhostname .*$/myhostname = $FQDN/g" /conf/postfix/main.cf
    touch /.postfix_configured

    # Set the MySQL login details.
    for config_file in mysql-virtual-mailbox-domains.cf mysql-virtual-mailbox-maps.cf mysql-virtual-alias-maps.cf; do
        sed -i "s/^user .*$/user = $DATABASE_USER/g" "/conf/postfix/$config_file"
        sed -i "s/^password .*$/password = $DATABASE_PASSWORD/g" "/conf/postfix/$config_file"
        sed -i "s/^hosts .*$/hosts = $DATABASE_HOST/g" "/conf/postfix/$config_file"
        sed -i "s/^dbname .*$/dbname = $DATABASE_NAME/g" "/conf/postfix/$config_file"
    done

    # Make sure there is a /etc/aliases.
    touch /etc/aliases
    newaliases

    info "Configured Postfix."
    touch /.postfix_configured
}

configure_dovecot() {
    if [[ -f /.dovecot-configured ]]; then
        return
    fi

    # First prepare the configuration files
    # by copying the sensible defaults
    # from the template directory.
    cp -r /template/dovecot/* /conf/dovecot/

    # Use environment variables to configure the database
    # connection.
    sed -i "s/\%DATABASE_HOST\%/$DATABASE_HOST/g" /conf/dovecot/dovecot-sql.conf.ext
    sed -i "s/\%DATABASE_NAME\%/$DATABASE_NAME/g" /conf/dovecot/dovecot-sql.conf.ext
    sed -i "s/\%DATABASE_USER\%/$DATABASE_USER/g" /conf/dovecot/dovecot-sql.conf.ext
    sed -i "s/\%DATABASE_PASSWORD\%/$DATABASE_PASSWORD/g" /conf/dovecot/dovecot-sql.conf.ext

    # Enable SSL if configured.
    if [[ -n "$SSL" ]]; then
        sed -i "s/ssl .*/ssl = $SSL/g" /conf/dovecot/conf.d/10-ssl.conf
        sed -i "s/disable_plaintext_auth .*/disable_plaintext_auth = yes/g" /conf/dovecot/conf.d/10-auth.conf
    fi

    # Create a user to hold mail with.
    addgroup -g 5000 vvmail
    adduser -G vvmail -D -H -u 5000 vvmail

    # Make sure there is a dummy cert if none available.
    if [[ ! -f /conf/certificates/certificate.pem || ! -f /conf/certificates/key.pem ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes\
                    -keyout /conf/certificates/key.pem\
                    -out /conf/certificates/certificate.pem\
                    -days 3650\
                    -subj "/CN=$FQDN"
    fi

    # Generate DH parameters if none exist yet.
    if [[ ! -f /conf/certificates/dh.pem ]]; then
        openssl dhparam -out /conf/certificates/dh.pem 4096
    fi

    info "Configured Dovecot."
    touch /.dovecot-configured
}

run_dovecot() {
    info "Dovecot is starting..."
    /usr/sbin/dovecot -F | info_dovecot | tee -a /data/logs/dovecot_daemon.log
    code="$?"
    info "Dovecot exited with $code"
    return "$code"
}

run_postfix() {
    info "Postfix is starting..."
    /usr/sbin/postfix start-fg | info_postfix | tee -a /data/logs/postfix_daemon.log
    code="$?"
    info "Postfix exited with $code"
    return "$code"
}

graceful_exit() {
    # Get the pids.
    postfix_pid="$1"
    dovecot_pid="$2"

    # Send a SIGTERM to both pids.
    kill -SIGTERM "$postfix_pid"
    kill -SIGTERM "$dovecot_pid"
}

main() {
    # Time to bring it all together.

    # First check if all directories that
    # need to be there are present.
    check_dirs

    # Make sure the softwares are installed.
    install_postfix
    install_dovecot

    # Make sure both are configured too.
    configure_postfix
    configure_dovecot

    # Also check permissions of these directories.
    check_permissions

    # Run both on the background and wait
    # for their exit. Send a SIGTERM to both
    # if sent to this script.
    run_dovecot &
    dovecot_pid="$!"

    run_postfix &
    postfix_pid="$!"

    trap 'graceful_exit $postfix_pid $dovecot_pid' SIGTERM SIGINT

    # Wait for both to gracefully exit.
    wait "$postfix_pid"
    wait "$dovecot_pid"

    exit 0
}

main
