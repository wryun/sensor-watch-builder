FROM openresty/openresty:bullseye

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

ENV EM_CACHE /emcache
RUN emcc --generate-config

RUN git clone https://github.com/joeycastillo/Sensor-Watch.git

WORKDIR Sensor-Watch/

COPY *.patch ./
RUN for f in *.patch; do patch -p1 < "$f"; done

RUN emmake make -C movement/make 'BUILD=build-sim'
RUN make -C movement/make

COPY *.afterpatch ./
RUN for f in *.afterpatch; do patch -p1 < "$f"; done

WORKDIR /
RUN mkdir /builds
RUN chown www-data:www-data /builds
RUN chown -R www-data:www-data /emcache
COPY nginx.conf /usr/local/openresty/nginx/conf/
COPY static static
COPY code code

