ARG ALPINE_VER="3.22"
FROM alpine:${ALPINE_VER} as base

# cmake options
ENV CFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS"
ENV CXXFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS"
ENV LDFLAGS="-gz -Wl,-O1,--as-needed,--sort-common,-z,now,-z,relro"

# build args
ARG RELEASE
ARG LIBTORRENT_RELEASE

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl \
		grep \
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
	RELEASE=$(curl -u "${SECRETUSER}:${SECRETPASS}" -sX GET "https://api.github.com/repos/qbittorrent/qBittorrent/tags" \
	| jq -r ".[].name" \
	| grep -v -e 'alpha' -e 'beta' -e 'rc' \
	| head -n 1); \
	fi \
	&& mkdir -p \
		/src/qbittorrent \
	&& curl -o \
	/tmp/qbittorrent.tar.gz	-L \
		"https://github.com/qbittorrent/qBittorrent/archive/refs/tags/${RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/qbittorrent.tar.gz -C \
	/src/qbittorrent --strip-components=1


FROM base as build_stage

# install build packages
RUN \
	apk add --no-cache \
		boost-dev \
		cmake \
		git \
		g++ \
		ninja \
		openssl-dev \
		qt6-qtbase-dev \
		qt6-qtbase-private-dev \
		qt6-qttools-dev

WORKDIR /src/rasterbar

# build rasterbar
RUN \
	cmake \
		-B build \
		-G Ninja \
		-DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
		-Ddeprecated-functions=OFF \
		&& cmake --build build -j "$(nproc)" \
		&& cmake --install build

WORKDIR /src/qbittorrent

# build qbitorrent
RUN \
	cmake \
		-B build \
		-G Ninja \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
		-DGUI=OFF \
		-DQT6=ON \
	&& cmake --build build -j "$(nproc)" \
	&& cmake --install build \
	&& strip /usr/bin/qbittorrent-nox

FROM sparklyballs/alpine-test:${ALPINE_VER}

# copy build artifacts
COPY --from=build_stage /usr/bin/qbittorrent-nox /usr/bin/qbittorrent-nox

# add unrar
# builds will fail unless you download a copy of the build artifacts and place in a folder called build
# sourced from the relevant builds here https://ci.sparklyballs.com/job/App-Builds/

ADD /build/unrar-*.tar.gz /usr/bin/

# environment settings
ENV HOME="/config" \
XDG_CONFIG_HOME="/config" \
XDG_DATA_HOME="/config"

# install runtime packages
RUN \
	apk --no-cache add \
	bash \
	curl \
	python3 \
	qt6-qtbase \
	qt6-qtbase-sqlite \
	tzdata

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8080
VOLUME /config /downloads
