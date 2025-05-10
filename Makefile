#!make

# export $(shell chmod a+x bin/load-env.sh)
# export $(shell bin/load-env.sh)

include .env.local
export $(shell sed 's/=.*//' .env.local)

GLOBAL_STACK_COMPOSE_CLI_SERVICE ?=
GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND ?=
GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS ?=
GLOBAL_STACK_COMPOSE_CLI ?= docker compose

default: help

help:
	@echo "Welcome to the multipurpose dockerized stack\n"
	@echo " --- Version : ${GLOBAL_STACK_VERSION} ---"
	@echo "*********************************************\n"
	@echo "XXXXXXXXXXXXX This stack works only on linux for the moment (i think) !!\n"
	@echo "XXXXXXXXXXXXX This stack uses docker compose v2 !!\n"
	@echo " -- Where you can run multiple projects in multiple containers but in the same stack\n"
	@echo " -- I switch between many projects, so installing the tech stack in my host machine is not really an option \n"
	@echo " -- Same as running different dockerized projects separately where you need to docker-compose up .. docker-compose down ... it's time consuming for me \n"
	@echo " -- And so i created this, where i have all i need in different containers but they communicate together \n"
	@echo " -- *** IMPORTANT base should always be present within DOCKER_COMPOSE in .env or .env.local (many other images are based on it) \n"
	@echo " -- *** IMPORTANT If you are using any node image you should include nvm within DOCKER_COMPOSE in .env or .env.local \n"
	@echo " -- *** IMPORTANT If you are using any php image you should include phpbrew within DOCKER_COMPOSE in .env or .env.local \n"
	@echo " ------ Enough with the introduction ------ \n"
	@echo " ------ How does it work ?? ------ \n"
	@echo " ------ ******** 1 - Install/update the latest versions of docker.io and docker-compose \n"
	@echo " ------ ******** 2 - Copy .env to .env.local \n"
	@echo " ------ ******** 2 ---- .1 - COMPOSE_FILE : choose the docker images you want to use, i have some prepared already ***** WARNING ---- But always leave docker-compose.yaml ***** \n"
	@echo " ------ ******** 2 ---- .* ---- do not leave a ; at the end ! \n"
	@echo " ------ ******** 2 ---- .3 - GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS : This contains all the virtual hosts that are declared in 'docker/images/01httpd/conf/sites-enabled', format (separated by space) : myhost.local myhost2.local  \n"
	@echo " ------ ******** 2 ---- .* ---- - These virtual hosts should be in you host /etc/hosts also \n"
	@echo " ------ ******** 2 ---- .4 - GIT_USERNAME and GIT_EMAIL : set them so you can use git inside the containers \n"
	@echo " ------ ******** 3 - Copy your ~/.ssh files in docker/config/root/.ssh \n"
	@echo " ------ ******** You are almost done :) \n"
	@echo " ------ ******** 4 - All you projects should go in ./projects , in docker containers you can access them from /projects \n"
	@echo " ------ ******** * - All the virtual hosts declared in 'docker/images/01httpd/conf/sites-enabled' should point to projects that are in /projects (which is ./projects in your host) \n"
	@echo " ------ ******** And you are done :D \n"
	@echo " ------ ******** Now go to a terminal, navigate to where the is (i.e. /home/stack/) and run 'make down-n-rebuild-force-recreate' \n"
	@echo " ------ ******** To kill the stack run 'make down' \n"
	@echo " ------ ******** If you encounter any probléme contact takieddine.messaoudi.official@gmail.com \n"
	@echo " ------ ************************************************************************** \n"
	@echo " ------ ************************************************************************** \n"
	@echo " ------ ************************************************************************** \n"
	@echo " ------ ******** Local files : \n"
	@echo " ------ ******** --- if you want to create another docker compose / Dockerfile or even modifie your makefile without it being tracked by git \n"
	@echo " ------ ******** --- juste name the file local.Makefile or Makefile.local (same for Dockerfile and docker-compose) \n"
	@echo " ------ ******** --- And then put the relative docker-compose file in .env.local COMPOSE_FILE separated by ; \n"
	@echo " ------ ******** Some known problems : \n"
	@echo " ------ ******** Sometimes databaes containers (specifically mysql) does not take the user and pass from the first time \n"
	@echo " ------ ******** Or you won't be able to connect to it from phpmyadmin \n"
	@echo " ------ ******** Solution :  \n"
	@echo " ------ ******** --- Wait for it, give time, if it does not work \n"
	@echo " ------ ******** --- Stop stack \n"
	@echo " ------ ******** --- Delete docker/data/mysql/{version} folder \n"
	@echo " ------ ******** --- Try again until it works \n"
	@echo " ------ ******** Templates \n"
	@echo " ------ ******** --- take a look at ./templates :) \n"
mkdir-p:
	mkdir -p ${GLOBAL_STACK_TARGET_DIR}
