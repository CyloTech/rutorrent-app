FROM repo.cylo.io/alpine-lep

ENV RUTORRENT_VERSION master

ARG RTORRENT_VERSION=0.9.6
ARG LIBTORRENT_VERSION=0.13.6
ARG XMLRPC_VERSION=01.51.00
ARG LIBSIG_VERSION=2.10.0
ARG CARES_VERSION=1.13.0
ARG CURL_VERSION=7.55.1

RUN NB_CORES=${BUILD_CORES-`getconf _NPROCESSORS_CONF`} && apk update && \
    apk add --no-cache \
    mediainfo \
    unzip \
    gzip \
    tar \
    geoip-dev \
    wget \
    irssi \
    irssi-perl \
    sox \
    zip \
    bzip2 \
    ffmpeg \
    findutils \
    perl-xml-libxml \
    perl-json \
    perl-archive-zip \
    perl-html-parser \
    perl-net-ssleay \
    ca-certificates \
    coreutils \
    file \
    cksfv \
    fontconfig \
    ttf-freefont

RUN docker-php-ext-install xml sockets

RUN apk add --no-cache --virtual .build-deps \
    build-base \
    libtool \
    automake \
    autoconf \
    wget \
    binutils \
    cppunit-dev \
    libressl-dev \
    ncurses-dev \
    zlib-dev \
    xz

RUN pecl install geoip-1.1.1
RUN echo "extension=geoip.so" > /usr/local/etc/php/conf.d/cylo-geoip.ini
RUN git clone https://github.com/mcrapet/plowshare
RUN cd plowshare && make install
RUN plowmod --install
RUN cd && rm -rf plowshare
RUN apk add -X http://dl-cdn.alpinelinux.org/alpine/v3.6/main -U cppunit-dev==1.13.2-r1 cppunit==1.13.2-r1
RUN cd /tmp && \
    git clone https://github.com/mirror/xmlrpc-c.git && \
    cd xmlrpc-c/stable && ./configure && make -j ${NB_CORES} && make install && \
    cd /tmp && wget http://ftp.gnome.org/pub/GNOME/sources/libsigc++/2.10/libsigc++-${LIBSIG_VERSION}.tar.xz && \
    unxz libsigc++-${LIBSIG_VERSION}.tar.xz && tar -xf libsigc++-${LIBSIG_VERSION}.tar && \
    cd libsigc++-${LIBSIG_VERSION} && ./configure && make -j ${NB_CORES} && make install && \
    cd /tmp && wget https://c-ares.haxx.se/download/c-ares-${CARES_VERSION}.tar.gz && \
    tar zxf c-ares-${CARES_VERSION}.tar.gz && \
    cd c-ares-${CARES_VERSION} && ./configure && make -j ${NB_CORES} && make install && \
    cd /tmp && wget https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz && \
    tar zxf curl-${CURL_VERSION}.tar.gz && \
    cd curl-${CURL_VERSION}  && ./configure --enable-ares --enable-tls-srp --enable-gnu-tls --with-ssl --with-zlib && make && make install && \
    cd /tmp && git clone https://github.com/rakshasa/libtorrent.git && cd libtorrent && git checkout tags/${LIBTORRENT_VERSION} && \
    ./autogen.sh && ./configure --with-posix-fallocate && make -j ${NB_CORES} && make install && \
    cd /tmp && git clone https://github.com/rakshasa/rtorrent.git && cd rtorrent && git checkout tags/${RTORRENT_VERSION} && \
    ./autogen.sh && ./configure --with-xmlrpc-c --with-ncurses && make -j ${NB_CORES} && make install

RUN curl -fSL http://www.rarlab.com/rar/rarlinux-5.3.0.tar.gz -o rar.tar.gz && \
    tar -xzvf rar.tar.gz && \
    mv rar/rar_static /usr/bin/rar && \
    ln -s /usr/bin/rar /usr/bin/unrar && \
    rm -rf rar*

