#!/bin/bash

set -ue -o pipefail

export PATH=/bin:/usr/bin
output=`mktemp`

dir=$1

handle_cleanup() {
    rm -f "$output"
}

trap handle_cleanup EXIT

if flock -w 30 -E 250 /tmp/build-sensor-watch /code/build.sh "$dir" 2>&1 | tee -a "$output"; then
  echo > "${dir}index.html" "
<html><body> 
<h3><a href='build/watch.uf2'>Download</a></h3> 
<iframe width='800' height='1000' src='build-sim/watch.html'></iframe> 
</body></html> 
"
  cat "$dir"/build.html >> /builds/list.html
  touch "${dir}completed"
else
  if [ "$?" -eq 250 ]; then
    echo "Timed out waiting for build lock. System probably overloaded. Try again later." | tee -a "$output"
    # In this case, we don't touch 'completed' so the user can try again.
  else
    touch "${dir}completed"
  fi
  echo > "${dir}index.html" "
<html><body> 
<p>Error building firmware.</p>
<pre>$(cat "$output")</pre>
</body></html> 
"
fi
