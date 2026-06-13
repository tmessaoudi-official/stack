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

SERVICES_SHELL := \
	00base 00corentinth-it-tools \
	01axllent-mailpit 01caddy 01epiclabs-docker-oracle-xe-11g \
	01httpd 01localstack-localstack 01mariadb12 01mongo7 \
	01mysql9 01nginx \
	01selenium-standalone-chrome 01selenium-standalone-firefox \
	02fvm 02keycloak-keycloak \
	02mongoclient-mongoclient 02nvm 02phpbrew 02pyenv \
	02rbenv 02rust 02sdkman 02sonarqube \
	03flutter3 03java17-zulu 03java21-zulu 03java26-zulu \
	03node26 03node24 03nodeedge \
	03php8-4 03php8-5 03phpedge \
	03python3 03ruby3 03ruby4 \
	04android 04phpmyadmin 04serverless-framework \
	05edge 05stable

SERVICES_SH := 01postgres18 01redis 01valkey 02dpage-pgadmin4

SERVICES_ALL := $(SERVICES_SHELL) $(SERVICES_SH)

.PHONY: help mkdir-p touch create-paths generate-buildx docker-cli create-buildx-builder \
	start-local-registry build up up-build up-build-force-recreate down \
	down-n-rebuild down-n-rebuild-force-recreate rebuild rebuild-force-recreate \
	down-n-up exec restart health wait-healthy save commit restore log-follow hard-restart soft-restart \
	$(foreach s,$(SERVICES_SHELL),login-$(s)) \
	$(foreach s,$(SERVICES_SH),login-$(s)) \
	$(foreach s,$(SERVICES_ALL),log-$(s) log-follow-$(s) restart-$(s))

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

# Generate login/log/log-follow/restart targets from service lists
$(foreach s,$(SERVICES_SHELL),$(eval $(call login-service-shell,$(s))))
$(foreach s,$(SERVICES_SH),$(eval $(call login-service-sh,$(s))))
$(foreach s,$(SERVICES_ALL),$(eval $(call log-service,$(s))))
$(foreach s,$(SERVICES_ALL),$(eval $(call log-follow-service,$(s))))
$(foreach s,$(SERVICES_ALL),$(eval $(call restart-service,$(s))))

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
	@curl -fks https://$(GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS):$(GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000)/v2/ >/dev/null 2>&1 \
	  || { echo "FATAL: local registry not running — run 'make start-local-registry' first"; exit 1; }
	@_cert="docker/registry/certs/$(GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS).crt"; \
	  [ -f "$$_cert" ] && openssl x509 -noout -checkend 2592000 -in "$$_cert" 2>/dev/null \
	  || { [ -f "$$_cert" ] && echo "WARNING: local registry cert expires within 30 days — run 'make start-local-registry' to rotate"; }; true
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
