#!/bin/sh
set -x
echo " — — — — — — — — — — Building Dependencies Script Started — — — — — — — — — — "

MIN_IOS="10.0"
MIN_WATCHOS="2.0"
MIN_TVOS=$MIN_IOS
MIN_MACOS="10.10"
IPHONEOS=iphoneos
IPHONESIMULATOR=iphonesimulator
WATCHOS=watchos
WATCHSIMULATOR=watchsimulator
TVOS=appletvos
TVSIMULATOR=appletvsimulator
MACOS=macosx
LOGICALCPU_MAX=`sysctl -n hw.logicalcpu_max`
GMP_DIR="`pwd`/gmp"
NTL_VERSION="11.4.3"
GMP_VERSION="6.2.0"

change_submodules() 
{
    git submodule update --init --recursive
}

check_cmake() 
{
    install_cmake()
    {
        echo "installing cmake"
        curl -OL https://github.com/Kitware/CMake/releases/download/v3.17.1/cmake-3.17.1-Darwin-x86_64.tar.gz
        tar -xzf cmake-3.17.1-Darwin-x86_64.tar.gz
        sudo mv cmake-3.17.1-Darwin-x86_64/CMake.app /Applications
        sudo /Applications/CMake.app/Contents/bin/cmake-gui --install

    }

    if hash cmake 2>/dev/null; then
        echo "CMAKE is present on this system so skipping install."
    else
        #we have to install cmake
        echo "no CMAKE Found.  Installing now..."
        install_cmake
    fi
}

version_min_flag()
{
    PLATFORM=$1
    FLAG=""
    if [[ $PLATFORM = $IPHONEOS ]]; then
        FLAG="-miphoneos-version-min=${MIN_IOS}"
    elif [[ $PLATFORM = $IPHONESIMULATOR ]]; then
        FLAG="-mios-simulator-version-min=${MIN_IOS}"
    elif [[ $PLATFORM = $WATCHOS ]]; then
        FLAG="-mwatchos-version-min=${MIN_WATCHOS}"
    elif [[ $PLATFORM = $WATCHSIMULATOR ]]; then
        FLAG="-mwatchos-simulator-version-min=${MIN_WATCHOS}"
    elif [[ $PLATFORM = $TVOS ]]; then
        FLAG="-mtvos-version-min=${MIN_TVOS}"
    elif [[ $PLATFORM = $TVSIMULATOR ]]; then
        FLAG="-mtvos-simulator-version-min=${MIN_TVOS}"
    elif [[ $PLATFORM = $MACOS ]]; then
        FLAG="-mmacosx-version-min=${MIN_MACOS}"
    fi
    echo $FLAG
}
prepare()
{
    download_gmp()
    {
        CURRENT_DIR=`pwd`
        if [ ! -s ${CURRENT_DIR}/gmp-${GMP_VERSION}.tar.bz2 ]; then
            curl -L -o ${CURRENT_DIR}/gmp-${GMP_VERSION}.tar.bz2 https://gmplib.org/download/gmp/gmp-${GMP_VERSION}.tar.bz2
        fi
        rm -rf gmp
        tar xfj "gmp-${GMP_VERSION}.tar.bz2"
        mv gmp-${GMP_VERSION} gmp
        cd gmp
    }
    download_ntl()
    {
        CURRENT_DIR=`pwd`
        if [ ! -s ${CURRENT_DIR}/ntl-${NTL_VERSION}.tar.gz ]; then
            curl -L -o ${CURRENT_DIR}/ntl-${NTL_VERSION}.tar https://www.shoup.net/ntl/ntl-${NTL_VERSION}.tar.gz
        fi
        tar xvf "ntl-${NTL_VERSION}.tar"
    }
    download_ntl
    download_gmp
}

