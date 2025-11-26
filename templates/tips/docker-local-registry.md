Edit /etc/docker/daemon.json and add the following:

replace GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000 with the port you have chosen in .env.local
replace GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS with the virtualhost you have chosen in .env.local
{
  "insecure-registries": ["localhost:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}", "${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}"]
}

Add this line to /etc/hosts:

replace GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS with the value from .env.local you have chosen
127.0.0.1 GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS

replace GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS with the value from .env.local you have chosen
replace GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000 with the port you have chosen in .env.local
replace GLOBAL_STACK_DOCKER_ROOT_PATH with the path from .env.local you have chosen
create a file in docker/registry/config.json
{
  "mirrors": {
    "${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}": {
      "endpoint": ["https://${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}"]
    }
  },
  "configs": {
    "${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}": {
      "tls": {
        "ca": "/etc/ssl/certs/${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}.crt"
      }
    }
  }
}