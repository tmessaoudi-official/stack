#!make

# export $(shell chmod a+x bin/load-env.sh)
# export $(shell bin/load-env.sh)

GLOBAL_STACK_DOCKER_CLI_SERVICE ?=
GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND ?=
GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS ?=
GLOBAL_STACK_DOCKER_CLI_EXEC ?=
GLOBAL_STACK_DOCKER_CLI ?=
GLOBAL_STACK_DOCKER_CLI_DOT_ENV ?= .env.local
GLOBAL_STACK_DOCKER_CLI_FLAGS ?=

include ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}
export $(shell sed 's/=.*//' ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV})

GLOBAL_STACK_DOCKER_CLI_NO_COMPOSE_BAKE ?= ${COMPOSE_BAKE}

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
	@echo " -- *** IMPORTANT base should always be present within DOCKER_COMPOSE in .env or ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} (many other images are based on it) \n"
	@echo " -- *** IMPORTANT If you are using any node image you should include nvm within DOCKER_COMPOSE in .env or ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} \n"
	@echo " -- *** IMPORTANT If you are using any php image you should include phpbrew within DOCKER_COMPOSE in .env or ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} \n"
	@echo " ------ Enough with the introduction ------ \n"
	@echo " ------ How does it work ?? ------ \n"
	@echo " ------ ******** 1 - Install/update the latest versions of docker.io and docker-compose \n"
	@echo " ------ ******** 2 - Copy .env to ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} \n"
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
	@echo " ------ ******** --- And then put the relative docker-compose file in ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} COMPOSE_FILE separated by ; \n"
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
generate-buildx:
	rm -rf ${BUILDX_BAKE_FILE} ${COMPOSE_FULL_FILE}
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="config" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--output ${COMPOSE_FULL_FILE}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="bake" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--file ${COMPOSE_FULL_FILE} --print" GLOBAL_STACK_DOCKER_CLI="docker buildx" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables > ${BUILDX_BAKE_FILE}
docker-cli: create-paths
	# @echo ${GLOBAL_STACK_DOCKER_CLI} ${GLOBAL_STACK_DOCKER_CLI_FLAGS} ${GLOBAL_STACK_DOCKER_CLI_EXEC} ${GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS} ${GLOBAL_STACK_DOCKER_CLI_SERVICE} ${GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND}
	# COMPOSE_BAKE=${GLOBAL_STACK_DOCKER_CLI_NO_COMPOSE_BAKE} 
	${GLOBAL_STACK_DOCKER_CLI} ${GLOBAL_STACK_DOCKER_CLI_FLAGS} ${GLOBAL_STACK_DOCKER_CLI_EXEC} ${GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS} ${GLOBAL_STACK_DOCKER_CLI_SERVICE} ${GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND}
create-buildx-builder:
	docker buildx stop docker-buildx-builder &>/dev/null
	docker buildx rm docker-buildx-builder &>/dev/null
	docker build --file docker/buildkit/Dockerfile --build-arg GLOBAL_STACK_MOBY_BUILDKIT_VERSION=${GLOBAL_STACK_MOBY_BUILDKIT_VERSION} --build-arg GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS} --tag custom-moby/buildkit .
	[ ! -f ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json ] && cp ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.json ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json || true
	sudo systemctl stop docker
	sudo rm -rf /var/lib/docker/volumes/buildx_buildkit_docker-buildx-builder0_state
	sudo systemctl start docker
	docker buildx create --debug --name docker-buildx-builder --driver docker-container --driver-opt image=custom-moby/buildkit --driver-opt network=host --driver-opt env.BUILDKIT_REGISTRY_CONFIG=${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json --driver-opt env.BUILDKIT_EXTRA_MOUNTS=[/stack/docker/registry/certs/local-global-stack-registry.local.crt:/etc/ssl/certs/local-global-stack-registry.local.crt:ro] --use
	docker buildx inspect --debug --bootstrap
start-local-registry:
	docker stop ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME} &>/dev/null
	sleep 10
	docker rm ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME} &>/dev/null
	openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes -keyout ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.key -out ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt -subj "/CN=${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}" -addext "subjectAltName=DNS:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}"
	sudo cp ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt /usr/local/share/ca-certificates/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt
	sudo update-ca-certificates
	sudo mkdir -p /etc/docker/certs.d/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}
	sudo cp ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt /etc/docker/certs.d/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/ca.crt
	sudo systemctl restart docker
	docker run --detach --publish ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}:5000 --restart=always --mount type=bind,source=./docker/registry/certs,target=/docker/registry/certs --env REGISTRY_HTTP_ADDR=0.0.0.0:5000 --env REGISTRY_HTTP_TLS_CERTIFICATE=/docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt --env REGISTRY_HTTP_TLS_KEY=/docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.key --env REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data --mount type=bind,source=./docker/registry/data,target=/data --mount type=bind,source=./docker/registry/registry,target=/var/lib/registry --name ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME} registry:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION}
