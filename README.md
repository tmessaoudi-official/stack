# stack

Dockerized local development environment. Run `make help` to see all available targets.

# Important 

base should always be present within COMPOSE_FILE in .env or .env.local (many other images are based on it)

If you are using any node image you should include nvm within COMPOSE_FILE in .env or .env.local

If you are using any php image you should include phpbrew within COMPOSE_FILE in .env or .env.local

# Ssh files
Put your id_rsa and id_rsa.pub and known_hosts in docker/config/root/.ssh/ ,
php dockers will install git and add your identity so you may use git inside docker

# Apache/Nginx
## Virtual hosts
Put all your virtual hosts conf files in docker/config/dist/conf/httpd-conf/sites-available or docker/config/dist/conf/nginx-conf/sites-available
all the files in there will be activated except
example.*
## Confs
Put all your conf files in docker/config/dist/conf/httpd-conf/conf-available
all the files in there will be activated

# Docker containers shared Executables
tools contains list of executables 
npm, yarn, composer, symfony installer and cli, deployer
you can add to them they will be available in your containers 
# Phpmyadmin
docker/config/dist/conf/phpmyadmin/config.user.inc.php contains the default server (docker image)
you add to it or change to load new local/distant servers
# PGadmin (postgres)
`docker/images/02dpage-pgadmin4/dist/conf/servers.json` — contains the default server (copied into the image by Dockerfile)
you add to it or change to load new local/distant servers

# Selenium
1. Set `GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS` to the virtual hosts defined in your Apache/Nginx containers
2. The container IP addresses are resolved automatically at startup and injected into the browser hosts file

# Compose
Set `COMPOSE_FILE` in `.env.local` to select which services to start. See `make help` for syntax.

# Up
make up

# After a version change (make down-n-rebuild-force-recreate) or full teardown (make hard-restart)
See `make help` for details.
# SSL
####execute this command in apache container
####as many as your virtualhosts
####replace domain by the virtualhost domain name each time
openssl req -x509 -days 7300 -out /etc/apache2/ssl/domain.crt -keyout /etc/apache2/ssl/domain.key \
  -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=domain' -extensions EXT -config <( \
   printf "[dn]\nCN=domain\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:domain\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")

    SSLEngine on
    SSLCertificateFile "/etc/apache2/ssl/domain.crt"
    SSLCertificateKeyFile "/etc/apache2/ssl/domain.key"