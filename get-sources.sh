#!/bin/bash

source ./env-vars.sh

wget --input-file=wget-list --continue --directory-prefix=$SRCS
