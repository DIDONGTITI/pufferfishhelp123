#!/bin/bash

OS=mac
ARCH="${1:-`uname -a | rev | cut -d' ' -f1 | rev`}"
if [ "$ARCH" == "arm64" ]; then
    ARCH=aarch64
fi
LIB_EXT=dylib
LIB=libHSsimplex-chat-*-inplace-ghc*.$LIB_EXT
GHC_LIBS_DIR=$(ghc --print-libdir)

BUILD_DIR=dist-newstyle/build/$ARCH-*/ghc-*/simplex-chat-*

rm -rf $BUILD_DIR
cabal build lib:simplex-chat lib:simplex-chat --ghc-options="-optl-Wl,-rpath,@loader_path -optl-Wl,-L$GHC_LIBS_DIR/rts -optl-lHSrts_thr-ghc8.10.7 -optl-lffi"

cd $BUILD_DIR/build
mkdir deps 2> /dev/null

# It's not included by default for some reason. Compiled lib tries to find system one but it's not always available
cp $GHC_LIBS_DIR/rts/libffi.dylib ./deps

DYLIBS=`otool -L $LIB | grep @rpath | tail -n +2 | cut -d' ' -f 1 | cut -d'/' -f2`
RPATHS=`otool -l $LIB | grep "path "| cut -d' ' -f11`

PROCESSED_LIBS=()

function copy_deps() {
    local LIB=$1
    if [[ "${PROCESSED_LIBS[*]}" =~ "$LIB" ]]; then
    	return 0
    fi

    PROCESSED_LIBS+=$LIB
	local DYLIBS=`otool -L $LIB | grep @rpath | tail -n +2 | cut -d' ' -f 1 | cut -d'/' -f2`
	local NON_FINAL_RPATHS=`otool -l $LIB | grep "path "| cut -d' ' -f11`
	local RPATHS=`otool -l $LIB | grep "path "| cut -d' ' -f11 | sed "s|@loader_path/..|$GHC_LIBS_DIR|"`

	cp $LIB ./deps
    if [[ "$NON_FINAL_RPATHS" == *"@loader_path/.."* ]]; then
		# Need to point the lib to @loader_path instead
		install_name_tool -add_rpath @loader_path ./deps/`basename $LIB`
	fi
	#echo LIB $LIB
	#echo DYLIBS ${DYLIBS[@]}
	#echo RPATHS ${RPATHS[@]}

	for DYLIB in $DYLIBS; do
	    for RPATH in $RPATHS; do
	        if [ -f "$RPATH/$DYLIB" ]; then
	            #echo DEP IS "$RPATH/$DYLIB"
	            if [ ! -f "deps/$DYLIB" ]; then
	            	cp "$RPATH/$DYLIB" ./deps
	            fi
	            copy_deps "$RPATH/$DYLIB"
	        fi
	    done
	done
}

copy_deps $LIB
rm deps/`basename $LIB`

cd -

rm -rf apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
rm -rf apps/multiplatform/common/src/commonMain/resources/libs/$OS-$ARCH/
rm -rf apps/multiplatform/desktop/build/cmake

mkdir -p apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp -r $BUILD_DIR/build/deps apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp $BUILD_DIR/build/deps/libHSsimplex-chat-*-inplace-ghc*.$LIB_EXT apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
