FROM gcr.io/oss-fuzz-base/base-builder-python:v1@sha256:030add5351585b43fb46a1939aad7c82dc11c7e690eaaaf118e8b71e3b674519

COPY . $SRC/lean-relay
WORKDIR $SRC/lean-relay
COPY .clusterfuzzlite/build.sh $SRC/build.sh
