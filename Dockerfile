# ruTorrent 3.10 on Ubuntu 18.04 with a locally rebuilt php7.2.
#
# Stage 1 rebuilds Ubuntu's php7.2 source package with the patches in
# php72-patches/. Stage 2 is the deployed 3.10 image with only its php7.2
# packages replaced, so the PHP ABI, extensions (including the PECL geoip
# module), configuration and the ruTorrent code stay as they were.

ARG PHP72_SOURCE_VERSION=7.2.24-0ubuntu0.18.04.17
ARG PHP72_LOCAL_SUFFIX=+cylo2

FROM ubuntu:18.04@sha256:152dc042452c496007f07ca9127571cb9c29697f42acbfad72324b2bb2e43c98 AS php72-build
ARG PHP72_SOURCE_VERSION
ARG PHP72_LOCAL_SUFFIX
ENV DEBIAN_FRONTEND=noninteractive DEBFULLNAME="Appbox build" DEBEMAIL=build@localhost

RUN sed -i 's/^# deb-src/deb-src/' /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends build-essential devscripts dpkg-dev fakeroot quilt \
    && apt-get build-dep -y "php7.2=${PHP72_SOURCE_VERSION}"

# apt resolves the tools and build dependencies above without version pins.
# release/php72-build-packages.txt records the packages this release was
# built with; stop if apt installed anything else.
COPY release/php72-build-packages.txt /build/
RUN dpkg-query -W -f='${Status}|${Package} ${Version} ${Architecture}\n' \
        | sed -n 's/^install ok installed|//p' | LC_ALL=C sort \
        | diff -u /build/php72-build-packages.txt -

WORKDIR /build
RUN apt-get source --only-source "php7.2=${PHP72_SOURCE_VERSION}"
COPY php72-patches/ /build/php72-patches/

# Append each local patch to the package's quilt series and fail the build
# if any of them does not apply cleanly.
RUN cd php7.2-7.2.24 \
    && export QUILT_PATCHES=debian/patches \
    && for patch in /build/php72-patches/*.patch; do \
           [ -e "$patch" ] || continue; \
           cp "$patch" debian/patches/; \
           basename "$patch" >> debian/patches/series; \
           quilt push "$(basename "$patch")"; \
       done \
    && dch --newversion "${PHP72_SOURCE_VERSION}${PHP72_LOCAL_SUFFIX}" --distribution bionic-security \
           "Appbox: apply local security patches from php72-patches/." \
    && DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -uc -us

FROM repo.cylo.net/rutorrent@sha256:0041c3e3b84513b1c210d7a2f7f7e8d9f6f790570777381fd13deb13fff80201

# Replace exactly the php7.2 packages the deployed image has installed.
COPY --from=php72-build \
    /build/php7.2-common_*_amd64.deb \
    /build/php7.2-json_*_amd64.deb \
    /build/php7.2-opcache_*_amd64.deb \
    /build/php7.2-readline_*_amd64.deb \
    /build/php7.2-cli_*_amd64.deb \
    /build/php7.2-fpm_*_amd64.deb \
    /build/php7.2-mbstring_*_amd64.deb \
    /build/php7.2-xml_*_amd64.deb \
    /build/php7.2-zip_*_amd64.deb \
    /tmp/php72/

RUN apt-get update \
    && apt-get install -y --no-install-recommends /tmp/php72/*.deb \
    && rm -rf /tmp/php72 /var/lib/apt/lists/* \
    && php-fpm7.2 -t

ADD scripts /scripts

RUN chmod -R +x /scripts/*

EXPOSE 80

CMD [ "/scripts/start.sh" ]
