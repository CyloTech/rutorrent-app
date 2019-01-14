#!/usr/bin/env bash
set -x
###########################[ COPY TO MOUNTS ]###############################

if [ ! -d /torrents/config/rutorrent/html ]; then
    echo "Did not find /torrents/config/rutorrent/html existed. Creating it and copying rutorrent into."
    mkdir -p /torrents/config/rutorrent/html
    cp -avr /sources/html/* /torrents/config/rutorrent/html/
fi

# Only needed if we need to reset .rtorrent.rc
if [[ ! $(grep '3.8-11' /torrents/config/rtorrent/.rtorrent.rc) && ! $(grep '3.8-15' /torrents/config/rtorrent/.rtorrent.rc) && ! $(grep '3.8-16' /torrents/config/rtorrent/.rtorrent.rc) ]]; then
    sed -i 's/"webui.reqtimeout":"30000"/"webui.reqtimeout":"60000"/g' /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/uisettings.json
    sed -i 's/"webui.ignore_timeouts":0/"webui.ignore_timeouts":1/g' /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/uisettings.json
    sed -i '/network.http.ssl_verify_host.set/d' /torrents/config/rtorrent/.rtorrent.rc
    cp /sources/html/conf/config.php /torrents/config/rutorrent/html/conf/config.php
    cp /sources/html/plugins/filemanager/conf.php /torrents/config/rutorrent/html/plugins/filemanager/conf.php
    sed -i 's/3.8-7/3.8-11/g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's/3.8-10/3.8-11/g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i '/network.http.ssl_verify_peer.set/a network.http.ssl_verify_host.set = 0' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's/network.xmlrpc.size_limit.set = 2M/network.xmlrpc.size_limit.set = 4M/g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i '/scgi_port=127.0.0.1:5000/d' /torrents/config/rtorrent/.rtorrent.rc
    sed -i '/3.8-11/a \
\
execute.nothrow = rm,/torrents/config/rtorrent/.rtorrent.sock \
network.scgi.open_local = /torrents/config/rtorrent/.rtorrent.sock \
schedule = socket_chmod,0,0,"execute=chmod,0666,/torrents/config/rtorrent/.rtorrent.sock" \
schedule = socket_chgrp,0,0,"execute=chgrp,rtorrent-socket,/torrents/config/rtorrent/.rtorrent.sock"' /torrents/config/rtorrent/.rtorrent.rc

    if [ -d /torrents/config/rutorrent/html/plugins/ipad ]; then
        rm -rf /torrents/config/rutorrent/html/plugins/ipad
        rm -rf /torrents/config/rutorrent/html/plugins/rutorrentMobile
        git clone https://github.com/xombiemp/rutorrentMobile.git /torrents/config/rutorrent/html/plugins/mobile
    fi
fi

if [[ $(grep '3.8-11' /torrents/config/rtorrent/.rtorrent.rc) ]]; then
    sed -i 's/3.8-11/3.8-15/g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i '/system.file.allocate.set/a \
\
execute = {sh,-c,/usr/bin/php /torrents/config/rutorrent/html/php/initplugins.php '${RUTORRENT_USER}' &}' /torrents/config/rtorrent/.rtorrent.rc
    mkdir -p /torrents/config/autodl-irssi/autodl
    mkdir -p /torrents/config/autodl-irssi/irssi

    rm -rf /var/cache/nginx/.autodl
    mv /torrents/config/rtorrent/autodl/* /torrents/config/autodl-irssi/autodl/
    rm -r /torrents/config/rtorrent/autodl
    ln -s /torrents/config/autodl-irssi/autodl /var/cache/nginx/.autodl

    mv /var/cache/nginx/.irssi/* /torrents/config/autodl-irssi/irssi/
    rm -r /var/cache/nginx/.irssi
    ln -s /torrents/config/autodl-irssi/irssi /var/cache/nginx/.irssi

    rm -rf /torrents/config/rutorrent/html/plugins/cpuload
fi

if [[ $(grep '3.8-15' /torrents/config/rtorrent/.rtorrent.rc) ]]; then
    sed -i 's/3.8-15/3.8-16/g' /torrents/config/rtorrent/.rtorrent.rc
    cp /sources/html/plugins/create/conf.php /torrents/config/rutorrent/html/plugins/create/conf.php
fi

if [[ $(grep '3.8-16' /torrents/config/rtorrent/.rtorrent.rc) ]]; then
    sed -i 's/3.8-16/3.8-17/g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's/schedule2 = low_diskspace,5,60,close_low_diskspace=1G/schedule2 = low_diskspace,5,60,close_low_diskspace=37G/g' /torrents/config/rtorrent/.rtorrent.rc
fi

###########################[ SUPERVISOR SCRIPTS ]###############################
cat << EOF > /etc/supervisor/conf.d/rtorrent.conf
[program:rtorrent]
command=/bin/su -s /bin/bash -c "export TERM=screen-256color && ulimit -Sn 65535; /var/cache/nginx/.local/rtorrent/0.9.6-PS-1.1-dev/bin/rtorrent-extended" nginx
autostart=true
autorestart=true
priority=2
stdout_events_enabled=false
stderr_events_enabled=true
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF > /etc/supervisor/conf.d/irssi.conf
[program:irssi]
command=/bin/su -s /bin/bash -c "TERM=xterm irssi" nginx
autostart=true
autorestart=true
priority=3
stdout_events_enabled=false
stderr_events_enabled=true
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF > /etc/supervisor/conf.d/rtorrent-log.conf
[program:rtorrent-logging]
command=/bin/su -s /bin/bash -c "TERM=xterm tail -f /torrents/config/log/rtorrent/rtorrent.log" nginx
autostart=true
autorestart=true
priority=4
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF > /etc/supervisor/conf.d/nginx.conf
[program:nginx]
command=/usr/sbin/nginx
autostart=true
autorestart=true
priority=10
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF > /etc/supervisor/conf.d/php-fpm.conf
[program:php-fpm]
command=/usr/sbin/php-fpm7.2 --nodaemonize
autostart=true
autorestart=true
priority=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

###########################[ IRSSI SETUP ]###############################
# Set up .autodl dir, and allow for configs to be saved.
if [ ! -d /torrents/config/autodl-irssi/autodl ]
then
    echo "Did not find /torrents/config/autodl-irssi/autodl existed. Creating it."
    mkdir -p /torrents/config/autodl-irssi/autodl
fi

if [ ! -d /torrents/config/autodl-irssi/irssi ]
then
    echo "Did not find /torrents/config/autodl-irssi/irssi existed. Creating it."
    mv /var/cache/nginx/.irssi /torrents/config/autodl-irssi/irssi
fi

if [ ! -h /var/cache/nginx/.autodl ]
then
	echo "Linking autodl config directory to /torrents/config/autodl-irssi/autodl"
	ln -s /torrents/config/autodl-irssi/autodl /var/cache/nginx/.autodl
else
	echo "Do not need to relink the autodl config directory."
fi

if [ ! -h /var/cache/nginx/.irssi ]
then
	echo "Linking autodl config directory to /torrents/config/autodl-irssi/irssi"
	ln -s /torrents/config/autodl-irssi/irssi /var/cache/nginx/.irssi
else
	echo "Do not need to relink the irssi config directory."
fi

if [ -f /torrents/config/autodl-irssi/autodl/autodl.cfg ]
then
	echo "Found an existing autodl config. Will not reinitialize."
	irssi_port=$(grep gui-server-port /torrents/config/autodl-irssi/autodl/autodl.cfg | awk '{print $3}')
	irssi_pass=$(grep gui-server-password /torrents/config/autodl-irssi/autodl/autodl.cfg | awk '{print $3}')
else
	echo "Need to set up a new autodl install."

	irssi_pass=$(perl -le 'print map {(a..z,A..Z,0..9)[rand 62] } 0..pop' 15)
	irssi_port=$((RANDOM%64025+1024))
	
	echo "Creating necessary configuration files ... "
cat << EOF >> /torrents/config/autodl-irssi/autodl/autodl.cfg
[options]
gui-server-port = ${irssi_port}
gui-server-password = ${irssi_pass}
upload-type = rtorrent
rt-label = \$(FilterName)
EOF
fi

# Install the web plugin.
if [ ! -d /torrents/config/rutorrent/html/plugins/autodl-irssi ]
then
	echo "Installing web plugin portion."
	# Web plugin setup.
	cd /torrents/config/rutorrent/html/plugins/
	git clone https://github.com/autodl-community/autodl-rutorrent.git autodl-irssi > /dev/null 2>&1
	cd autodl-irssi
	cp _conf.php conf.php
	sed -i "s/autodlPort = 0;/autodlPort = ${irssi_port};/" conf.php
	sed -i "s/autodlPassword = \"\";/autodlPassword = \"${irssi_pass}\";/" conf.php
else
	echo "Found web plugin portion is already installed."
fi

###########################[ RTORRENT SETUP ]###############################

# arrange dirs and configs
mkdir -p /torrents/downloading
mkdir -p /torrents/completed
mkdir -p /torrents/watch
mkdir -p /torrents/config/rtorrent/session
mkdir -p /torrents/config/log/rtorrent
mkdir -p /torrents/config/rutorrent/torrents
mkdir -p /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings
mkdir -p /torrents/config/rutorrent/users/${RUTORRENT_USER}/torrents

if [ ! -f /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/theme.dat ]
    then
    echo 'O:6:"club-QuickBox":2:{s:4:"hash";s:9:"theme.dat";s:7:"current";s:0:"";}' > /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/theme.dat
fi

if [ ! -f /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/uisettings.json ]
    then
    echo '{"webui.fls.view":0,"webui.show_cats":1,"webui.show_dets":1,"webui.needmessage":1,"webui.reqtimeout":"60000","webui.confirm_when_deleting":1,"webui.alternate_color":0,"webui.update_interval":3000,"webui.hsplit":0.88,"webui.vsplit":0.5,"webui.effects":0,"webui.fullrows":0,"webui.no_delaying_draw":1,"webui.search":-1,"webui.speedlistdl":"100,150,200,250,300,350,400,450,500,750,1000,1250","webui.speedlistul":"100,150,200,250,300,350,400,450,500,750,1000,1250","webui.ignore_timeouts":1,"webui.retry_on_error":120,"webui.closed_panels":{"ptrackers":0,"prss":0,"pstate":0,"plabel":0,"flabel":0},"webui.timeformat":0,"webui.dateformat":0,"webui.speedintitle":0,"webui.log_autoswitch":1,"webui.show_labelsize":1,"webui.register_magnet":0,"webui.lang":"en","webui.trt.colwidth":[200,100,60,100,100,100,60,60,60,60,60,60,60,80,110,90,200,100,100,100,100,110,80,60,75,75,75,100,80],"webui.trt.colenabled":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],"webui.trt.colorder":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28],"webui.trt.sindex":-1,"webui.trt.rev":0,"webui.trt.sindex2":0,"webui.trt.rev2":0,"webui.fls.colwidth":[200,60,100,100,80],"webui.fls.colenabled":[1,1,1,1,1],"webui.fls.colorder":[0,1,2,3,4],"webui.fls.sindex":-1,"webui.fls.rev":0,"webui.fls.sindex2":0,"webui.fls.rev2":0,"webui.trk.colwidth":[200,60,60,60,60,60,80,85,80,60],"webui.trk.colenabled":[1,1,1,1,1,1,1,1,1,1],"webui.trk.colorder":[0,1,2,3,4,5,6,7,8,9],"webui.trk.sindex":-1,"webui.trk.rev":0,"webui.trk.sindex2":0,"webui.trk.rev2":0,"webui.prs.colwidth":[120,100,120,60,100,100,100,60,60,60,100],"webui.prs.colenabled":[1,1,1,1,1,1,1,1,1,1,1],"webui.prs.colorder":[0,1,2,3,4,5,6,7,8,9,10],"webui.prs.sindex":-1,"webui.prs.rev":0,"webui.prs.sindex2":0,"webui.prs.rev2":0,"webui.plg.colwidth":[150,60,80,80,80,500],"webui.plg.colenabled":[1,1,1,1,1,1],"webui.plg.colorder":[0,1,2,3,4,5],"webui.plg.sindex":-1,"webui.plg.rev":0,"webui.plg.sindex2":0,"webui.plg.rev2":0,"webui.hst.colwidth":[200,100,110,60,100,100,60,60,110,110,110,100],"webui.hst.colenabled":[1,1,1,1,1,1,1,1,1,1,1,1],"webui.hst.colorder":[0,1,2,3,4,5,6,7,8,9,10,11],"webui.hst.sindex":-1,"webui.hst.rev":0,"webui.hst.sindex2":0,"webui.hst.rev2":0,"webui.teg.colwidth":[200,100,60,100,100,100,60,60,60,60,60,60,60,80,110,90,200,100,100,100,100,110,80,60,75,75,75,100,80],"webui.teg.colenabled":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],"webui.teg.colorder":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28],"webui.teg.sindex":-1,"webui.teg.rev":0,"webui.teg.sindex2":0,"webui.teg.rev2":0,"webui.rss.colwidth":[200,100,60,100,100,100,60,60,60,60,60,60,60,80,110,90,200,100,100,100,100,110,80,60,75,75,75,100,80],"webui.rss.colenabled":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],"webui.rss.colorder":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28],"webui.rss.sindex":-1,"webui.rss.rev":0,"webui.rss.sindex2":0,"webui.rss.rev2":0,"webui.fsh.colwidth":[210,60,120,80,310],"webui.fsh.colenabled":[1,1,1,1,1],"webui.fsh.colorder":[0,1,2,3,4],"webui.fsh.sindex":-1,"webui.fsh.rev":0,"webui.fsh.sindex2":0,"webui.fsh.rev2":0,"webui.flm.colwidth":[210,60,120,80,80],"webui.flm.colenabled":[1,1,1,1,1],"webui.flm.colorder":[0,1,2,3,4],"webui.flm.sindex":-1,"webui.flm.rev":0,"webui.flm.sindex2":0,"webui.flm.rev2":0,"webui.tasks.colwidth":[100,100,200,100,110,110,110],"webui.tasks.colenabled":[1,1,1,1,1,1,1],"webui.tasks.colorder":[0,1,2,3,4,5,6],"webui.tasks.sindex":-1,"webui.tasks.rev":0,"webui.tasks.sindex2":0,"webui.tasks.rev2":0,"webui.fManager.timef":"%d-%M-%y %h:%m:%s","webui.fManager.permf":1,"webui.fManager.histpath":5,"webui.fManager.stripdirs":1,"webui.fManager.showhidden":1,"webui.fManager.cleanlog":0,"webui.fManager.arcnscheme":"new","webui.fManager.scrows":12,"webui.fManager.sccols":4,"webui.fManager.scwidth":300}' > /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/uisettings.json
fi

if [ ! -f /torrents/config/rtorrent/.rtorrent.rc ]
    then
    cp /sources/.rtorrent.rc /torrents/config/rtorrent/.rtorrent.rc
    ln -s /torrents/config/rtorrent/.rtorrent.rc /var/cache/nginx/
    sed -i 's#LISTENING_PORT#'${LISTENING_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#DHT_PORT#'${DHT_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#RUTORRENT_USER#'${RUTORRENT_USER}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#http://mydomain.com#'${EXTERNAL_DOMAIN}'/no-auth#g' /torrents/config/rutorrent/html/plugins/fileshare/conf.php
    sed -i 's#300#30#g' /torrents/config/rutorrent/html/plugins/autotools/conf.php
    sed -i 's/$defaultTheme = ""/$defaultTheme = "club-QuickBox"/g' /torrents/config/rutorrent/html/plugins/theme/conf.php
    mkdir -p '/torrents/config/rutorrent/users/'${RUTORRENT_USER}'/settings/'
    cp /sources/autotools.dat '/torrents/config/rutorrent/users/'${RUTORRENT_USER}'/settings/autotools.dat'
else
    sed -i 's#network.port_range.set = [0-9]*-[0-9]*#network.port_range.set = '${LISTENING_PORT}'-'${LISTENING_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#dht.port.set=[0-9]*#dht.port.set='${DHT_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
fi

if [ ! -f /var/cache/nginx/.rtorrent.rc ]
    then
    ln -s /torrents/config/rtorrent/.rtorrent.rc /var/cache/nginx/
fi

rm -f /torrents/config/rtorrent/session/rtorrent.lock

# This got created on old version, delete it!
if [ -d /torrents/config/rutorrent/settings ]
    then
    rm -rf /torrents/config/rutorrent/settings
fi

# Empty the task folders
if [ -d /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/tasks ]
    then
    rm -rf /torrents/config/rutorrent/users/${RUTORRENT_USER}/settings/tasks
fi

###########################[ NGINX SETUP ]###############################

if [ ! -f /torrents/config/rutorrent/html/.htpasswd ]; then
    printf "${RUTORRENT_USER}:$(openssl passwd -crypt ${RUTORRENT_PASSWORD})\n" >> //torrents/config/rutorrent/html/.htpasswd && chmod 755 /torrents/config/rutorrent/html/.htpasswd
    rm -rf /torrents/config/rutorrent/html/index.php
fi

###########################[ PERMISSIONS ]###############################
# Make it so users can see /torrents/home
sed -i 's/true/false/g' /torrents/config/rutorrent/html/plugins/_getdir/conf.php

# Don't chown -R /torrents/home !
ls -d /torrents/* | grep -v home | xargs -d "\n" chown -R nginx:nginx
chown -R nginx:nginx /var/cache/nginx

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
fi

exec /usr/bin/supervisord -n -c /etc/supervisord.conf