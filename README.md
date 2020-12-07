# Mail Server
This image automates both postfix and dovecot in a single image. It sets up SASL
authentication between the two and makes sure there are valid certificates for
the mail server to operate securely. This mail server also requires a MySQL database
to operate with, no more creating Linux users so a mail account is created.

## How to set it up
The easiest way is by combining the [maildb](https://hub.docker.com/r/eyedevelop/maildb) image
and this one in one Docker Compose file. If no certificate can be found, the container generates one.

The default configuration should be sufficient and secure for running your own mail server.

An example docker-compose.yml:
```
version: '3'
services:
  maildb:
    image: eyedevelop/maildb
    container_name: maildb
    volumes:
      - "./maildb:/var/lib/mysql"
    ports:
      - "3306:3306"
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=verisecure
      - MAILDB_PASSWORD=mysecurepassword

  mail-server:
    image: eyedevelop/mail-server
    container_name: mail-server
    depends_on:
      - maildb
    volumes:
      - "./mail-server/conf:/conf"
      - "./mail-server/data:/data"
    ports:
      - "25:25"
      - "587:587"
      - "993:993"
    restart: unless-stopped
    environment:
      - DATABASE_HOST=maildb
      - DATABASE_NAME=maildb
      - DATABASE_USER=mailadmin
      - DATABASE_PASSWORD=mysecurepassword
      - SSL=required
      - FQDN=example.org
```

Do note that the mail-server container does **NOT** create the
required tables in the database.

Please refer to the [maildb container](https://hub.docker.com/r/eyedevelop/maildb)
for instructions how to create users and set up aliases.

# Good luck and have fun!
If you like this image, please [donate a coffee](https://paypal.me/eyegaming2) :)