#!/bin/bash

set -ue -o pipefail

dir=$1
shift

color=$1
shift

cd /Sensor-Watch/movement/make

echo '---- movement_config.h'
cat "${dir}movement_config.h"

# Don't bothering making most of the .o files
for build_dir in "build-${color}" build-sim; do
  mkdir -p "$dir$build_dir"
  for f in $build_dir/*.o; do
    ln -s "$(pwd)/$f" "$dir$f"
  done
  # Except movement.o we'll need to regenerate.
  # I experimented with refactoring this out as well, such that changing movement_config.h
  # only affected a couple of functions, but it didn't actually save that much time and
  # required a much larger change to the repo (i.e. not one we want to carry in a patch).
  rm "$dir$build_dir/movement.o"
done

echo make BUILD="${dir}build-${color}" MOVEMENT_CONFIG="${dir}movement_config.h" "$@"
make BUILD="${dir}build-${color}" MOVEMENT_CONFIG="${dir}movement_config.h" "$@"
emmake make BUILD="${dir}build-sim" MOVEMENT_CONFIG="${dir}movement_config.h" "$@"
