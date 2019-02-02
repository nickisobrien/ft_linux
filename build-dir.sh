#!/bin/bash

set -euo pipefail

source ./common.sh

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
echo "Binutils!"
cd $SRCS
tar xf binutils-2.31.1.tar.xz
cd binutils-2.31.1 && mkdir build && cd build
../configure --prefix=/tools --with-sysroot=$LFS --with-lib-path=/tools/lib --target=$LFS_TGT --disable-nls --disable-werror > ${log_dir}/binutils-config.log
make > ${log_dir}/binutils-build.log
case $(uname -m) in
    x86_64) mkdir -v /tools/lib && ln -sv lib /tools/lib64 ;;
esac
make install >> ${log_dir}/binutils-build.log


#gcc
echo "GCC!"
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
    --enable-languages=c,c++ > ${log_dir}/gcc-config.log2>&1
make > ${log_dir}/gcc-build.log 2>&1
make install >> ${log_dir}/gcc-build.log 2>&1


# linux
echo "Linux!"
cd $SRCS
tar -xf linux-4.18.5.tar.xz
cd linux-4.18.5
make mrproper > ${log_dir}/linux-build.log 2>&1
make INSTALL_HDR_PATH=dest headers_install >> ${log_dir}/linux-build.log 2>&1
if [ ! -d /tools/include ]; then
  mkdir /tools/include
