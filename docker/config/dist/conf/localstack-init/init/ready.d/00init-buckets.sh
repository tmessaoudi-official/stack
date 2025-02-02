#!/bin/bash

awslocal s3 mb s3://local-bucket
awslocal s3api put-bucket-cors --bucket local-bucket --cors-configuration file://${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/localstack-conf/cors.json