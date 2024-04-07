#!/bin/sh

cd Sensor-Watch
commit="$(git rev-parse HEAD)"

for category in clock settings complication sensor demo; do
    echo "<h3>$category</h3>"
    for f in "movement/watch_faces/$category"/*.h; do
        echo "<option data-category=\"$category\" data-url=\"https://github.com/joeycastillo/Sensor-Watch/blob/$commit/$f\" value=\"$(basename $f .h)\">$(basename $f _face.h)</option>"
    done
done
