#!/bin/bash

yum install bash binutils bison bzip2 coreutils diffutils expect findutils gawk gcc git grep m4 make patch perl sed tar texinfo vim gcc-multilib
yum groupinstall 'Development Tools'
yum update
