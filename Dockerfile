FROM repo.cylo.io/alpine-lep

ENV RUTORRENT_VERSION master

RUN apk update && \
    apk add --no-cache \
    mediainfo \
    rtorrent \
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
    cksfv

RUN docker-php-ext-install xml sockets

RUN apk add --no-cache --virtual .build-deps \
    build-base \
    libtool \
    automake \
    autoconf \
    wget \
    ncurses-dev \
    curl-dev

RUN pecl install geoip-1.1.1
RUN echo "extension=geoip.so" > /usr/local/etc/php/conf.d/cylo-geoip.ini
RUN git clone https://github.com/mcrapet/plowshare
RUN cd plowshare && make install
RUN plowmod --install
RUN cd && rm -rf plowshare

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
    rm -rf ./*.md

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
RUN chmod -R +x /scripts
RUN apk del .build-deps

ENTRYPOINT [ "/scripts/entrypoint.sh" ]
CMD [ "/start.sh" ]