build: create-paths generate-buildx
	# change the order of this in local.Makefile
	@jq -r '.group.default.targets[]' ${BUILDX_BAKE_FILE} | while read target; do echo "Processing $$target..."; $(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="bake" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--push --load" GLOBAL_STACK_DOCKER_CLI="docker buildx" GLOBAL_STACK_DOCKER_CLI_SERVICE="$$target" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables ;done
up: create-paths generate-buildx
	rm -rf ${BUILDX_BAKE_FILE} ${COMPOSE_FULL_FILE}
	GLOBAL_STACK_DOCKER_CLI_NO_COMPOSE_BAKE="false" $(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="up" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--remove-orphans --detach" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
up-build: create-paths generate-buildx
	rm -rf ${BUILDX_BAKE_FILE} ${COMPOSE_FULL_FILE}
	GLOBAL_STACK_DOCKER_CLI_NO_COMPOSE_BAKE="false" $(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="up" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--remove-orphans --detach --build" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
up-build-force-recreate: create-paths generate-buildx
	rm -rf ${BUILDX_BAKE_FILE} ${COMPOSE_FULL_FILE}
	GLOBAL_STACK_DOCKER_CLI_NO_COMPOSE_BAKE="false" $(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="up" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--remove-orphans --detach --build --force-recreate --always-recreate-deps" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
down:
	rm -rf ${BUILDX_BAKE_FILE} ${COMPOSE_FULL_FILE}
	GLOBAL_STACK_DOCKER_CLI_NO_COMPOSE_BAKE="false" $(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="down" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--remove-orphans" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
down-n-rebuild: down build up-build
down-n-rebuild-force-recreate: down build up-build-force-recreate
rebuild: up-build
rebuild-force-recreate: up-build-force-recreate
# remove build from here (if you already built the stack)
down-n-up: down up

login-02dpage-pgadmin4:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02dpage-pgadmin4" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="sh" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02keycloak-keycloak:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02keycloak-keycloak" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02mongoclient-mongoclient:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02mongoclient-mongoclient" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-04phpmyadmin:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="04phpmyadmin" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01httpd:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01httpd" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01mariadb12:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01mariadb12" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01mysql9:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01mysql9" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01mongo8:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01mongo8" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01epiclabs-docker-oracle-xe-11g:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01epiclabs-docker-oracle-xe-11g" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01postgres18:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01postgres18" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="sh" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02nvm:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02nvm" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02sdkman:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02sdkman" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03java11-zulu:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03java11-zulu" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03java17-zulu:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03java17-zulu" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03java25-zulu:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03java25-zulu" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02phpbrew:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02phpbrew" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02rbenv:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02rbenv" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03ruby3:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03ruby3" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-2:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-2" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-3:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-3" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-4:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-4" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03php8-5:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-5" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03phpnext:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03phpnext" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-00base:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="00base" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03node22:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03node22" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03node24:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03node24" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03node26:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03node26" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01selenium-standalone-chrome:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01selenium-standalone-chrome" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01selenium-standalone-firefox:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01selenium-standalone-firefox" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02sonarqube:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02sonarqube" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01axllent-mailpit:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01axllent-mailpit" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-04android:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="04android" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02rust:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02rust" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-02pyenv:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="02pyenv" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-03python3:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="03python3" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01redis:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01redis" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="sh" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01valkey:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01valkey" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="sh" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01nginx:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01nginx" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01localstack-localstack:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01localstack-localstack" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-00corentinth-it-tools:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="00corentinth-it-tools" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-01caddy:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="01caddy" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
login-04serverless-framework:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="04serverless-framework" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables

log-02dpage-pgadmin4:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02dpage-pgadmin4" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02keycloak-keycloak:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02keycloak-keycloak" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02mongoclient-mongoclient:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02mongoclient-mongoclient" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-04phpmyadmin:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="04phpmyadmin" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01httpd:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01httpd" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01mariadb12:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01mariadb12" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01epiclabs-docker-oracle-xe-11g:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01epiclabs-docker-oracle-xe-11g" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01mysql9:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01mysql9" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01mongo8:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01mongo8" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01postgres18:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01postgres18" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-00base:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="00base" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02nvm:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02nvm" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02sdkman:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02sdkman" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03java11-zulu:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03java11-zulu" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03java17-zulu:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03java17-zulu" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03java25-zulu:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03java25-zulu" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02phpbrew:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02phpbrew" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02rbenv:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02rbenv" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03ruby3:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03ruby3" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-2:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-2" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-3:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-3" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-4:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-4" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03php8-5:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03php8-5" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03phpnext:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03phpnext" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03node22:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03node22" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03node24:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03node24" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03node26:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03node26" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01selenium-standalone-chrome:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01selenium-standalone-chrome" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01selenium-standalone-firefox:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01selenium-standalone-firefox" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02sonarqube:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02sonarqube" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01axllent-mailpit:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01axllent-mailpit" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-04android:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="04android" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02rust:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02rust" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-02pyenv:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="02pyenv" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-03python3:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="03python3" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01redis:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01redis" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01valkey:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01valkey" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01nginx:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01nginx" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01localstack-localstack:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01localstack-localstack" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-00corentinth-it-tools:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="00corentinth-it-tools" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-01caddy:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="01caddy" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
log-04serverless-framework:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="04serverless-framework" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables

restart-x:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="restart" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
save:
	source ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} && docker save $(docker images --format '{{.Repository}}:{{.Tag}}') -o var/images/stack-${GLOBAL_STACK_VERSION}.tar
commit:
	source ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} && docker commit ${CONTAINER_NAME} repository:tag
restore:
	source ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} && docker load -i var/images/stack-${GLOBAL_STACK_VERSION}.tar
log-follow:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs --follow" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
hard-restart:
	bin/load-env.sh --update-differences="update_differences"
	yes y | global-unu.sh || echo 'script does not exit'
	$(MAKE) down --silent --ignore-errors --keep-going --warn-undefined-variables
	docker system prune -a -f --volumes
	yes y | docker-reclaim-disk-space-script.sh || echo 'script does not exist'
	sudo rm -rf tools ./docker/registry/data ./docker/registry/certs
	cp -R var/tools/ tools
	$(MAKE) create-paths --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) start-local-registry --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) create-buildx-builder --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) build --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) up --silent --ignore-errors --keep-going --warn-undefined-variables

