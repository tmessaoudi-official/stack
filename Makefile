#!make

GLOBAL_STACK_DOCKER_CLI_SERVICE ?=
GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND ?=
GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS ?=
GLOBAL_STACK_DOCKER_CLI_EXEC ?=
GLOBAL_STACK_DOCKER_CLI ?=
GLOBAL_STACK_DOCKER_CLI_DOT_ENV ?= .env.local
GLOBAL_STACK_DOCKER_CLI_FLAGS ?=

-include ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}
export $(shell sed 's/=.*//' ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV})

GLOBAL_STACK_DOCKER_CLI_NO_COMPOSE_BAKE ?= ${COMPOSE_BAKE}

default: help

.PHONY: help mkdir-p touch create-paths generate-buildx docker-cli create-buildx-builder \
	start-local-registry build up up-build up-build-force-recreate down \
	down-n-rebuild down-n-rebuild-force-recreate rebuild rebuild-force-recreate \
	down-n-up exec restart health wait-healthy save commit restore log-follow hard-restart soft-restart \
	login-00base login-00corentinth-it-tools \
	login-01axllent-mailpit login-01caddy login-01epiclabs-docker-oracle-xe-11g \
	login-01httpd login-01localstack-localstack login-01mariadb12 login-01mongo7 \
	login-01mysql9 login-01nginx login-01postgres18 login-01redis \
	login-01selenium-standalone-chrome login-01selenium-standalone-firefox \
	login-01valkey \
	login-02dpage-pgadmin4 login-02fvm login-02keycloak-keycloak \
	login-02mongoclient-mongoclient login-02nvm login-02phpbrew login-02pyenv \
	login-02rbenv login-02rust login-02sdkman login-02sonarqube \
	login-03java17-zulu login-03flutter3 login-03java21-zulu login-03java26-zulu \
	login-03node24 login-03node26 login-03nodeedge \
	login-03php8-4 login-03php8-5 login-03phpedge \
	login-03python3 login-03ruby3 login-03ruby4 \
	login-04android login-04phpmyadmin login-04serverless-framework \
	login-05edge login-05stable \
	log-00base log-00corentinth-it-tools \
	log-01axllent-mailpit log-01caddy log-01epiclabs-docker-oracle-xe-11g \
	log-01httpd log-01localstack-localstack log-01mariadb12 log-01mongo7 \
	log-01mysql9 log-01nginx log-01postgres18 log-01redis \
	log-01selenium-standalone-chrome log-01selenium-standalone-firefox \
	log-01valkey \
	log-02dpage-pgadmin4 log-02fvm log-02keycloak-keycloak \
	log-02mongoclient-mongoclient log-02nvm log-02phpbrew log-02pyenv \
	log-02rbenv log-02rust log-02sdkman log-02sonarqube \
	log-03flutter3 log-03java17-zulu log-03java21-zulu log-03java26-zulu \
	log-03node24 log-03node26 log-03nodeedge \
	log-03php8-4 log-03php8-5 log-03phpedge \
	log-03python3 log-03ruby3 log-03ruby4 \
	log-04android log-04phpmyadmin log-04serverless-framework \
	log-05edge log-05stable \
	log-follow-00base log-follow-00corentinth-it-tools \
	log-follow-01axllent-mailpit log-follow-01caddy log-follow-01epiclabs-docker-oracle-xe-11g \
	log-follow-01httpd log-follow-01localstack-localstack log-follow-01mariadb12 log-follow-01mongo7 \
	log-follow-01mysql9 log-follow-01nginx log-follow-01postgres18 log-follow-01redis \
	log-follow-01selenium-standalone-chrome log-follow-01selenium-standalone-firefox \
	log-follow-01valkey \
	log-follow-02dpage-pgadmin4 log-follow-02fvm log-follow-02keycloak-keycloak \
	log-follow-02mongoclient-mongoclient log-follow-02nvm log-follow-02phpbrew log-follow-02pyenv \
	log-follow-02rbenv log-follow-02rust log-follow-02sdkman log-follow-02sonarqube \
	log-follow-03flutter3 log-follow-03java17-zulu log-follow-03java21-zulu log-follow-03java26-zulu \
	log-follow-03node24 log-follow-03node26 log-follow-03nodeedge \
	log-follow-03php8-4 log-follow-03php8-5 log-follow-03phpedge \
	log-follow-03python3 log-follow-03ruby3 log-follow-03ruby4 \
	log-follow-04android log-follow-04phpmyadmin log-follow-04serverless-framework \
	log-follow-05edge log-follow-05stable \
	restart-00base restart-00corentinth-it-tools \
	restart-01axllent-mailpit restart-01caddy restart-01epiclabs-docker-oracle-xe-11g \
	restart-01httpd restart-01localstack-localstack restart-01mariadb12 restart-01mongo7 \
	restart-01mysql9 restart-01nginx restart-01postgres18 restart-01redis \
	restart-01selenium-standalone-chrome restart-01selenium-standalone-firefox \
	restart-01valkey \
	restart-02dpage-pgadmin4 restart-02fvm restart-02keycloak-keycloak \
	restart-02mongoclient-mongoclient restart-02nvm restart-02phpbrew restart-02pyenv \
	restart-02rbenv restart-02rust restart-02sdkman restart-02sonarqube \
	restart-03flutter3 restart-03java17-zulu restart-03java21-zulu restart-03java26-zulu \
	restart-03node24 restart-03node26 restart-03nodeedge \
	restart-03php8-4 restart-03php8-5 restart-03phpedge \
	restart-03python3 restart-03ruby3 restart-03ruby4 \
	restart-04android restart-04phpmyadmin restart-04serverless-framework \
	restart-05edge restart-05stable