build_gmp()
{
   
    PLATFORM=$1
    ARCH=$2
    SDK=`xcrun --sdk $PLATFORM --show-sdk-path`
    PLATFORM_PATH=`xcrun --sdk $PLATFORM --show-sdk-platform-path`
    CLANG=`xcrun --sdk $PLATFORM --find clang`
    CURRENT_DIR=`pwd`
    DEVELOPER=`xcode-select --print-path`
    export PATH="${PLATFORM_PATH}/Developer/usr/bin:${DEVELOPER}/usr/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    mkdir "${CURRENT_DIR}/../gmplib-so-${PLATFORM}-${ARCH}"
    CFLAGS="-arch ${ARCH} --sysroot=${SDK}"
    EXTRA_FLAGS="$(version_min_flag $PLATFORM)"
    CCARGS="${CLANG} ${CFLAGS}"
    CPPFLAGSARGS="${CFLAGS} ${EXTRA_FLAGS}"
    #CONFIGURESCRIPT="gmp_configure_script.sh"
    #cat >"$CONFIGURESCRIPT" << EOF

    ./configure CC="$CCARGS" CPPFLAGS="$CPPFLAGSARGS" --host=${ARCH}-apple-darwin --disable-assembly --prefix="${CURRENT_DIR}/../gmplib-so-${PLATFORM}-${ARCH}"

    make -j $LOGICALCPU_MAX &> "${CURRENT_DIR}/gmplib-so-${PLATFORM}-${ARCH}-build.log"
    make install &> "${CURRENT_DIR}/gmplib-so-${PLATFORM}-${ARCH}-install.log"
    rm "${CURRENT_DIR}/../gmplib-so-${PLATFORM}-${ARCH}/lib/libgmp.10.dylib"
    rm "${CURRENT_DIR}/../gmp-${GMP_VERSION}.tar.bz2"
    cd ../
}

build_ntl()
{
    PLATFORM=$1
    ARCH=$2
    CURRENT_DIR=`pwd`
    SDK=`xcrun --sdk $PLATFORM --show-sdk-path`
    
    mkdir ntl
    mkdir ntl/libs
    cd ntl-${NTL_VERSION}
    cd src

    ./configure CXX=clang++ CXXFLAGS="-stdlib=libc++  -arch ${ARCH} -isysroot ${SDK}"  NTL_THREADS=on NATIVE=on TUNE=x86 NTL_GMP_LIP=on PREFIX="${CURRENT_DIR}/ntl" GMP_PREFIX="${CURRENT_DIR}/gmplib-so-${PLATFORM}-${ARCH}"
    make -j
    
    cp -R "${CURRENT_DIR}/ntl-${NTL_VERSION}/include" "${CURRENT_DIR}/ntl/include" 
    cp "${CURRENT_DIR}/ntl-${NTL_VERSION}/src/ntl.a" "${CURRENT_DIR}/ntl/libs/ntl.a"
    rm "${CURRENT_DIR}/ntl-${NTL_VERSION}.tar"
    cd ../../
}

build_helib() 
{
    PLATFORM=$1
    ARCH=$2
    CURRENT_DIR=`pwd`
    DEPEND_DIR="${CURRENT_DIR}"
    cp "${CURRENT_DIR}/Helib_install/CMakeLists.txt" "${CURRENT_DIR}/HElib"
    cd "${CURRENT_DIR}/HElib"
    cmake -S. -B../HElib_macOS -GXcode \
    -DCMAKE_SYSTEM_NAME=Darwin \
    "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.10 \
    -DCMAKE_INSTALL_PREFIX=`pwd`/_install \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -DCMAKE_IOS_INSTALL_COMBINED=YES \
    -DGMP_DIR="${DEPEND_DIR}/gmp" \
    -DGMP_HEADERS="${DEPEND_DIR}/gmp/include" \
    -DGMP_LIB="${DEPEND_DIR}/gmp/lib/libgmp.a" \
    -DNTL_INCLUDE_PATHS="${DEPEND_DIR}/ntl/include" \
        -DNTL_LIB="${DEPEND_DIR}/ntl/lib/ntl.a" \
        -DNTL_DIR="${DEPEND_DIR}/ntl/include"
}

build_all()
{
    SUFFIX=$1
    BUILD_IN=$2
    
    build_gmp "${MACOS}" "x86_64"
    build_ntl "${MACOS}" "x86_64"
    build_helib "${MACOS}" "x86_64"
}

change_submodules
check_cmake
prepare
build_all "ios" "${MACOS};|x86_64"
echo " — — — — — — — — — — Building Dependencies Script Ended — — — — — — — — — — "

