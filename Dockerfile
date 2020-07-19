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
		/tmp/qbittorrent-src \
	&& curl -o \
	/tmp/qbittorrent.tar.gz	-L \
		"https://github.com/qbittorrent/qBittorrent/archive/release-4.2.5.tar.gz" \
	&& tar xf \
	/tmp/qbittorrent.tar.gz -C \
	/tmp/qbittorrent-src --strip-components=1

FROM alpine:${ALPINE_VER} as build-stage

############## build stage ##############

# copy artifacts from fetch stage
COPY --from=fetch-stage /tmp/qbittorrent-src /tmp/qbittorrent-src

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		boost-dev \
		g++ \
		gcc \
		make \
		qt5-qtbase-dev \
		qt5-qtsvg-dev \
		qt5-qttools-dev \
	&& apk add --no-cache \
	-X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
		libtorrent-rasterbar-dev


# build app
RUN \
	cd /tmp/qbittorrent-src \
	&& ./configure \
		--disable-gui \
		--prefix=/usr \
	&& make \
	&& make INSTALL_ROOT=/build install

FROM sparklyballs/alpine-test:${ALPINE_VER}

# environment settings
ENV HOME="/config" \
XDG_CONFIG_HOME="/config" \
XDG_DATA_HOME="/config"

# add artifacts from build stage
COPY --from=build-stage /build/usr /usr

# install runtime packages
RUN \
	apk add --no-cache \
		qt5-qtbase \
	&& apk add --no-cache \
	-X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
		libtorrent-rasterbar

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8080
VOLUME /config /downloads

