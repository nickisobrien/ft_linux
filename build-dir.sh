#!/bin/bash

set -euo pipefail

source ./env-vars.sh

#logging
datetime=$(date -u +%F_%H%M)
log_dir=${LFS}/logs/build_${datetime}

if [ ! -d ${LFS}/logs ]; then
	mkdir -p ${LFS}/logs
fi
mkdir -p ${log_dir}
echo "Logging to ${log_dir}"

function onexit {
    if [ $? -ne 0 ]; then
        echo "FAIL!"
        echo "Check the logs in ${log_dir} for details"
    fi
}
trap onexit EXIT


#binutils
cd $SRCS
tar xf binutils-2.31.1.tar.xz
cd binutils-2.31.1 && mkdir build && cd build
echo "Configuring binutils!"
../configure --prefix=/tools --with-sysroot=$LFS --with-lib-path=/tools/lib --target=$LFS_TGT --disable-nls --disable-werror > ${log_dir}/binutils-config.log
echo "Building binutils!"
make > ${log_dir}/binutils-build.log
case $(uname -m) in
	  x86_64) mkdir -v /tools/lib && ln -sv lib /tools/lib64 ;;
esac
echo "Installing binutils!"
make install >> ${log_dir}/binutils-build.log


#gcc
echo "GCC:"
cd $SRCS
tar -xf gcc-8.2.0.tar.xz
cd gcc-8.2.0
tar -xf ../mpfr-4.0.1.tar.xz
mv -v mpfr-4.0.1 mpfr
tar -xf ../gmp-6.1.2.tar.xz
mv -v gmp-6.1.2 gmp
tar -xf ../mpc-1.1.0.tar.gz
mv -v mpc-1.1.0 mpc
for file in gcc/config/{linux,i386/linux{,64}}.h
do
  cp -uv $file{,.orig}
  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
      -e 's@/usr@/tools@g' $file.orig > $file
  echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
  touch $file.orig
done
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac
mkdir -v build
cd       build
echo "Configuring gcc!"
../configure                                       \
    --target=$LFS_TGT                              \
    --prefix=/tools                                \
    --with-glibc-version=2.11                      \
    --with-sysroot=$LFS                            \
    --with-newlib                                  \
    --without-headers                              \
    --with-local-prefix=/tools                     \
    --with-native-system-header-dir=/tools/include \
    --disable-nls                                  \
    --disable-shared                               \
    --disable-multilib                             \
    --disable-decimal-float                        \
    --disable-threads                              \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libmpx                               \
    --disable-libquadmath                          \
    --disable-libssp                               \
    --disable-libvtv                               \
    --disable-libstdcxx                            \
    --enable-languages=c,c++ > ${log_dir}/gcc-config.log
echo "Building gcc!"
make > ${log_dir}/gcc-build.log
echo "Installing gcc!"
make install >> ${log_dir}/gcc-build.log


# Kernel
echo "Kernel"
cd $SRCS
tar -xf linux-4.18.5.tar.xz
cd linux-4.18.5
echo "Making proper!"
make mrproper > ${log_dir}/kernel.log
make INSTALL_HDR_PATH=dest headers_install >> ${log_dir}/kernel.log
if [ ! -d /tools/include ]; then
	mkdir /tools/include