touch:
	touch ${GLOBAL_STACK_TARGET_FILE}
create-paths:
	$(MAKE) GLOBAL_STACK_TARGET_DIR="tools ${GLOBAL_STACK_AXLLENT_MAILPIT_MP_DATABASE} docker/data/dumps/dpage-pgadmin4 ./docker/registry/certs/ ./docker/registry/data/ ./docker/registry/registry/" mkdir-p --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_TARGET_FILE="${GLOBAL_STACK_SHELL_HISTORY} tools/.gitkeep ./docker/registry/certs/.gitkeep ./docker/registry/data/.gitkeep ./docker/registry/registry/.gitkeep" touch --silent --ignore-errors --keep-going --warn-undefined-variables
docker-compose: create-paths
	${GLOBAL_STACK_COMPOSE_CLI} --env-file .env.local ${GLOBAL_STACK_COMPOSE_CLI_EXEC} ${GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS} ${GLOBAL_STACK_COMPOSE_CLI_SERVICE} ${GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND}
create-buildx-builder:
	docker buildx stop docker-buildx-builder &>/dev/null
	docker buildx rm docker-buildx-builder &>/dev/null
	docker build --file docker/buildkit/Dockerfile --build-arg GLOBAL_STACK_MOBY_BUILDKIT_VERSION=${GLOBAL_STACK_MOBY_BUILDKIT_VERSION} --build-arg GLOBAL_STACK_LOCAL_REGISTRY_ALIAS=${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS} --tag custom-moby/buildkit .
	[ ! -f ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json ] && cp ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.json ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json || true
	docker buildx create --debug --name docker-buildx-builder --driver docker-container --driver-opt image=custom-moby/buildkit --driver-opt network=host --driver-opt env.BUILDKIT_REGISTRY_CONFIG=${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json --driver-opt env.BUILDKIT_EXTRA_MOUNTS=[/stack/docker/registry/certs/local-global-stack-registry.local.crt:/etc/ssl/certs/local-global-stack-registry.local.crt:ro] --use
	docker buildx inspect --debug --bootstrap
start-local-registory:
	docker stop ${GLOBAL_STACK_LOCAL_REGISTRY_NAME} &>/dev/null
	sleep 10
	docker rm ${GLOBAL_STACK_LOCAL_REGISTRY_NAME} &>/dev/null
	openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes -keyout ./docker/registry/certs/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}.key -out ./docker/registry/certs/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}.crt -subj "/CN=${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}" -addext "subjectAltName=DNS:${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}"
	sudo cp ./docker/registry/certs/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}.crt /usr/local/share/ca-certificates/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}.crt
	sudo update-ca-certificates
	sudo mkdir -p /etc/docker/certs.d/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000}
	sudo cp ./docker/registry/certs/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}.crt /etc/docker/certs.d/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000}/ca.crt
	sudo systemctl restart docker
	docker run --detach --publish ${GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000}:5000 --restart=always --mount type=bind,source=./docker/registry/certs,target=/docker/registry/certs --env REGISTRY_HTTP_ADDR=0.0.0.0:5000 --env REGISTRY_HTTP_TLS_CERTIFICATE=/docker/registry/certs/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}.crt --env REGISTRY_HTTP_TLS_KEY=/docker/registry/certs/${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}.key --env REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data --mount type=bind,source=./docker/registry/data,target=/data --mount type=bind,source=./docker/registry/registry,target=/var/lib/registry --name ${GLOBAL_STACK_LOCAL_REGISTRY_NAME} registry:${GLOBAL_STACK_LOCAL_REGISTRY_VERSION}
build: create-paths
	# change the order of this in local.Makefile
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="00base" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="00base" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01httpd" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01nginx" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01caddy" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01localstack-localstack" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01epiclabs-docker-oracle-xe-11g" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01axllent-mailpit" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mariadb11" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mongo8" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mysql8" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01postgres17" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01redis" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01valkey" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01selenium-standalone-chrome" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01selenium-standalone-firefox" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02dpage-pgadmin4" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02mongoclient-mongoclient" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02nvm" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02nvm" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02phpbrew" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02phpbrew" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02pyenv" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02pyenv" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rbenv" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rbenv" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rust" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rust" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sdkman" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sdkman" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sonarqube" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sonarqube" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java11-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java11-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java17-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java17-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java24-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java24-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node18" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node18" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node22" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node22" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node24" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node24" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-2" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-2" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-4" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-4" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-5" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-5" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03python3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03python3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03ruby3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03ruby3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04android" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="push" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04android" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04serverless-framework" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="build" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04phpmyadmin" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
up: create-paths
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="up" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--remove-orphans --detach" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
up-build: create-paths
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="up" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--remove-orphans --detach --build" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
up-build-force-recreate: create-paths
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="up" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--remove-orphans --detach --build --force-recreate --always-recreate-deps" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
down:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="down" GLOBAL_STACK_COMPOSE_CLI_EXEC_FLAGS="--remove-orphans" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
down-n-rebuild: down build up-build
down-n-rebuild-force-recreate: down build up-build-force-recreate
rebuild: up-build
rebuild-force-recreate: up-build-force-recreate
# remove build from here (if you already built the stack)
down-n-up: down up

