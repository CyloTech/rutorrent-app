FROM repo.cylo.io/alpine-lep

ENV RUTORRENT_VERSION master

RUN NB_CORES=-j${BUILD_CORES-`getconf _NPROCESSORS_CONF`} && apk update && \
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
    sed \
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
    xz \
    subversion \
    patch

RUN pecl install geoip-1.1.1
RUN echo "extension=geoip.so" > /usr/local/etc/php/conf.d/cylo-geoip.ini
RUN wget -q http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz && \
    gunzip GeoIP.dat.gz && \
    mkdir -p /usr/share/GeoIP && \
    mv GeoIP.dat /usr/share/GeoIP/GeoIP.dat
RUN git clone https://github.com/mcrapet/plowshare && cd plowshare && make install && plowmod --install && cd .. && rm -rf plowshare
RUN apk add -X http://dl-cdn.alpinelinux.org/alpine/v3.6/main -U cppunit-dev==1.13.2-r1 cppunit==1.13.2-r1
RUN /bin/su -s /bin/bash -c "cd && \
TERM=xterm git clone https://github.com/CyloTech/rtorrent-ps.git && \
cd rtorrent-ps && \
nice time ./build.sh all && \
cd && \
rm -rf rtorrent-ps" nginx

RUN curl -fSL http://www.rarlab.com/rar/rarlinux-5.3.0.tar.gz -o rar.tar.gz && \
    tar -xzvf rar.tar.gz && \
    mv rar/rar_static /usr/bin/rar && \
    ln -s /usr/bin/rar /usr/bin/unrar && \
    rm -rf rar*

RUN mkdir -p /sources/html/

RUN curl -fSL https://github.com/Novik/ruTorrent/archive/$RUTORRENT_VERSION.tar.gz -o rutorrent.tar.gz && \
    tar xzf rutorrent.tar.gz && \
    mv ruTorrent-$RUTORRENT_VERSION/* /sources/html/ && \
    rm -rf ruTorrent-$RUTORRENT_VERSION && \
    rm -rf rutorrent.tar.gz && \
    git clone https://github.com/nelu/rutorrent-thirdparty-plugins.git /tmp/plugins && \
    mv /tmp/plugins/filemanager  /sources/html/plugins/ && \
    mv /tmp/plugins/fileshare /sources/html/plugins/ && \
    mv /tmp/plugins/fileupload /sources/html/plugins/ && \
    rm -rf /tmp/plugins && \
    chmod 755 /sources/html/plugins/filemanager/scripts/* && \
    mkdir -p /sources/html/no-auth && \
    ln -s /sources/html/plugins/fileshare/share.php /sources/html/no-auth/share.php && \
    sed -i /getConfFile/d /sources/html/plugins/fileshare/share.php

RUN cd /sources/html/plugins/ && \
    cd /sources/html/plugins/theme/themes  && \
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

RUN cd /sources/html/plugins/ && \
    git clone https://github.com/Gyran/rutorrent-pausewebui pausewebui && \
    git clone https://github.com/Gyran/rutorrent-ratiocolor ratiocolor && \
    sed -i 's/changeWhat = "cell-background";/changeWhat = "font";/g' ratiocolor/init.js && \
    git clone https://github.com/Gyran/rutorrent-instantsearch instantsearch && \
    git clone https://github.com/Korni22/rutorrent-logoff logoff && \
    git clone https://github.com/dioltas/AddZip && \
    git clone https://github.com/orobardet/rutorrent-force_save_session force_save_session && \
    git clone https://github.com/AceP1983/ruTorrent-plugins && \
    mv ruTorrent-plugins/* . && \
    rm -rf ruTorrent-plugins && \
    git clone https://github.com/radonthetyrant/rutorrent-discord.git

# Patch rutorrent erase data!
ADD sources/erasedata.patch /sources/erasedata.patch
RUN cd /sources/html/ && \
    patch -p1 < /sources/erasedata.patch

ADD sources/label-encoding.patch /sources/label-encoding.patch
RUN cd /sources/html/ && \
    patch -p1 < /sources/label-encoding.patch

ADD sources/config.php /sources/html/conf/config.php
ADD sources/.rtorrent.rc /sources/.rtorrent.rc
ADD sources/autotools.dat /sources/autotools.dat
ADD sources/filemanager.conf /sources/html/plugins/filemanager/conf.php
ADD sources/nginx-site.conf /etc/nginx/sites-available/default.conf
ADD scripts/entrypoint.sh /scripts/entrypoint.sh
ADD sources/ffmpeg /usr/bin/ffmpeg
ADD sources/ffprobe /usr/bin/ffprobe

RUN chmod -R +x /scripts
RUN apk del .build-deps  && rm -rf /tmp/* && \
    rm -rf /var/cache/apk/*

ENTRYPOINT [ "/scripts/entrypoint.sh" ]
CMD [ "/start.sh" ]