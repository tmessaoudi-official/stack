log-ghost-blog:
	make GLOBAL_STACK_COMPOSE_CLI_EXEC="logs" GLOBAL_STACK_COMPOSE_CLI_SERVICE="ghost-blog" docker-compose  --ignore-errors --keep-going --warn-undefined-variables

login-ghost-blog:
	make GLOBAL_STACK_COMPOSE_CLI_EXEC="exec" GLOBAL_STACK_COMPOSE_CLI_SERVICE="ghost-blog" GLOBAL_STACK_COMPOSE_CLI_CONTAINER_COMMAND="bash" docker-compose  --ignore-errors --keep-going --warn-undefined-variables