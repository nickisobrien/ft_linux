#!/bin/bash

export LFS=${PWD}/lfs # this should actually be set to where the linux fs (ext4) is mounted
export SRCS=${LFS}/sources
export TOOLS=${LFS}/tools
export PATH=/tools/bin:/usr/local/bin:/bin:/usr/bin