login-02dpage-pgadmin4:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02dpage-pgadmin4" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="sh" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02mongoclient-mongoclient:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02mongoclient-mongoclient" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-04phpmyadmin:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04phpmyadmin" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01httpd:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01httpd" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01mariadb11:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mariadb11" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01mysql8:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mysql8" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01mongo8:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mongo8" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01epiclabs-docker-oracle-xe-11g:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01epiclabs-docker-oracle-xe-11g" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01postgres17:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01postgres17" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="sh" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02nvm:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02nvm" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02sdkman:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sdkman" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03java11-zulu:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java11-zulu" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03java17-zulu:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java17-zulu" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03java24-zulu:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java24-zulu" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02phpbrew:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02phpbrew" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02rbenv:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rbenv" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03ruby3:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03ruby3" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-2:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-2" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-3:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-3" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-4:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-4" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-5:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-5" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-00base:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="00base" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03node18:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node18" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03node22:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node22" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01selenium-standalone-chrome:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01selenium-standalone-chrome" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01selenium-standalone-firefox:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01selenium-standalone-firefox" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02sonarqube:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sonarqube" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01axllent-mailpit:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01axllent-mailpit" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-04android:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04android" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02rust:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rust" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-02pyenv:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02pyenv" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-03python3:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03python3" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01redis:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01redis" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="sh" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01valkey:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01valkey" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="sh" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01nginx:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01nginx" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01localstack-localstack:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01localstack-localstack" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-00corentinth-it-tools:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="00corentinth-it-tools" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-01caddy:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01caddy" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
login-04serverless-framework:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04serverless-framework" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables

log-02dpage-pgadmin4:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02dpage-pgadmin4" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02mongoclient-mongoclient:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02mongoclient-mongoclient" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-04phpmyadmin:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04phpmyadmin" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01httpd:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01httpd" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01mariadb11:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mariadb11" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01epiclabs-docker-oracle-xe-11g:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01epiclabs-docker-oracle-xe-11g" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01mysql8:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mysql8" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01mongo8:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01mongo8" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01postgres17:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01postgres17" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-00base:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="00base" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02nvm:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02nvm" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02sdkman:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sdkman" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03java11-zulu:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java11-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03java17-zulu:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java17-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03java24-zulu:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03java24-zulu" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02phpbrew:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02phpbrew" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02rbenv:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rbenv" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03ruby3:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03ruby3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-2:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-2" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-3:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-4:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-4" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-5:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03php8-5" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03node18:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node18" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03node22:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node22" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03node24:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03node24" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01selenium-standalone-chrome:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01selenium-standalone-chrome" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01selenium-standalone-firefox:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01selenium-standalone-firefox" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02sonarqube:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02sonarqube" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01axllent-mailpit:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01axllent-mailpit" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-04android:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04android" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02rust:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02rust" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-02pyenv:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="02pyenv" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-03python3:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="03python3" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01redis:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01redis" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01valkey:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01valkey" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01nginx:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01nginx" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01localstack-localstack:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01localstack-localstack" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-00corentinth-it-tools:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="00corentinth-it-tools" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-01caddy:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="01caddy" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
log-04serverless-framework:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="04serverless-framework" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables

restart-x:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="restart" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
save:
	source .env.local && docker save $(docker images --format '{{.Repository}}:{{.Tag}}') -o var/images/stack-${GLOBAL_STACK_VERSION}.tar
commit:
	source .env.local && docker commit ${CONTAINER_NAME} repository:tag
restore:
	source .env.local && docker load -i var/images/stack-${GLOBAL_STACK_VERSION}.tar
log-follow:
	$(MAKE) GLOBAL_STACK_COMPOSE_CLI_EXEC="logs --follow" docker-compose --silent --ignore-errors --keep-going --warn-undefined-variables
hard-restart:
	$(MAKE) down --silent --ignore-errors --keep-going --warn-undefined-variables
	docker system prune -a -f --volumes
	yes y | docker-reclaim-disk-space-script.sh || echo 'script does not exist'
	sudo rm -rf tools 
	cp -R var/tools/ tools
	sudo rm -rf ./docker/registry/data ./docker/registry/certs
	mkdir -p ./docker/registry/data ./docker/registry/certs
	touch ./docker/registry/data/.gitkeep ./docker/registry/registry/.gitkeep ./docker/registry/certs/.gitkeep
	$(MAKE) start-local-registory
	$(MAKE) create-buildx-builder
	$(MAKE) down-n-rebuild-force-recreate --silent --ignore-errors --keep-going --warn-undefined-variables

