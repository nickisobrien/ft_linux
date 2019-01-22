#!/bin/bash

source ./env-vars.sh

if [ ! -d "$LFS" ]; then
	mkdir -v $LFS
fi

if [ ! -d "$SRCS" ]; then
	mkdir -v $SRCS
	echo "Getting sources..."
	./get-sources.sh
fi

if [ ! -d "$TOOLS" ]; then
	mkdir -v $TOOLS
fi

if [ ! -L "/tools" ]; then
	echo "Missing tools symlink in home directory"
	while true; do
    read -p "Do you wish to use our tools? [y,n,?] " yn
    case $yn in
        [Yy]* ) sudo ln -sv $TOOLS /; break;;
        [Nn]* ) exit;;
        * ) echo "To do so, you need to create a symlink in your home directory pointing to our tools, would you like to? "
		echo "sudo ln -sv $TOOLS /";;
    esac
done

fi
