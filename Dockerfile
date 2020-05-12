FROM ubuntu:bionic as build-ubuntu

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        wget curl ca-certificates \
        libatlas-base-dev libatlas3-base gfortran \
        automake autoconf unzip sox libtool subversion \
        python3 python \
        git zlib1g-dev patchelf rsync \
        libboost-all-dev cmake zlib1g-dev libbz2-dev liblzma-dev

FROM build-ubuntu as build-amd64

FROM build-ubuntu as build-armv7

FROM build-ubuntu as build-arm64

FROM balenalib/raspberry-pi-debian:stretch-build as build-armv6

RUN install_packages \
        wget curl ca-certificates \
        libatlas-base-dev libatlas3-base gfortran \
        automake autoconf unzip sox libtool subversion \
        python3 python \
        git zlib1g-dev patchelf rsync \
        libboost-all-dev cmake zlib1g-dev libbz2-dev liblzma-dev

# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT

ARG MAKE_THREADS=8

# -----------------------------------------------------------------------------
# Julius
# https://github.com/julius-speech/julius
# Output: /julius.tar.gz
# -----------------------------------------------------------------------------

ADD download/julius-2019.tar.gz /
RUN cd /julius-master && \
    ./configure --prefix=/build/julius --enable-words-int && \
    make -j $MAKE_THREADS  && \
    make install

RUN cd /build/julius/bin && tar -czvf /julius.tar.gz *

# -----------------------------------------------------------------------------
# KenLM
# https://kheafield.com/code/kenlm/
# Output: /kenlm.tar.gz
# -----------------------------------------------------------------------------

ADD download/eigen-3.2.8.tar.bz2 /
RUN cd /eigen-eigen-07105f7124f9 && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make -j $MAKE_THREADS install

ADD download/kenlm-20200308.tar.gz /

# Build kenlm
RUN cd /kenlm && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make -j $MAKE_THREADS

RUN cd /kenlm/build/bin && \
    (strip --strip-unneeded -- * || true) && \
    tar -czvf /kenlm.tar.gz *

# -----------------------------------------------------------------------------
# OpenFST
# http://www.openfst.org
# Output: /build/openfst
# -----------------------------------------------------------------------------

ADD download/openfst-1.6.9.tar.gz /
RUN cd /openfst-1.6.9 && \
    ./configure --prefix=/build/openfst \
                --enable-static \
                --enable-shared \
                --enable-far \
                --enable-ngram-fsts && \
    make -j $MAKE_THREADS && \
    make install

# -----------------------------------------------------------------------------
# Opengrm
# http://www.opengrm.org/twiki/bin/view/GRM/NGramLibrary
# Output: /opengrm.tar.gz
# -----------------------------------------------------------------------------

ADD download/opengrm-ngram-1.3.4.tar.gz /
RUN cd /opengrm-ngram-1.3.4 && \
    mkdir -p build && \
    export CXXFLAGS=-I/build/openfst/include && \
    export LDFLAGS=-L/build/openfst/lib && \
    ./configure --prefix=/build/opengrm && \
    make -j $MAKE_THREADS && \
    make install

RUN cd /build/opengrm && \
    cp "/build/openfst/bin"/* bin/ && \
    cp "/build/openfst/lib"/*.so* lib/ && \
    rm -f lib/*.a lib/fst/*.a && \
    (strip --strip-unneeded -- bin/* lib/* lib/fst/* || true) && \
    tar -czf /opengrm.tar.gz -- *

# -----------------------------------------------------------------------------
# Phonetisaurus
# https://github.com/AdolfVonKleist/Phonetisaurus
# Output: /phonetisaurus.tar.gz
# -----------------------------------------------------------------------------

ADD download/phonetisaurus-2019.tar.gz /

RUN cd /phonetisaurus && \
    ./configure --prefix=/build/phonetisaurus \
                --with-openfst-includes=/build/openfst/include \
                --with-openfst-libs=/build/openfst/lib && \
    make -j $MAKE_THREADS && \
    make install

RUN cd /build/phontisaurus && \
    cp "/build/openfst/bin"/* bin/ && \
    cp "/build/openfst/lib"/*.so* lib/ && \
    rm -f lib/*.a lib/fst/*.a && \
    (strip --strip-unneeded -- bin/* lib/* || true) && \
    tar -czf /phonetisaurus.tar.gz -- *

# -----------------------------------------------------------------------------
# Kaldi
# https://kaldi-asr.org
# Output: /kaldi.tar.gz
# -----------------------------------------------------------------------------

ADD download/kaldi-2020.tar.gz /

# Set ATLASLIBDIR
COPY set-atlas-dir.sh /
RUN bash /set-atlas-dir.sh

COPY download/tools/* /download/
ENV DOWNLOAD_DIR=/download

# Install tools
RUN cd /kaldi-master/tools && \
    make -j $MAKE_THREADS

# Fix things for aarch64 (arm64v8)
COPY linux_atlas_aarch64.mk /kaldi-master/src/makefiles/

RUN cd /kaldi-master/src && \
    ./configure --shared --mathlib=ATLAS --use-cuda=no

COPY fix-configure.sh /
RUN bash /fix-configure.sh

# Build Kaldi
RUN cd /kaldi-master/src && \
    make depend -j $MAKE_THREADS && \
    make -j $MAKE_THREADS

# Fix symbolic links in kaldi/src/lib
COPY fix-links.sh /
RUN bash /fix-links.sh /kaldi-master/src/lib/*.so*

RUN mkdir -p /dist/kaldi/egs && \
    cp -R /kaldi-master/egs/wsj /dist/kaldi/egs/ && \
    rsync -av --exclude='*.o' --exclude='*.cc' /kaldi-master/src/bin/ /dist/kaldi/ && \
    cp /kaldi-master/src/lib/*.so* /dist/kaldi/ && \
    rsync -av --include='*.so*' --include='fst' --exclude='*' /kaldi-master/tools/openfst/lib/ /dist/kaldi/ && \
    cp /kaldi-master/tools/openfst/bin/ /dist/kaldi/

# Fix rpaths
RUN find /dist/kaldi/ -type f -exec patchelf --set-rpath '$ORIGIN' {} \;

# Strip and compress
RUN (strip --strip-unneeded -- /dist/kaldi/* || true) && \
    tar -C /dist -czvf /kaldi.tar.gz .