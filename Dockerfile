ARG ALPINE_VER="edge"
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
		/tmp/rasterbar-src \
		/tmp/qbittorrent-src \
	&& curl -o \
	/tmp/rasterbar.tar.gz	-L \
		"https://github.com/arvidn/libtorrent/releases/download/${LIBTORRENT_RELEASE//./_}/libtorrent-rasterbar-${LIBTORRENT_RELEASE#libtorrent.}.tar.gz" \
	&& tar xf \
	/tmp/rasterbar.tar.gz -C \
	/tmp/rasterbar-src --strip-components=1 \
	&& curl -o \
	/tmp/qbittorrent.tar.gz	-L \
		"https://github.com/qbittorrent/qBittorrent/archive/release-4.2.5.tar.gz" \
	&& tar xf \
	/tmp/qbittorrent.tar.gz -C \
	/tmp/qbittorrent-src --strip-components=1

FROM alpine:${ALPINE_VER} as rasterbar-build-stage

############## rasterbar build stage ##############

# add  artifacts from fetch stage
COPY --from=fetch-stage /tmp/rasterbar-src /tmp/rasterbar-src

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		boost-dev \
		cmake \
		g++ \
		gcc \
		git \
		openssl-dev \
		make \
		qt5-qttools-dev

# set workdir
WORKDIR /tmp/rasterbar-src

# build rasterbar
RUN \
	set -ex \
	&& ./configure \
		--localstatedir=/var \
		--prefix=/usr \
		--sysconfdir=/etc \
		
	&& make -j8 \
	&& make DESTDIR=/rasterbar-build-output install

FROM alpine:${ALPINE_VER} as qbittorrent-build-stage

############## qbittorrent build stage ##############

# add  artifacts from fetch stage
COPY --from=fetch-stage /tmp/qbittorrent-src /tmp/qbittorrent-src

# add artifacts from rasterbar build stage
COPY --from=rasterbar-build-stage /rasterbar-build-output/usr /usr

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		boost-dev \
		cmake \
		g++ \
		gcc \
		git \
		openssl-dev \
		make \
		qt5-qttools-dev


# set workdir
WORKDIR /tmp/qbittorrent-src

# build app
RUN \
	set -ex \
	&& ./configure \
		--disable-gui \
		--prefix=/usr \
	&& make -j8 \
	&& make INSTALL_ROOT=/build-output install

FROM sparklyballs/alpine-test:${ALPINE_VER} as strip-stage

############## strip stage ##############

# add artifacts from build stages
COPY --from=qbittorrent-build-stage /build-output/usr /strip-output/usr
COPY --from=rasterbar-build-stage /rasterbar-build-output/usr /strip-output/usr

# set workdir
WORKDIR /strip-output/usr

# install strip packages
RUN \
	set -ex \
	&& apk add --no-cache \
		bash \
		binutils

# strip packages
RUN \
	set -ex \
	&& find . -type f | xargs strip --strip-all || true

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
COPY --from=strip-stage /strip-output/usr /usr

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
