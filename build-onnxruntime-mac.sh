#!/bin/bash
# build onnxruntime by benjaminwan
# CMakeFiles/onnxruntime.dir/link.txt/link/lib*.a

function is_cmd_exist() {
    retval=""
    if ! command -v $1 >/dev/null 2>&1; then
        retval="false"
    else
        retval="true"
    fi
    echo "$retval"
}

function collect_shared_lib(){
    if [ -d "install/bin" ]; then
        rm -r -f install/bin
    fi

    if [ -d "install/include/onnxruntime/core/session" ]; then
        mv install/include/onnxruntime/core/session/* install/include
        rm -rf install/include/onnxruntime
    fi

    echo "set(OnnxRuntime_INCLUDE_DIRS \"\${CMAKE_CURRENT_LIST_DIR}/include\")" > install/OnnxRuntimeConfig.cmake
    echo "include_directories(\${OnnxRuntime_INCLUDE_DIRS})" >> install/OnnxRuntimeConfig.cmake
    echo "link_directories(\${CMAKE_CURRENT_LIST_DIR}/lib)" >> install/OnnxRuntimeConfig.cmake
    echo "set(OnnxRuntime_LIBS onnxruntime)" >> install/OnnxRuntimeConfig.cmake
}

function copy_libs(){
    all_link=$(cat CMakeFiles/onnxruntime.dir/link.txt)
    link=${all_link#*onnxruntime.dir}
    regex="lib.*.a$"
    libs=""
    for var in $link; do
        if [[ ${var} =~ ${regex} ]]; then
            #echo cp ${var} install-static/lib
            cp ${var} install-static/lib
            name=$(echo $var | grep -E ${regex} -o)
            name=${name#lib}
            name=${name%.a}
            libs="${libs} ${name}"
        fi
    done
    echo "$libs"
}

function combine_libs_darwin(){
    all_link=$(cat CMakeFiles/onnxruntime.dir/link.txt)
    link=${all_link#*onnxruntime.dir}
    regex="lib.*.a$"
    root_path="${PWD}"
    lib_path="${PWD}/install-static/lib"
    mkdir -p $lib_path
    libs=""
    for var in $link; do
        if [[ ${var} =~ ${regex} ]]; then
            libs="${libs} ${root_path}/${var}"
        fi
    done
    libtool -static -o ${lib_path}/libonnxruntime.a ${libs}
}

function collect_static_libs() {
    if [ -d "install-static" ]; then
        rm -r -f install-static
    fi
    mkdir -p install-static/lib

    if [ -d "install/include" ]; then
        cp -r install/include install-static
    fi

    if [ ! -f "CMakeFiles/onnxruntime.dir/link.txt" ]; then
        echo "link.txt is not exist, collect static libs error."
        exit 0
    fi

    libtool_exist=$( is_cmd_exist libtool )
    if [ "$libtool_exist" == "true" ]; then
        echo "combine_libs_darwin"
        combine_libs_darwin
        libs="onnxruntime"
    else
      echo "copy_libs"
      libs=$( copy_libs )
    fi

    echo "set(OnnxRuntime_INCLUDE_DIRS \"\${CMAKE_CURRENT_LIST_DIR}/include\")" > install-static/OnnxRuntimeConfig.cmake
    echo "include_directories(\${OnnxRuntime_INCLUDE_DIRS})" >> install-static/OnnxRuntimeConfig.cmake
    echo "link_directories(\${CMAKE_CURRENT_LIST_DIR}/lib)" >> install-static/OnnxRuntimeConfig.cmake
    echo "set(OnnxRuntime_LIBS $libs)" >> install-static/OnnxRuntimeConfig.cmake

    cp CMakeFiles/onnxruntime.dir/link.txt install-static/link.log
}

HOST_OS=$(uname -s)
NUM_THREADS=1
BUILD_TYPE=Release

if [ $HOST_OS == "Darwin" ]; then
  NUM_THREADS=$(sysctl -n hw.ncpu)
else
  echo "Unsupport OS: $HOST_OS"
  exit 0
fi

while getopts "a:" arg
do
    case $arg in
        a)
            echo "a's arg:$OPTARG" #参数存在$OPTARG中
		TARGET_ARCH=$OPTARG
            ;;
        ?)  #当有不认识的选项的时候arg为?
            echo -e "unkonw argument. \nuseage1: ./build-onnxruntim-mac.bat -a x86_64 \nuseage2: ./build-onnxruntim-mac.bat -a arm64"
            exit 1
        ;;
    esac
done

if [ "$TARGET_ARCH" != "x86_64" ] && [ "$TARGET_ARCH" != "arm64" ]; then
    echo "Unsupported TARGET_ARCH:$TARGET_ARCH"
    exit 0
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
python3 $DIR/tools/ci_build/build.py --build_dir $DIR/build-$HOST_OS-$TARGET_ARCH \
    --config $BUILD_TYPE \
    --parallel \
    --skip_tests \
    --build_shared_lib \
    --build_java \
    --osx_arch $TARGET_ARCH \
    --apple_deploy_target "10.9" \
    --cmake_extra_defines CMAKE_INSTALL_PREFIX=./install \
    onnxruntime_BUILD_UNIT_TESTS=OFF onnxruntime_RUN_ONNX_TESTS=OFF \
    onnxruntime_BUILD_WINML_TESTS=OFF onnxruntime_USE_OPENMP=OFF onnxruntime_DEV_MODE=OFF \
    CMAKE_OSX_DEPLOYMENT_TARGET="10.9"

if [ ! -d "build-$HOST_OS-$TARGET_ARCH/$BUILD_TYPE" ]; then
  echo "Build error!"
  exit 0
fi

pushd build-$HOST_OS-$TARGET_ARCH/$BUILD_TYPE
cmake --install .
if [ ! -d "install" ]; then
  echo "Cmake install  error!"
  exit 0
fi
collect_shared_lib
collect_static_libs
popd
