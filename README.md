# stack

# Bugs
Lock files create problems when waiting and then trying to show waiting for what when the other has finished and removed the lock file
## Run make or make help to see how to set up the project 
Dockerized local development environment

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
create folder if not exists : docker/data/postgres/xx
docker/images/02dpage-pgadmin4/dist/conf/servers.json — contains the default server (copied into image by Dockerfile)
you add to it or change to load new local/distant servers
# Mongoclient (nosqlclient)

# Selenium
and add the virtual hosts you defined in your apache containers, apache ip address will be replaced automatically after by the real address of the container
or you can add new lines and define ip ad domains
to make them accessbile to selenium when running google chrome
change the env variable GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS

# Compose
change les fichier docker-compose utilisé dans le fichier env.local COMPOSE_FILE pour avoir le stack que tu veux
# Up 
make down-n-rebuild-force-recreate --ignore-errors --keep-going
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