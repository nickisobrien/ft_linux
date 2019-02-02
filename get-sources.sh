#!/bin/bash

source ./common.sh

wget --input-file=wget-list --continue --directory-prefix=$SRCS
