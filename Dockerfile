FROM openresty/openresty:bookworm

ENV DEBIAN_FRONTEND noninteractive

# These should all be one big install,
# but the fly.io registry kept dying on big layer transfers...
# Possibly should just do a two stage build.

RUN apt-get update && \
  apt-get install -y --no-install-recommends git make patch && \
  rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
  apt-get install -y --no-install-recommends gcc-arm-none-eabi && \
  rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
  apt-get install -y --no-install-recommends libnewlib-arm-none-eabi && \
  rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
  apt-get install -y --no-install-recommends clang && \
  rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
  apt-get install -y --no-install-recommends llvm lld & \
  rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
  apt-get install -y --no-install-recommends nodejs && \
  rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
  apt-get install -y --no-install-recommends emscripten && \
  rm -rf /var/lib/apt/lists/*

# Bookworm seems to setup a decent FROZEN_CACHE which means
# this is no longer necessary for decent perf.
#ENV EM_CACHE /emcache
#ENV EM_CONFIG /emconfig
#RUN emcc --generate-config

RUN git clone https://github.com/joeycastillo/Sensor-Watch.git

WORKDIR Sensor-Watch/

COPY *.patch ./
RUN for f in *.patch; do patch -p1 < "$f"; done

RUN emmake make -C movement/make 'BUILD=build-sim' 'COLOR=RED'
RUN make -C movement/make 'BUILD=build-RED' COLOR=RED
RUN make -C movement/make 'BUILD=build-GREEN' COLOR=GREEN
RUN make -C movement/make 'BUILD=build-BLUE' COLOR=BLUE

COPY *.afterpatch ./
RUN for f in *.afterpatch; do patch -p1 < "$f"; done

WORKDIR /
RUN mkdir /builds
RUN touch /builds/list.html
#RUN chown -R www-data:www-data /emcache
RUN chown -R www-data:www-data /builds
COPY nginx.conf /usr/local/openresty/nginx/conf/
COPY static static
RUN sed -n '/#include/{s/#include "\(.*\).h"/  <option value="\1">\1<\/option>/;p}' Sensor-Watch/movement/movement_faces.h > static/available_faces.html
RUN cd /Sensor-Watch && git rev-parse HEAD > /static/commit_hash
COPY templates templates
COPY code code
RUN sed -n -e '/#include/{s/#include "\(.*\).h"/  \1 = true,/;p}' -e '1i return {' -e ';$a }' Sensor-Watch/movement/movement_faces.h > code/available_faces.lua