fi
cp -rv dest/include/* /tools/include


#Glibc
echo "Glibc!"
cd $SRCS
tar -xf glibc-2.28.tar.xz
cd glibc-2.28/
mkdir build
cd build
../configure                             \
      --prefix=/tools                    \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=3.2             \
      --with-headers=/tools/include      \
      libc_cv_forced_unwind=yes          \
      libc_cv_c_cleanup=yes       \
  > ${log_dir}/glibc-configure.log 2>&1
make -j1 > ${log_dir}/glibc-build.log 2>&1 # force single thread
make -j1 install >> ${log_dir}/glibc-build.log 2>&1


#libstdc++
echo "Libstdc++!"
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
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/8.2.0 > ${log_dir}/libstdc++-configure.log 2>&1
make > ${log_dir}/libstdc++-build.log 2>&1
make install >> ${log_dir}/libstdc++-build.log 2>&1


#binutils pass2
echo "Binutils pass 2!"
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
    --with-sysroot > ${log_dir}/binutils2-config.log 2>&1
make > ${log_dir}/binutils2-build.log 2>&1
make install >> ${log_dir}/binutils2-build.log 2>&1
make -C ld clean >> ${log_dir}/binutils2-build.log 2>&1
make -C ld LIB_PATH=/usr/lib:/lib >> ${log_dir}/binutils2-build.log 2>&1
cp -v ld/ld-new /tools/bin


#gcc pass2
echo "Gcc pass 2!"
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
    --disable-libgomp > ${log_dir}/gcc2-config.log 2>&1
make > ${log_dir}/gcc2-build.log 2>&1
make install >> ${log_dir}/gcc2-build.log 2>&1
ln -sv gcc /tools/bin/cc


#TCL
echo "TCL!"
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
echo "Expect!"
cd $SRCS
tar -xf expect5.45.4.tar.gz
cd expect5.45.4
cp -v configure{,.orig}
sed 's:/usr/local/bin:/bin:' configure.orig > configure
./configure --prefix=/tools       \
            --with-tcl=/tools/lib \
            --with-tclinclude=/tools/include > ${log_dir}/expect-config.log 2>&1
make > ${log_dir}/expect-build.log 2>&1
make SCRIPTS="" install >> ${log_dir}/expect-build.log 2>&1


#DejaGNU
echo "DejaGNU!"
cd $SRCS
tar -xf dejagnu-1.6.1.tar.gz
cd dejagnu-1.6.1/
./configure --prefix=/tools > ${log_dir}/dejagnu-config.log 2>&1
make install > ${log_dir}/dejagnu-build.log 2>&1


#M4
echo "M4!"
cd $SRCS
tar -xf m4-1.4.18.tar.xz
cd m4-1.4.18
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
./configure --prefix=/tools > ${log_dir}/m4-config.log 2>&1
make > ${log_dir}/m4-build.log 2>&1
make check >> ${log_dir}/m4-build.log 2>&1
make install >> ${log_dir}/m4-build.log 2>&1


#NCurses
echo "Ncurses!"
cd $SRCS
tar -xf ncurses-6.1.tar.gz
cd ncurses-6.1/
sed -i s/mawk// configure
./configure --prefix=/tools \
            --with-shared   \
            --without-debug \
            --without-ada   \
            --enable-widec  \
            --enable-overwrite > ${log_dir}/ncurses-config.log 2>&1
make > ${log_dir}/ncurses-build.log 2>&1
make install >> ${log_dir}/ncurses-build.log 2>&1

#Bash
echo "Bash!"
cd $SRCS
tar -xf bash-4.4.18.tar.gz
cd bash-4.4.18
./configure --prefix=/tools --without-bash-malloc > ${log_dir}/bash-config.log 2>&1
make > ${log_dir}/bash-build.log 2>&1
make install >> ${log_dir}/bash-build.log 2>&1
ln -sv bash /tools/bin/sh


#Bison
echo "Bison!"
cd $SRCS
tar -xf bison-3.0.5.tar.xz
cd bison-3.0.5
./configure --prefix=/tools > ${log_dir}/bison-config.log 2>&1
make > ${log_dir}/bison-build.log 2>&1
make install >> ${log_dir}/bison-build.log 2>&1


#Bzip2
echo "Bzip2!"
cd $SRCS
tar -xf bzip2-1.0.6.tar.gz
cd bzip2-1.0.6
make > ${log_dir}/bzip2-build.log 2>&1
make PREFIX=/tools install >> ${log_dir}/bzip2-build.log 2>&1


#Coreutils
echo "Coreutils!"
cd $SRCS
tar -xf coreutils-8.30.tar.xz
cd coreutils-8.30
export FORCE_UNSAFE_CONFIGURE=1 # if root user
./configure --prefix=/tools --enable-install-program=hostname > ${log_dir}/coreutils-config.log 2>&1
make > ${log_dir}/coreutils-build.log 2>&1
make install >> ${log_dir}/coreutils-build.log 2>&1


#Diffutils
echo "Diffutils!"
cd $SRCS
tar -xf diffutils-3.6.tar.xz
cd diffutils-3.6
./configure --prefix=/tools > ${log_dir}/diffutils-config.log 2>&1
make > ${log_dir}/diffutils-build.log 2>&1
make install >> ${log_dir}/diffutils-build.log 2>&1


#file
echo "File!"
cd $SRCS
tar -xf file-5.34.tar.gz
cd file-5.34
./configure --prefix=/tools > ${log_dir}/file-config.log 2>&1
make > ${log_dir}/file-build.log 2>&1
make install >> ${log_dir}/file-build.log 2>&1


#findutils
echo "Findutils!"
cd $SRCS
tar -xf findutils-4.6.0.tar.gz
cd findutils-4.6.0
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' gl/lib/*.c
sed -i '/unistd/a #include <sys/sysmacros.h>' gl/lib/mountlist.c
echo "#define _IO_IN_BACKUP 0x100" >> gl/lib/stdio-impl.h
./configure --prefix=/tools > ${log_dir}/findutils-config.log 2>&1
make > ${log_dir}/findutils-build.log 2>&1
make install >> ${log_dir}/findutils-build.log 2>&1


#Gawk
echo "Gawk!"
cd $SRCS
tar -xf gawk-4.2.1.tar.xz
cd gawk-4.2.1
./configure --prefix=/tools > ${log_dir}/gawk-config.log 2>&1
make > ${log_dir}/gawk-build.log 2>&1
make install >> ${log_dir}/gawk-build.log 2>&1

#Gettext
echo "Gettext!"
cd $SRCS
tar -xf gettext-0.19.8.1.tar.xz
cd gettext-0.19.8.1
cd gettext-tools
EMACS="no" ./configure --prefix=/tools --disable-shared > ${log_dir}/gettext-config.log 2>&1
make -C gnulib-lib > ${log_dir}/gettext-build.log 2>&1
make -C intl pluralx.c >> ${log_dir}/gettext-build.log 2>&1
make -C src msgfmt >> ${log_dir}/gettext-build.log 2>&1
make -C src msgmerge >> ${log_dir}/gettext-build.log 2>&1
make -C src xgettext >> ${log_dir}/gettext-build.log 2>&1
cp -v src/{msgfmt,msgmerge,xgettext} /tools/bin


#Grep
echo "Grep!"
cd $SRCS
tar -xf grep-3.1.tar.xz
cd grep-3.1
./configure --prefix=/tools > ${log_dir}/grep-config.log 2>&1
make > ${log_dir}/grep-build.log 2>&1
make install >> ${log_dir}/grep-build.log 2>&1


#Gzip
echo "Gzip!"
cd $SRCS
tar -xf gzip-1.9.tar.xz
cd gzip-1.9
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
./configure --prefix=/tools > ${log_dir}/gzip-config.log 2>&1
make > ${log_dir}/gzip-build.log 2>&1
make install >> ${log_dir}/gzip-build.log 2>&1


#Make
echo "Make!"
cd $SRCS
tar -xf make-4.2.1.tar.bz2
cd make-4.2.1
sed -i '211,217 d; 219,229 d; 232 d' glob/glob.c
./configure --prefix=/tools --without-guile > ${log_dir}/make-config.log 2>&1
make > ${log_dir}/make-build.log 2>&1
make install >> ${log_dir}/make-build.log 2>&1


#Patch
echo "Patch!"
cd $SRCS
tar -xf patch-2.7.6.tar.xz
cd patch-2.7.6
./configure --prefix=/tools > ${log_dir}/patch-config.log 2>&1
make > ${log_dir}/patch-build.log 2>&1
make install >> ${log_dir}/patch-build.log 2>&1


#Perl
echo "Perl!"
cd $SRCS
tar -xf perl-5.28.0.tar.xz
cd perl-5.28.0
sh Configure -des -Dprefix=/tools -Dlibs=-lm -Uloclibpth -Ulocincpth > ${log_dir}/perl-config.log 2>&1
make > ${log_dir}/perl-build.log 2>&1
cp -v perl cpan/podlators/scripts/pod2man /tools/bin
mkdir -pv /tools/lib/perl5/5.28.0
cp -Rv lib/* /tools/lib/perl5/5.28.0


#Sed
echo "Sed!"
cd $SRCS
tar -xf sed-4.5.tar.xz
cd sed-4.5
./configure --prefix=/tools > ${log_dir}/sed-config.log 2>&1
make > ${log_dir}/sed-build.log 2>&1
make install >> ${log_dir}/sed-build.log 2>&1


#Tar
echo "Tar!"
cd $SRCS
tar -xf tar-1.30.tar.xz
cd tar-1.30
./configure --prefix=/tools > ${log_dir}/tar-config.log 2>&1
make > ${log_dir}/tar-build.log 2>&1
make install >> ${log_dir}/tar-build.log 2>&1


#Texinfo
echo "Texinfo!"
cd $SRCS
tar -xf texinfo-6.5.tar.xz
cd texinfo-6.5
./configure --prefix=/tools > ${log_dir}/texinfo-config.log 2>&1
make > ${log_dir}/texinfo-build.log 2>&1
make install >> ${log_dir}/texinfo-build.log 2>&1


#Util Linux
echo "Util linux!"
cd $SRCS
tar -xf util-linux-2.32.1.tar.xz
cd util-linux-2.32.1
./configure --prefix=/tools                \
            --without-python               \
            --disable-makeinstall-chown    \
            --without-systemdsystemunitdir \
            --without-ncurses              \
            PKG_CONFIG="" > ${log_dir}/util-linux-config.log 2>&1
make > ${log_dir}/util-linux-build.log 2>&1
make install >> ${log_dir}/util-linux-build.log 2>&1


#Xz
echo "Xz!"
cd $SRCS
tar -xf xz-5.2.4.tar.xz
cd xz-5.2.4
./configure --prefix=/tools > ${log_dir}/xz-config.log 2>&1
make > ${log_dir}/xz-build.log 2>&1
make install >> ${log_dir}/xz-build.log 2>&1
