#!/bin/bash

for dependency in $@; do
  echo -e "Checking ${dependency}"
  global_stack_base_show_waiting=""

  while [ ! -f "${dependency}" ]
  do
    sleep 1
  done

  echo " yes"
done