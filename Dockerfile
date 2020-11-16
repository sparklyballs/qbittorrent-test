ARG ALPINE_VER="3.12"
FROM alpine:${ALPINE_VER} as fetch-stage

############## fetch stage ##############

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# fetch version file
RUN \
	set -ex \
	&& curl -o \
	/tmp/version.txt -L \
	"https://raw.githubusercontent.com/sparklyballs/versioning/master/version.txt"

# fetch source code
# hadolint ignore=SC1091
RUN \
	. /tmp/version.txt \
	&& set -ex \
	&& mkdir -p \
		/source/rasterbar \
		/source/qbittorrent \
	&& curl -o \
	/tmp/rasterbar.tar.gz	-L \
		"https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_RELEASE}/libtorrent-rasterbar-${LIBTORRENT_RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/rasterbar.tar.gz -C \
	/source/rasterbar --strip-components=1 \
	&& curl -o \
	/tmp/qbittorrent.tar.gz	-L \
		"https://github.com/qbittorrent/qBittorrent/archive/release-${QBITTORRENT_TAG}.tar.gz" \
	&& tar xf \
	/tmp/qbittorrent.tar.gz -C \
	/source/qbittorrent --strip-components=1

FROM alpine:${ALPINE_VER} as packages-stage

############## packages stage ##############

# install build packages
RUN \
	apk add --no-cache \
		boost-dev \
		cmake \
		g++ \
		gcc \
		git \
		openssl-dev \
		make \
		ninja \
		qt5-qttools-dev


FROM packages-stage as rasterbar-build-stage

############## rasterbar build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /source /source

# create build directory for cmake
RUN \
	mkdir -p \
		/source/rasterbar/build

# set workdir
WORKDIR /source/rasterbar/build

# build rasterbar
RUN \
	set -ex \
	&& cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_CXX_STANDARD=14 \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \	
		-G Ninja .. \
	&& ninja -j4 \
	&& DESTDIR=/output/rasterbar ninja install

FROM packages-stage as qbittorrent-build-stage

############## qbittorrent build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /source /source

# add artifacts from rasterbar build stage
COPY --from=rasterbar-build-stage /output/rasterbar/usr /usr

# set workdir
WORKDIR /source/qbittorrent

# build app
RUN \
	set -ex \
	&& ./configure \
		--disable-gui \
		--prefix=/usr \
	&& make -j4 \
	&& make INSTALL_ROOT=/output/qbittorrent install

FROM alpine:${ALPINE_VER} as strip-stage

############## strip stage ##############

# add artifacts from build stages
COPY --from=qbittorrent-build-stage /output/qbittorrent/usr /builds/usr
COPY --from=rasterbar-build-stage /output/rasterbar/usr /builds/usr

# set workdir
WORKDIR /builds/usr

# install strip packages
RUN \
	set -ex \
	&& apk add --no-cache \
		bash \
		binutils

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# strip packages
RUN \
	set -ex \
	&& for dirs in /usr/lib /usr/bin /usr/include /usr/share; \
	do \
		find /builds/"${dirs}" -type f | \
		while read -r files ; do strip "${files}" || true \
		; done \
	; done

FROM sparklyballs/alpine-test:${ALPINE_VER}

############## runtine stage ##############

# add unrar
# sourced from self builds here:- 
# https://ci.sparklyballs.com:9443/job/App-Builds/job/unrar-build/
# builds will fail unless you download a copy of the build artifacts and place in a folder called build
ADD /build/unrar-*.tar.gz /usr/bin/

# environment settings
ENV HOME="/config" \
XDG_CONFIG_HOME="/config" \
XDG_DATA_HOME="/config"

# add artifacts from strip stage
COPY --from=strip-stage /builds/usr /usr

# install runtime packages
RUN \
	apk add --no-cache \
		boost-system \
		boost-thread \
		p7zip \
		qt5-qtbase \
		unzip

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8080
VOLUME /config /downloads