# Macro: login with ${GLOBAL_STACK_SHELL} (bash/zsh capable containers)
define login-service-shell
login-$(1):
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="$(1)" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="$${GLOBAL_STACK_SHELL}" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file $${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
endef

# Macro: login with sh (containers that only have sh, e.g. postgres, redis, pgadmin)
define login-service-sh
login-$(1):
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI_SERVICE="$(1)" GLOBAL_STACK_DOCKER_CLI_CONTAINER_COMMAND="sh" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file $${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
endef

# Macro: tail logs for a service
define log-service
log-$(1):
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs" GLOBAL_STACK_DOCKER_CLI_SERVICE="$(1)" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file $${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
endef

# Macro: tail log-follow for a service
define log-follow-service
log-follow-$(1):
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs --follow" GLOBAL_STACK_DOCKER_CLI_SERVICE="$(1)" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file $${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
endef

# Macro: tail restart for a service
define restart-service
restart-$(1):
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="restart" GLOBAL_STACK_DOCKER_CLI_SERVICE="$(1)" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file $${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
endef

# login targets — shell-capable containers
$(eval $(call login-service-shell,00base))
$(eval $(call login-service-shell,00corentinth-it-tools))
$(eval $(call login-service-shell,01axllent-mailpit))
$(eval $(call login-service-shell,01caddy))
$(eval $(call login-service-shell,01epiclabs-docker-oracle-xe-11g))
$(eval $(call login-service-shell,01httpd))
$(eval $(call login-service-shell,01localstack-localstack))
$(eval $(call login-service-shell,01mariadb12))
$(eval $(call login-service-shell,01mongo7))
$(eval $(call login-service-shell,01mysql9))
$(eval $(call login-service-shell,01nginx))
$(eval $(call login-service-shell,01selenium-standalone-chrome))
$(eval $(call login-service-shell,01selenium-standalone-firefox))
$(eval $(call login-service-shell,02fvm))
$(eval $(call login-service-shell,02keycloak-keycloak))
$(eval $(call login-service-shell,02mongoclient-mongoclient))
$(eval $(call login-service-shell,02nvm))
$(eval $(call login-service-shell,02phpbrew))
$(eval $(call login-service-shell,02pyenv))
$(eval $(call login-service-shell,02rbenv))
$(eval $(call login-service-shell,02rust))
$(eval $(call login-service-shell,02sdkman))
$(eval $(call login-service-shell,02sonarqube))
$(eval $(call login-service-shell,03flutter3))
$(eval $(call login-service-shell,03java17-zulu))
$(eval $(call login-service-shell,03java21-zulu))
$(eval $(call login-service-shell,03java26-zulu))
$(eval $(call login-service-shell,03node26))
$(eval $(call login-service-shell,03node24))
$(eval $(call login-service-shell,03nodeedge))
$(eval $(call login-service-shell,03php8-4))
$(eval $(call login-service-shell,03php8-5))
$(eval $(call login-service-shell,03phpedge))
$(eval $(call login-service-shell,03python3))
$(eval $(call login-service-shell,03ruby3))
$(eval $(call login-service-shell,03ruby4))
$(eval $(call login-service-shell,04android))
$(eval $(call login-service-shell,04phpmyadmin))
$(eval $(call login-service-shell,04serverless-framework))
$(eval $(call login-service-shell,05edge))
$(eval $(call login-service-shell,05stable))

# login targets — sh-only containers
$(eval $(call login-service-sh,01postgres18))
$(eval $(call login-service-sh,01redis))
$(eval $(call login-service-sh,01valkey))
$(eval $(call login-service-sh,02dpage-pgadmin4))

# log targets
$(eval $(call log-service,00base))
$(eval $(call log-service,00corentinth-it-tools))
$(eval $(call log-service,01axllent-mailpit))
$(eval $(call log-service,01caddy))
$(eval $(call log-service,01epiclabs-docker-oracle-xe-11g))
$(eval $(call log-service,01httpd))
$(eval $(call log-service,01localstack-localstack))
$(eval $(call log-service,01mariadb12))
$(eval $(call log-service,01mongo7))
$(eval $(call log-service,01mysql9))
$(eval $(call log-service,01nginx))
$(eval $(call log-service,01postgres18))
$(eval $(call log-service,01redis))
$(eval $(call log-service,01selenium-standalone-chrome))
$(eval $(call log-service,01selenium-standalone-firefox))
$(eval $(call log-service,01valkey))
$(eval $(call log-service,02dpage-pgadmin4))
$(eval $(call log-service,02fvm))
$(eval $(call log-service,02keycloak-keycloak))
$(eval $(call log-service,02mongoclient-mongoclient))
$(eval $(call log-service,02nvm))
$(eval $(call log-service,02phpbrew))
$(eval $(call log-service,02pyenv))
$(eval $(call log-service,02rbenv))
$(eval $(call log-service,02rust))
$(eval $(call log-service,02sdkman))
$(eval $(call log-service,02sonarqube))
$(eval $(call log-service,03flutter3))
$(eval $(call log-service,03java17-zulu))
$(eval $(call log-service,03java21-zulu))
$(eval $(call log-service,03java26-zulu))
$(eval $(call log-service,03node26))
$(eval $(call log-service,03node24))
$(eval $(call log-service,03nodeedge))
$(eval $(call log-service,03php8-4))
$(eval $(call log-service,03php8-5))
$(eval $(call log-service,03phpedge))
$(eval $(call log-service,03python3))
$(eval $(call log-service,03ruby3))
$(eval $(call log-service,03ruby4))
$(eval $(call log-service,04android))
$(eval $(call log-service,04phpmyadmin))
$(eval $(call log-service,04serverless-framework))
$(eval $(call log-service,05edge))
$(eval $(call log-service,05stable))

# log-follow targets
$(eval $(call log-follow-service,00base))
$(eval $(call log-follow-service,00corentinth-it-tools))
$(eval $(call log-follow-service,01axllent-mailpit))
$(eval $(call log-follow-service,01caddy))
$(eval $(call log-follow-service,01epiclabs-docker-oracle-xe-11g))
$(eval $(call log-follow-service,01httpd))
$(eval $(call log-follow-service,01localstack-localstack))
$(eval $(call log-follow-service,01mariadb12))
$(eval $(call log-follow-service,01mongo7))
$(eval $(call log-follow-service,01mysql9))
$(eval $(call log-follow-service,01nginx))
$(eval $(call log-follow-service,01postgres18))
$(eval $(call log-follow-service,01redis))
$(eval $(call log-follow-service,01selenium-standalone-chrome))
$(eval $(call log-follow-service,01selenium-standalone-firefox))
$(eval $(call log-follow-service,01valkey))
$(eval $(call log-follow-service,02dpage-pgadmin4))
$(eval $(call log-follow-service,02fvm))
$(eval $(call log-follow-service,02keycloak-keycloak))
$(eval $(call log-follow-service,02mongoclient-mongoclient))
$(eval $(call log-follow-service,02nvm))
$(eval $(call log-follow-service,02phpbrew))
$(eval $(call log-follow-service,02pyenv))
$(eval $(call log-follow-service,02rbenv))
$(eval $(call log-follow-service,02rust))
$(eval $(call log-follow-service,02sdkman))
$(eval $(call log-follow-service,02sonarqube))
$(eval $(call log-follow-service,03flutter3))
$(eval $(call log-follow-service,03java17-zulu))
$(eval $(call log-follow-service,03java21-zulu))
$(eval $(call log-follow-service,03java26-zulu))
$(eval $(call log-follow-service,03node26))
$(eval $(call log-follow-service,03node24))
$(eval $(call log-follow-service,03nodeedge))
$(eval $(call log-follow-service,03php8-4))
$(eval $(call log-follow-service,03php8-5))
$(eval $(call log-follow-service,03phpedge))
$(eval $(call log-follow-service,03python3))
$(eval $(call log-follow-service,03ruby3))
$(eval $(call log-follow-service,03ruby4))
$(eval $(call log-follow-service,04android))
$(eval $(call log-follow-service,04phpmyadmin))
$(eval $(call log-follow-service,04serverless-framework))
$(eval $(call log-follow-service,05edge))
$(eval $(call log-follow-service,05stable))

# restart targets
$(eval $(call restart-service,00base))
$(eval $(call restart-service,00corentinth-it-tools))
$(eval $(call restart-service,01axllent-mailpit))
$(eval $(call restart-service,01caddy))
$(eval $(call restart-service,01epiclabs-docker-oracle-xe-11g))
$(eval $(call restart-service,01httpd))
$(eval $(call restart-service,01localstack-localstack))
$(eval $(call restart-service,01mariadb12))
$(eval $(call restart-service,01mongo7))
$(eval $(call restart-service,01mysql9))
$(eval $(call restart-service,01nginx))
$(eval $(call restart-service,01postgres18))
$(eval $(call restart-service,01redis))
$(eval $(call restart-service,01selenium-standalone-chrome))
$(eval $(call restart-service,01selenium-standalone-firefox))
$(eval $(call restart-service,01valkey))
$(eval $(call restart-service,02dpage-pgadmin4))
$(eval $(call restart-service,02fvm))
$(eval $(call restart-service,02keycloak-keycloak))
$(eval $(call restart-service,02mongoclient-mongoclient))
$(eval $(call restart-service,02nvm))
$(eval $(call restart-service,02phpbrew))
$(eval $(call restart-service,02pyenv))
$(eval $(call restart-service,02rbenv))
$(eval $(call restart-service,02rust))
$(eval $(call restart-service,02sdkman))
$(eval $(call restart-service,02sonarqube))
$(eval $(call restart-service,03flutter3))
$(eval $(call restart-service,03java17-zulu))
$(eval $(call restart-service,03java21-zulu))
$(eval $(call restart-service,03java26-zulu))
$(eval $(call restart-service,03node26))
$(eval $(call restart-service,03node24))
$(eval $(call restart-service,03nodeedge))
$(eval $(call restart-service,03php8-4))
$(eval $(call restart-service,03php8-5))
$(eval $(call restart-service,03phpedge))
$(eval $(call restart-service,03python3))
$(eval $(call restart-service,03ruby3))
$(eval $(call restart-service,03ruby4))
$(eval $(call restart-service,04android))
$(eval $(call restart-service,04phpmyadmin))
$(eval $(call restart-service,04serverless-framework))
$(eval $(call restart-service,05edge))
$(eval $(call restart-service,05stable))

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
	@echo "  make restart                           # Restart all running containers"
mkdir-p:
	mkdir -p ${GLOBAL_STACK_TARGET_DIR}
touch:
	touch ${GLOBAL_STACK_TARGET_FILE}
create-paths::
	$(MAKE) GLOBAL_STACK_TARGET_DIR="tools var/images ${GLOBAL_STACK_AXLLENT_MAILPIT_MP_DATABASE} docker/data/dumps/dpage-pgadmin4 ./docker/registry/certs/ ./docker/registry/data/ ./docker/registry/registry/" mkdir-p --silent --ignore-errors --keep-going --warn-undefined-variables
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
	rm -rf ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json
	[ ! -f ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json ] && cp ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.json ${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json || true
	sudo systemctl stop docker
	sudo rm -rf /var/lib/docker/volumes/buildx_buildkit_docker-buildx-builder0_state
	sudo systemctl start docker
	docker buildx create --debug --name docker-buildx-builder --driver docker-container --driver-opt image=custom-moby/buildkit --driver-opt network=host --driver-opt env.BUILDKIT_REGISTRY_CONFIG=${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry/config.local.json --driver-opt env.BUILDKIT_EXTRA_MOUNTS=[/stack/docker/registry/certs/local-global-stack-registry.local.crt:/etc/ssl/certs/local-global-stack-registry.local.crt:ro] --use
	docker buildx inspect --debug --bootstrap
start-local-registry:
	docker rm -f ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME} >/dev/null 2>&1 || true
	openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes -keyout ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.key -out ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt -subj "/CN=${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}" -addext "subjectAltName=DNS:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}"
	sudo cp ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt /usr/local/share/ca-certificates/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt
	sudo update-ca-certificates
	sudo mkdir -p /etc/docker/certs.d/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}
	sudo cp ./docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt /etc/docker/certs.d/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/ca.crt
	sudo systemctl restart docker
	docker run --detach --publish ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}:5000 --restart=always --mount type=bind,source=./docker/registry/certs,target=/docker/registry/certs --env REGISTRY_HTTP_ADDR=0.0.0.0:5000 --env REGISTRY_HTTP_TLS_CERTIFICATE=/docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt --env REGISTRY_HTTP_TLS_KEY=/docker/registry/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.key --env REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data --mount type=bind,source=./docker/registry/data,target=/data --mount type=bind,source=./docker/registry/registry,target=/var/lib/registry --name ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME} registry:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION}