fi
echo "Copying from dest/include/* to /tools/include!"
cp -rv dest/include/* /tools/include


#Glibc
echo "Glibc"
cd $SRCS
tar -xf glibc-2.28.tar.xz
cd glibc-2.28/
mkdir build
cd build
echo "Configuring glibc!"
../configure                             \
      --prefix=/tools                    \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=3.2             \
      --with-headers=/tools/include      \
      libc_cv_forced_unwind=yes          \
      libc_cv_c_cleanup=yes				\
	> ${log_dir}/glibc-configure.log
echo "Building glibc!"
make -j1 > ${log_dir}/glibc-build.log # force single thread
echo "Installing glibc!"
make -j1 install >> ${log_dir}/glibc-build.log


#libstdc++
cd $SRCS/gcc-8.2.0
mkdir build-libstdc++
cd build-libstdc++/
echo "Configuring libstdc++!"
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --prefix=/tools                 \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-threads     \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/8.2.0 > ${log_dir}/libstdc++-configure.log
echo "Building libstdc++!"
make > ${log_dir}/libstdc++-build.log
echo "Installing libstdc++!"
make install >> ${log_dir}/libstdc++-build.log


#binutils pass2
cd $SRCS/binutils-2.31.1
mkdir build-pass2
cd build-pass2/
CC=$LFS_TGT-gcc                \
AR=$LFS_TGT-ar                 \
RANLIB=$LFS_TGT-ranlib         \
echo "Configuring binutils 2nd pass!"
../configure                   \
    --prefix=/tools            \
    --disable-nls              \
    --disable-werror           \
    --with-lib-path=/tools/lib \
    --with-sysroot > ${log_dir}/binutils2-config.log
echo "Building binutils 2nd pass!"
make > ${log_dir}/binutils2-build.log
echo "Installing binutils 2nd pass!"
make install >> ${log_dir}/binutils2-build.log
echo "Building binutils 2nd pass!"
make -C ld clean >> ${log_dir}/binutils2-build.log
echo "Building binutils 2nd pass!"
make -C ld LIB_PATH=/usr/lib:/lib >> ${log_dir}/binutils2-build.log
echo "Building binutils 2nd pass!"
cp -v ld/ld-new /tools/bin


#gcc pass2
cd $SRCS/gcc-8.2.0
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h

for file in gcc/config/{linux,i386/linux{,64}}.h
do
  cp -uv $file{,.orig}
  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
      -e 's@/usr@/tools@g' $file.orig > $file
  echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
  touch $file.orig
done
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
mkdir -v build2
cd       build2
echo “Configuring gcc 2!”
CC=$LFS_TGT-gcc                                    \
CXX=$LFS_TGT-g++                                   \
AR=$LFS_TGT-ar                                     \
RANLIB=$LFS_TGT-ranlib                             \
../configure                                       \
    --prefix=/tools                                \
    --with-local-prefix=/tools                     \
    --with-native-system-header-dir=/tools/include \
    --enable-languages=c,c++                       \
    --disable-libstdcxx-pch                        \
    --disable-multilib                             \
    --disable-bootstrap                            \
    --disable-libgomp ${log_dir}/gcc2-config.log
echo “Building gcc 2!”
make > ${log_dir}/gcc2-build.log
echo “Installing gcc 2!”
make install >> ${log_dir}/gcc2-build.log
ln -sv gcc /tools/bin/cc


Libstdc++

cd $SRCS/gcc-8.2.0
mkdir build-libstdc++
cd build-libstdc++/
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --prefix=/tools                 \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-threads     \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/8.2.0
make
make install

#Binutils2
cd $SRCS/binutils-2.31.1
mkdir build-pass2
cd build-pass2/
CC=$LFS_TGT-gcc                \
AR=$LFS_TGT-ar                 \
RANLIB=$LFS_TGT-ranlib         \
../configure                   \
    --prefix=/tools            \
    --disable-nls              \
    --disable-werror           \
    --with-lib-path=/tools/lib \
    --with-sysroot
make
make install
make -C ld clean
make -C ld LIB_PATH=/usr/lib:/lib
cp -v ld/ld-new /tools/bin


#gcc2
cd $SRCS/gcc-8.2.0
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h

for file in gcc/config/{linux,i386/linux{,64}}.h
do
  cp -uv $file{,.orig}
  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
      -e 's@/usr@/tools@g' $file.orig > $file
  echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
  touch $file.orig
done

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac

mkdir -v build2
cd       build2

echo “Configuring gcc 2!”
CC=$LFS_TGT-gcc                                    \
CXX=$LFS_TGT-g++                                   \
AR=$LFS_TGT-ar                                     \
RANLIB=$LFS_TGT-ranlib                             \
../configure                                       \
    --prefix=/tools                                \
    --with-local-prefix=/tools                     \
    --with-native-system-header-dir=/tools/include \
    --enable-languages=c,c++                       \
    --disable-libstdcxx-pch                        \
    --disable-multilib                             \
    --disable-bootstrap                            \
    --disable-libgomp ${log_dir}/gcc2-config.log
echo “Building gcc 2!”
make > ${log_dir}/gcc2-build.log
echo “Installing gcc 2!”
make install >> ${log_dir}/gcc2-build.log
ln -sv gcc /tools/bin/cc


#TCL
cd $SRCS
tar -xf tcl8.6.8-src.tar.gz
cd tcl8.6.8/unix
./configure --prefix=/tools
make
make install
chmod -v u+w /tools/lib/libtcl8.6.so
make install-private-headers
ln -sv tclsh8.6 /tools/bin/tclsh

 #Expect
cd $SRCS
tar -xf expect5.45.4.tar.gz
cd expect5.45.4
cp -v configure{,.orig}
sed 's:/usr/local/bin:/bin:' configure.orig > configure
./configure --prefix=/tools       \
            --with-tcl=/tools/lib \
            --with-tclinclude=/tools/include
make
make SCRIPTS="" install



#DejaGNU
cd $SRCS
tar -xf dejagnu-1.6.1.tar.gz
cd dejagnu-1.6.1/
./configure --prefix=/tools
make install



#M4
cd $SRCS
tar -xf m4-1.4.18.tar.xz
cd m4-1.4.18
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
./configure --prefix=/tools
make
make check
make install


#NCurses
cd $SRCS
tar -xf ncurses-6.1.tar.gz
cd ncurses-6.1/
sed -i s/mawk// configure
./configure --prefix=/tools \
            --with-shared   \
            --without-debug \
            --without-ada   \
            --enable-widec  \
            --enable-overwrite
make
make install

#Bash
cd $SRCS
tar -xf bash-4.4.18.tar.gz
cd bash-4.4.18
./configure --prefix=/tools --without-bash-malloc
make
make install
ln -sv bash /tools/bin/sh


#Bison
cd $SRCS
tar -xf bison-3.0.5.tar.xz
cd bison-3.0.5
./configure --prefix=/tools
make
make install


#Bzip2
cd $SRCS
tar -xf bzip2-1.0.6.tar.gz
cd bzip2-1.0.6
make
make PREFIX=/tools install


#Coreutils
cd $SRCS
tar -xf coreutils-8.30.tar.xz
cd coreutils-8.30
export FORCE_UNSAFE_CONFIGURE=1 # if root user
./configure --prefix=/tools --enable-install-program=hostname
make
make install


#Diffutils
cd $SRCS
tar -xf diffutils-3.6.tar.xz
cd diffutils-3.6
./configure --prefix=/tools
make
make install


#file
cd $SRCS
tar -xf file-5.34.tar.gz
cd file-5.34
./configure --prefix=/tools
make
make install


#findutils
cd $SRCS
tar -xf findutils-4.6.0.tar.gz
cd findutils-4.6.0
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' gl/lib/*.c
sed -i '/unistd/a #include <sys/sysmacros.h>' gl/lib/mountlist.c
echo "#define _IO_IN_BACKUP 0x100" >> gl/lib/stdio-impl.h
./configure --prefix=/tools
make
make install


#Gawk
cd $SRCS
tar -xf gawk-4.2.1.tar.xz
cd gawk-4.2.1
./configure --prefix=/tools
make
make install


#Gettext
cd $SRCS
tar -xf gettext-0.19.8.1.tar.xz
cd gettext-0.19.8.1
cd gettext-tools
EMACS="no" ./configure --prefix=/tools --disable-shared
make -C gnulib-lib
make -C intl pluralx.c
make -C src msgfmt
make -C src msgmerge
make -C src xgettext
cp -v src/{msgfmt,msgmerge,xgettext} /tools/bin


#Grep
cd $SRCS
tar -xf grep-3.1.tar.xz
cd grep-3.1
./configure --prefix=/tools
make
make install


#Gzip
cd $SRCS
tar -xf gzip-1.9.tar.xz
cd gzip-1.9
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
./configure --prefix=/tools
make
make install


#Make
cd $SRCS
tar -xf make-4.2.1.tar.bz2
cd make-4.2.1
sed -i '211,217 d; 219,229 d; 232 d' glob/glob.c
./configure --prefix=/tools --without-guile
make
make install


#Patch
cd $SRCS
tar -xf patch-2.7.6.tar.xz
cd patch-2.7.6
./configure --prefix=/tools
make
make install


#Perl
cd $SRCS
tar -xf perl-5.28.0.tar.xz
cd perl-5.28.0
sh Configure -des -Dprefix=/tools -Dlibs=-lm -Uloclibpth -Ulocincpth
make
cp -v perl cpan/podlators/scripts/pod2man /tools/bin
mkdir -pv /tools/lib/perl5/5.28.0
cp -Rv lib/* /tools/lib/perl5/5.28.0


#Sed
cd $SRCS
tar -xf sed-4.5.tar.xz
cd sed-4.5
./configure --prefix=/tools
make
make install


#Tar
cd $SRCS
tar -xf tar-1.30.tar.xz
cd tar-1.30
./configure --prefix=/tools
make
make install


#Texinfo
cd $SRCS
tar -xf texinfo-6.5.tar.xz
cd texinfo-6.5
./configure --prefix=/tools
make
make install


#Util Linux
cd $SRCS
tar -xf util-linux-2.32.1.tar.xz
cd util-linux-2.32.1
./configure --prefix=/tools                \
            --without-python               \
            --disable-makeinstall-chown    \
            --without-systemdsystemunitdir \
            --without-ncurses              \
            PKG_CONFIG=""
make
make install


#Xz
cd $SRCS
tar -xf xz-5.2.4.tar.xz
cd xz-5.2.4
./configure --prefix=/tools
make
make install

