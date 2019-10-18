FROM ubuntu
USER root

ENV LANG en_US.UTF-8
ENV RUTORRENT_VERSION master
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y git && \
    apt-get update && \
    apt-get install -y \
    locales \
    locales-all \
    tar \
    gzip \
    unzip \
    zip \
    unrar \
    rar \
    mediainfo \
    curl \
    nginx \
    wget \
    supervisor \
    libarchive-zip-perl \
    libjson-perl \
    libxml-libxml-perl \
    irssi \
    sox \
    cksfv \
    bzip2 \
    libgeoip-dev \
    php-fpm \
    plowshare \
    plowshare-modules \
    openssl \
    buildtorrent \
    php-mbstring \
    php-xml && \
    rm /etc/php/7.2/fpm/php.ini

RUN apt install -y php-pear php-dev
RUN pecl install geoip-1.1.1
RUN echo "extension=geoip.so" > /etc/php/7.2/fpm/conf.d/cylo-geoip.ini
RUN apt remove -y php-pear php-dev

RUN apt-get install -y lsb-release build-essential pkg-config \
    subversion git time lsof binutils tmux curl wget \
    python-setuptools python-virtualenv python-dev python-pip \
    libssl-dev zlib1g-dev libncurses-dev libncursesw5-dev \
    libcppunit-dev autoconf automake libtool \
    libffi-dev libxml2-dev libxslt1-dev
RUN adduser --system --disabled-password --home /var/cache/nginx --shell /sbin/nologin --group --uid 1000 nginx
RUN /bin/su -s /bin/bash -c "cd && \
TERM=xterm git clone https://github.com/CyloTech/rtorrent-ps.git && \
cd rtorrent-ps && \
nice ./build.sh all && \
cd && \
rm -rf rtorrent-ps" nginx

RUN mkdir -p /sources/html/ && mkdir -p /run/php

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
    sed -i /getConfFile/d /sources/html/plugins/fileshare/share.php && \
    sed -i "s/false/'buildtorrent'/g" /sources/html/plugins/create/conf.php && \
    sed -i "s#''#'/usr/bin/buildtorrent'#g" /sources/html/plugins/create/conf.php

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

RUN pip install cloudscraper

RUN	mkdir -p /var/cache/nginx/.irssi/scripts/autorun && \
    cd /var/cache/nginx/.irssi/scripts && \
	curl -sL http://git.io/vlcND | grep -Po '(?<="browser_download_url": ")(.*-v[\d.]+.zip)' | xargs wget --quiet -O autodl-irssi.zip && \
	unzip -o autodl-irssi.zip && \
	rm autodl-irssi.zip && \
	cp autodl-irssi.pl autorun/ && \
    echo "load perl" > /var/cache/nginx/.irssi/startup

RUN cd /sources/html/plugins/ && \
    git clone https://github.com/xombiemp/rutorrentMobile.git mobile && \
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
    git clone https://github.com/radonthetyrant/rutorrent-discord.git && \
    rm -rf ipad && \
    rm -rf cpuload

ADD sources/docker-vars.ini /etc/php/7.2/fpm/conf.d/docker-vars.ini
ADD sources/supervisord.conf /etc/supervisord.conf
ADD sources/config.php /sources/html/conf/config.php
ADD sources/.rtorrent.rc /sources/.rtorrent.rc
ADD sources/autotools.dat /sources/autotools.dat
ADD sources/filemanager.conf /sources/html/plugins/filemanager/conf.php
ADD sources/nginx-site.conf /etc/nginx/sites-enabled/default
ADD sources/www.conf /etc/php/7.2/fpm/pool.d/www.conf
ADD sources/nginx.conf /etc/nginx/nginx.conf
ADD scripts/start.sh /scripts/start.sh
ADD sources/ffmpeg /usr/bin/ffmpeg
ADD sources/ffprobe /usr/bin/ffprobe

RUN chmod -R +x /scripts


RUN groupmod -g 9999 nogroup
RUN usermod -g 9999 nobody
RUN usermod -u 9999 nobody
RUN usermod -g 9999 sync

RUN apt-get remove -y lsb-release build-essential pkg-config \
    subversion time lsof binutils \
    python-setuptools python-virtualenv python-dev \
    libssl-dev zlib1g-dev libncurses-dev libncursesw5-dev \
    libcppunit-dev autoconf automake libtool \
    libffi-dev libxml2-dev libxslt1-dev
RUN rm -rf /tmp/*
RUN apt autoremove -y && apt clean
RUN rm -rf /var/lib/apt/lists/*

EXPOSE 80

CMD [ "/scripts/start.sh" ]