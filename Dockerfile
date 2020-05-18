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

ARG MAKE_THREADS=4

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

ARG MAKE_THREADS=4

# -----------------------------------------------------------------------------
# Julius
# https://github.com/julius-speech/julius
# Output: /julius.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as julius

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

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as kenlm

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
    cmake -DFORCE_STATIC=on .. && \
    make -j $MAKE_THREADS

RUN cd /kenlm/build/bin && \
    (strip --strip-unneeded -- * || true) && \
    tar -czvf /kenlm.tar.gz *

# -----------------------------------------------------------------------------
# Opengrm
# http://www.opengrm.org/twiki/bin/view/GRM/NGramLibrary
# Output: /opengrm.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as opengrm

ADD download/openfst-1.6.9.tar.gz /
RUN cd /openfst-1.6.9 && \
    ./configure --prefix=/build/openfst \
                --enable-static=no \
                --enable-far && \
    make -j $MAKE_THREADS && \
    make install

ADD download/opengrm-ngram-1.3.4.tar.gz /
RUN cd /opengrm-ngram-1.3.4 && \
    mkdir -p build && \
    export CXXFLAGS=-I/build/openfst/include && \
    export LDFLAGS=-L/build/openfst/lib && \
    ./configure --prefix=/build/opengrm && \
    make -j $MAKE_THREADS && \
    make install

COPY ensure_symlinks.py /

RUN cd /build/opengrm && \
    cp /build/openfst/bin/* bin/ && \
    cp /build/openfst/lib/*.so* lib/ && \
    rm -f lib/*.a lib/fst/*.a && \
    python3 /ensure_symlinks.py lib/*.so* && \
    (strip --strip-unneeded -- bin/* lib/* lib/fst/* || true) && \
    tar -czf /opengrm.tar.gz -- *

# -----------------------------------------------------------------------------
# Phonetisaurus
# https://github.com/AdolfVonKleist/Phonetisaurus
# Output: /phonetisaurus.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as phonetisaurus

ADD download/openfst-1.6.9.tar.gz /
RUN cd /openfst-1.6.9 && \
    ./configure --prefix=/build/openfst \
                --enable-static \
                --enable-shared \
                --enable-far \
                --enable-ngram-fsts && \
    make -j $MAKE_THREADS && \
    make install

ADD download/phonetisaurus-2019.tar.gz /

RUN cd /phonetisaurus && \
    ./configure --prefix=/build/phonetisaurus \
                --with-openfst-includes=/build/openfst/include \
                --with-openfst-libs=/build/openfst/lib && \
    make -j $MAKE_THREADS && \
    make install

COPY ensure_symlinks.py /

RUN cd /build/phonetisaurus && \
    mkdir -p bin lib && \
    cp /build/openfst/bin/* bin/ && \
    cp /build/openfst/lib/*.so* lib/ && \
    rm -f lib/*.a lib/fst/*.a && \
    python3 /ensure_symlinks.py lib/*.so* && \
    (strip --strip-unneeded -- bin/* lib/* || true) && \
    tar -czf /phonetisaurus.tar.gz -- *

# -----------------------------------------------------------------------------
# Kaldi
# https://kaldi-asr.org
# Output: /kaldi.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as kaldi
ARG TARGETARCH
ARG TARGETVARIANT

ENV TARGET=${TARGETARCH}${TARGETVARIANT}

ADD download/kaldi-2020.tar.gz /

# Set ATLASLIBDIR
COPY set-atlas-dir.sh /

COPY download/tools/* /download/
ENV DOWNLOAD_DIR=/download

# Install tools
RUN if [ "${TARGET}" != 'armv6' ]; then \
    cd /kaldi-master/tools && \
    make -j $MAKE_THREADS; \
    fi

# Fix things for aarch64 (arm64v8)
COPY linux_atlas_aarch64.mk /kaldi-master/src/makefiles/

RUN if [ "${TARGET}" != 'armv6' ]; then \
    cd /kaldi-master/src && \
    if [ -f '/usr/lib/arm-linux-gnueabihf/libatlas.so' ]; then \
        export ATLASLIBDIR='/usr/lib/arm-linux-gnueabihf'; \
    elif [ -f '/usr/lib/aarch64-linux-gnu/libatlas.so' ]; then \
        export ATLASLIBDIR='/usr/lib/aarch64-linux-gnu'; \
    fi && \
    ./configure --shared --mathlib=ATLAS --use-cuda=no; \
    fi

COPY fix-configure.sh /
RUN bash /fix-configure.sh

# Build Kaldi
RUN if [ "${TARGET}" != 'armv6' ]; then \
    cd /kaldi-master/src && \
    make depend -j $MAKE_THREADS && \
    make -j $MAKE_THREADS; \
    fi

# Fix symbolic links in kaldi/src/lib
COPY fix-links.sh /
RUN if [ "${TARGET}" != 'armv6' ]; then \
    bash /fix-links.sh /kaldi-master/src/lib/*.so* && \
    mkdir -p /dist/kaldi/egs && \
    cp -R /kaldi-master/egs/wsj /dist/kaldi/egs/ && \
    find /kaldi-master/src/ -type f -executable -exec cp {} /dist/kaldi/ \; && \
    cp /kaldi-master/src/lib/*.so* /dist/kaldi/ && \
    rsync -av --include='*.so*' --include='fst' --exclude='*' /kaldi-master/tools/openfst/lib/ /dist/kaldi/ && \
    cp /kaldi-master/tools/openfst/bin/* /dist/kaldi/ && \
    find /dist/kaldi/ -type f -exec patchelf --set-rpath '$ORIGIN' {} \; && \
    (strip --strip-unneeded -- /dist/kaldi/* || true) && \
    tar -C /dist -czvf /kaldi.tar.gz kaldi; \
    else \
    touch /kaldi.tar.gz; \
    fi

# -----------------------------------------------------------------------------

FROM scratch
ARG TARGETARCH
ARG TARGETVARIANT

ENV TARGET=${TARGETARCH}${TARGETVARIANT}

COPY --from=julius /julius.tar.gz /julius-4.5_${TARGET}.tar.gz
COPY --from=kenlm /kenlm.tar.gz /kenlm-20200308_${TARGET}.tar.gz
COPY --from=opengrm /opengrm.tar.gz /opengrm-1.3.4_${TARGET}.tar.gz
COPY --from=phonetisaurus /phonetisaurus.tar.gz /phonetisaurus-2019_${TARGET}.tar.gz
COPY --from=kaldi /kaldi.tar.gz /kaldi-2020_${TARGET}.tar.gz
