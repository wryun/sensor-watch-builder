#!/bin/bash

set -ue -o pipefail

export PATH=/bin:/usr/bin
dir=$1

cd /Sensor-Watch/movement/make

for build_dir in build build-sim; do
  mkdir -p "$dir$build_dir"
  for f in $build_dir/*.o; do
    ln -s "$(pwd)/$f" "$dir$f"
  done
  rm "$dir$build_dir/movement.o"
done

make BUILD="${dir}build" MOVEMENT_CONFIG="${dir}movement_config.h"
EM_CACHE=/emcache emmake make BUILD="${dir}build-sim" MOVEMENT_CONFIG="${dir}movement_config.h"
