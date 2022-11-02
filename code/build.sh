#!/bin/bash

set -ue -o pipefail

output=`mktemp`

handle_err() {
  echo > "${dir}index.html" "
  <html><body> 
  <p>Error building firmware.</p>
  <pre>$(cat "$output")</pre>
  </body></html> 
  "
  exit 1
}

trap handle_err ERR

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

make BUILD="${dir}build" MOVEMENT_CONFIG="${dir}movement_config.h" 2>&1 | tee "$output"
EM_CACHE=/emcache emmake make BUILD="${dir}build-sim" MOVEMENT_CONFIG="${dir}movement_config.h" | tee -a "$output"

echo > "${dir}index.html" "
<html><body> 
<h3><a href='build/watch.uf2'>Download</a></h3> 
<iframe width='800' height='1000' src='build-sim/watch.html'></iframe> 
</body></html> 
"

rm "$output"


