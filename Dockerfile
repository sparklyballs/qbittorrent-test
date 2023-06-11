ARG ALPINE_VER="3.18"
FROM alpine:${ALPINE_VER} as fetch-stage

# build args
ARG RELEASE
ARG LIBTORRENT_RELEASE

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl \
		jq

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# fetch source
RUN \
	if [ -z ${LIBTORRENT_RELEASE+x} ]; then \
	LIBTORRENT_RELEASE=$(curl -u "${SECRETUSER}:${SECRETPASS}" -sX GET "https://api.github.com/repos/arvidn/libtorrent/releases/latest" \
	| jq -r ".tag_name" | sed "s/v//"); \
	fi \
	&& mkdir -p \
		/src/rasterbar \
	&& curl -o \
	/tmp/rasterbar.tar.gz -L \
	"https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_RELEASE}/libtorrent-rasterbar-${LIBTORRENT_RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/rasterbar.tar.gz -C \
	/src/rasterbar --strip-components=1 \
	&& if [ -z ${RELEASE+x} ]; then \
	RELEASE=$(curl -u "${SECRETUSER}:${SECRETPASS}" -sX GET "https://api.github.com/repos/qbittorrent/qBittorrent/tags"  \
	| jq -r ".[0].name"); \
	fi \
	&& mkdir -p \
		/src/qbittorrent \
	&& curl -o \
	/tmp/qbittorrent.tar.gz	-L \
		"https://github.com/qbittorrent/qBittorrent/archive/refs/tags/${RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/qbittorrent.tar.gz -C \
	/src/qbittorrent --strip-components=1


FROM alpine:${ALPINE_VER} as packages-stage

# install build packages
RUN \
	apk add --no-cache \
	boost-dev \
	cmake \
	gcc \
	g++ \
	openssl-dev \
	qt6-qtbase-dev \
	qt6-qtsvg-dev \
	qt6-qttools-dev \
	samurai

FROM packages-stage as rasterbar-build-stage

############## rasterbar build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /src /src

# create build directory for cmake
RUN \
	mkdir -p \
		/src/rasterbar/build

# set workdir
WORKDIR /src/rasterbar/build

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

# add artifacts from source stage
COPY --from=fetch-stage /src /src

# add artifacts from rasterbar build stage
COPY --from=rasterbar-build-stage /output/rasterbar/usr /usr

# set workdir
WORKDIR /src/qbittorrent

# build app
RUN \
	set -ex \
	&& cmake -B build-nox -G Ninja \
		-DCMAKE_BUILD_TYPE=None \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DGUI=OFF \
		-DSTACKTRACE=OFF \
		-DQT6=ON \
	&& cmake --build build-nox \
	&& install -Dm755 build-nox/qbittorrent-nox \
		-t /output/qbittorrent/usr/bin

FROM alpine:${ALPINE_VER} as strip-stage

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

# add unrar
# builds will fail unless you download a copy of the build artifacts and place in a folder called build
# sourced from the relevant builds here https://ci.sparklyballs.com/job/App-Builds/

COPY /build/unrar-*.tar.gz /usr/bin/

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
		qt6-qtbase \
		unzip

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8080
VOLUME /config /downloads