RUN curl -fSL https://github.com/Novik/ruTorrent/archive/$RUTORRENT_VERSION.tar.gz -o rutorrent.tar.gz && \
    tar xzf rutorrent.tar.gz && \
    mv ruTorrent-$RUTORRENT_VERSION/* /var/www/html/ && \
    rm -rf ruTorrent-$RUTORRENT_VERSION && \
    rm -rf rutorrent.tar.gz && \
    git clone https://github.com/nelu/rutorrent-thirdparty-plugins.git /tmp/plugins && \
    mv /tmp/plugins/filemanager  /var/www/html/plugins/ && \
    mv /tmp/plugins/fileshare /var/www/html/plugins/ && \
    mv /tmp/plugins/fileupload /var/www/html/plugins/ && \
    rm -rf /tmp/plugins && \
    chmod 755 /var/www/html/plugins/filemanager/scripts/* && \
    mkdir -p /var/www/html/no-auth && \
    ln -s /var/www/html/plugins/fileshare/share.php /var/www/html/no-auth/share.php && \
    sed -i /getConfFile/d /var/www/html/plugins/fileshare/share.php

RUN cd /var/www/html/plugins/ && \
    cd /var/www/html/plugins/theme/themes  && \
    git clone https://github.com/ArtyumX/ruTorrent-Themes && \
    mv ruTorrent-Themes/* . && \
    rm -rf ruTorrent-Themes && \
    rm -rf ./*.png && \
    rm -rf ./*.jpg && \
    rm -rf ./*.md && \
    rm -rf club-QuickBox && \
    git clone https://github.com/QuickBox/club-QuickBox.git club-QuickBox

RUN	mkdir -p /var/cache/nginx/.irssi/scripts/autorun && \
    cd /var/cache/nginx/.irssi/scripts && \
	curl -sL http://git.io/vlcND | grep -Po '(?<="browser_download_url": ")(.*-v[\d.]+.zip)' | xargs wget --quiet -O autodl-irssi.zip && \
	unzip -o autodl-irssi.zip && \
	rm autodl-irssi.zip && \
	cp autodl-irssi.pl autorun/ && \
    echo "load perl" > /var/cache/nginx/.irssi/startup

RUN cd /var/www/html/plugins/ && \
    git clone https://github.com/Gyran/rutorrent-pausewebui pausewebui && \
    git clone https://github.com/Gyran/rutorrent-ratiocolor ratiocolor && \
    sed -i 's/changeWhat = "cell-background";/changeWhat = "font";/g' ratiocolor/init.js && \
    git clone https://github.com/Gyran/rutorrent-instantsearch instantsearch && \
    git clone https://github.com/Korni22/rutorrent-logoff logoff && \
    git clone https://github.com/xombiemp/rutorrentMobile && \
    git clone https://github.com/dioltas/AddZip && \
    git clone https://github.com/orobardet/rutorrent-force_save_session force_save_session && \
    git clone https://github.com/AceP1983/ruTorrent-plugins && \
    mv ruTorrent-plugins/* . && \
    rm -rf ruTorrent-plugins && \
    git clone https://github.com/radonthetyrant/rutorrent-discord.git

RUN mkdir -p /sources
ADD sources/config.php /var/www/html/conf/config.php
ADD sources/.rtorrent.rc /sources/.rtorrent.rc
ADD sources/filemanager.conf /var/www/html/plugins/filemanager/conf.php
ADD sources/nginx-site.conf /etc/nginx/sites-available/default.conf
ADD scripts/entrypoint.sh /scripts/entrypoint.sh
ADD scripts/ffmpeg /usr/bin/ffmpeg
ADD scripts/ffprobe /usr/bin/ffprobe

RUN chmod -R +x /scripts
RUN apk del .build-deps  && rm -rf /tmp/* && \
    rm -rf /var/cache/apk/*

ENTRYPOINT [ "/scripts/entrypoint.sh" ]
CMD [ "/start.sh" ]