build: create-paths generate-buildx
	# change the order of this in local.Makefile
	#  --no-cache --progress=plain
	@echo "=== Building all targets (tagged: push+load, untagged: load only) ==="; \
	_failed_file=$$(mktemp) || { echo "Error: mktemp failed"; exit 1; }; \
	trap "rm -f $$_failed_file" EXIT; \
	jq -r '.group.default.targets[]' ${BUILDX_BAKE_FILE} | while IFS= read -r _target; do \
	  _has_tags=$$(jq -r --arg t "$$_target" '.target[$$t].tags // empty | length > 0' ${BUILDX_BAKE_FILE} 2>/dev/null); \
	  if [ "$$_has_tags" = "true" ]; then \
	    echo "Building + pushing $$_target (tagged)..."; \
	    $(MAKE) \
	      GLOBAL_STACK_DOCKER_CLI="docker buildx" \
	      GLOBAL_STACK_DOCKER_CLI_EXEC="bake" \
	      GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--push --load" \
	      GLOBAL_STACK_DOCKER_CLI_SERVICE="$$_target" \
	      docker-cli --silent --keep-going --warn-undefined-variables \
	      || printf '%s\n' "$$_target" >> "$$_failed_file"; \
	  else \
	    echo "Building $$_target (untagged, load only)..."; \
	    $(MAKE) \
	      GLOBAL_STACK_DOCKER_CLI="docker buildx" \
	      GLOBAL_STACK_DOCKER_CLI_EXEC="bake" \
	      GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--load" \
	      GLOBAL_STACK_DOCKER_CLI_SERVICE="$$_target" \
	      docker-cli --silent --keep-going --warn-undefined-variables \
	      || printf '%s\n' "$$_target" >> "$$_failed_file"; \
	  fi; \
	done; \
	if [ -s "$$_failed_file" ]; then \
	  echo ""; \
	  echo "=== BUILD FAILURES ==="; \
	  cat "$$_failed_file"; \
	  exit 1; \
	fi; \
	echo "=== Build complete ==="
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
	rm -rf tools/successes/*
	rm -rf tools/errors/*
	rm -rf tools/locks/*
	rm -rf tools/elapsed
down-n-rebuild: down build up-build
down-n-rebuild-force-recreate: down build up-build-force-recreate
rebuild: up-build
rebuild-force-recreate: up-build-force-recreate
# remove build from here (if you already built the stack)
down-n-up: down up

exec:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="exec" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables

restart:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="restart" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
health:
	@echo "=== Success tokens ===" && ls tools/successes/ 2>/dev/null || echo "(none)"
	@echo "=== Error tokens ===" && ls tools/errors/ 2>/dev/null || echo "(none)"
	@echo "=== Container status ===" && docker compose --env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}" 2>/dev/null || true
wait-healthy:
	@bash -c 'echo "Waiting for stack to settle..."; \
	while docker compose --env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} ps --format "{{.Health}}" 2>/dev/null | grep -q starting; do \
		printf "  %s healthy, %s failed — still starting...\n" "$$(ls tools/successes/ 2>/dev/null | wc -l | tr -d " ")" "$$(ls tools/errors/ 2>/dev/null | wc -l | tr -d " ")"; \
		sleep 10; \
	done; \
	printf "Stack settled: %s healthy, %s failed\n" "$$(ls tools/successes/ 2>/dev/null | wc -l | tr -d " ")" "$$(ls tools/errors/ 2>/dev/null | wc -l | tr -d " ")"'
	@if [ "$$(ls tools/errors/ 2>/dev/null | wc -l)" -gt 0 ]; then echo "Failed services:" && ls tools/errors/; exit 1; fi
save:
	source ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} && docker save $$(docker images --format '{{.Repository}}:{{.Tag}}') -o var/images/stack-${GLOBAL_STACK_VERSION}.tar
commit:
	@test -n "$(CONTAINER_NAME)" || (echo "Error: CONTAINER_NAME is required. Usage: make commit CONTAINER_NAME=<name> REPOSITORY_TAG=<repo:tag>"; exit 1)
	@test -n "$(REPOSITORY_TAG)" || (echo "Error: REPOSITORY_TAG is required. Usage: make commit CONTAINER_NAME=<name> REPOSITORY_TAG=<repo:tag>"; exit 1)
	source ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} && docker commit ${CONTAINER_NAME} ${REPOSITORY_TAG}
restore:
	source ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} && docker load -i var/images/stack-${GLOBAL_STACK_VERSION}.tar
log-follow:
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="logs --follow" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
hard-restart:
	@test -d var/tools || { echo "FATAL: var/tools/ is missing — cannot proceed with hard-restart. Restore it from a backup or run 'make save && make load' first."; exit 1; }
	$(MAKE) GLOBAL_STACK_DOCKER_CLI_EXEC="down" GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--rmi all --volumes --remove-orphans" GLOBAL_STACK_DOCKER_CLI="docker compose" GLOBAL_STACK_DOCKER_CLI_FLAGS="--env-file ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV}" docker-cli --silent --ignore-errors --keep-going --warn-undefined-variables
	docker system prune -a -f --volumes
	yes y | docker-reclaim-disk-space-script.sh || echo 'script does not exist'
	bin/env-scan.sh --yes
	yes y | global-unu.sh || echo 'script does not exit'
	sudo rm -rf tools ./docker/registry/data ./docker/registry/certs
	cp -R var/tools/ tools
	$(MAKE) create-paths --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) start-local-registry --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) create-buildx-builder --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) build --silent --ignore-errors --keep-going --warn-undefined-variables
	$(MAKE) up --silent --ignore-errors --keep-going --warn-undefined-variables
soft-restart:
	@test -d var/tools || { echo "FATAL: var/tools/ is missing — cannot proceed with soft-restart. Restore it from a backup or run 'make save && make load' first."; exit 1; }
	$(MAKE) down --silent --ignore-errors --keep-going --warn-undefined-variables
	sudo rm -rf tools
	cp -R var/tools/ tools
	$(MAKE) up --silent --ignore-errors --keep-going --warn-undefined-variables

-include local.Makefile
