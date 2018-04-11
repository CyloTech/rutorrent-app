#!/usr/bin/env bash
set -x
###########################[ SUPERVISOR SCRIPTS ]###############################

if [ ! -f /etc/app_configured ]; then
    mkdir -p /etc/supervisor/conf.d
cat << EOF >> /etc/supervisor/conf.d/initplugins.conf
[program:initplugins]
command=/usr/local/bin/php /var/www/html/php/initplugins.php
autostart=true
autorestart=false
priority=1
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF >> /etc/supervisor/conf.d/rtorrent.conf
[program:rtorrent]
command=/bin/su -s /bin/bash -c "TERM=xterm rtorrent" nginx
autostart=true
autorestart=true
priority=2
stdout_events_enabled=false
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF >> /etc/supervisor/conf.d/irssi.conf
[program:irssi]
command=/bin/su -s /bin/bash -c "TERM=xterm irssi" nginx
autostart=true
autorestart=true
priority=3
stdout_events_enabled=false
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
fi

###########################[ IRSSI SETUP ]###############################
# Set up .autodl dir, and allow for configs to be saved.
if [ ! -d /torrents/config/rtorrent/autodl ]
then
    echo "Did not find /torrents/config/rtorrent/autodl existed. Creating it."
    mkdir -p /torrents/config/rtorrent/autodl
fi

if [ ! -h /var/cache/nginx/.autodl ]
then
	echo "Linking autodl config directory to /torrents/config/rtorrent/autodl."
	ln -s /torrents/config/rtorrent/autodl /var/cache/nginx/.autodl
else
	echo "Do not need to relink the autodl config directory."
fi

if [ -f /torrents/config/rtorrent/autodl/autodl.cfg ]
then
	echo "Found an existing autodl configs. Will not reinitialize."
	irssi_port=$(grep gui-server-port /torrents/config/rtorrent/autodl/autodl2.cfg | awk '{print $3}')
	irssi_pass=$(grep gui-server-password /torrents/config/rtorrent/autodl/autodl2.cfg | awk '{print $3}')
else
	echo "Need to set up a new autodl install."

	irssi_pass=$(perl -le 'print map {(a..z,A..Z,0..9)[rand 62] } 0..pop' 15)
	irssi_port=$((RANDOM%64025+1024))
	
	echo "Creating necessary configuration files ... "
cat << EOF >> /torrents/config/rtorrent/autodl/autodl.cfg
[options]
gui-server-port = ${irssi_port}
gui-server-password = ${irssi_pass}
EOF
fi

# Install the web plugin.
if [ ! -d /var/www/html/plugins/autodl-irssi ]	
then
	echo "Installing web plugin portion."
	# Web plugin setup.
	cd /var/www/html/plugins/
	git clone https://github.com/autodl-community/autodl-rutorrent.git autodl-irssi > /dev/null 2>&1
	cd autodl-irssi
	cp _conf.php conf.php
	sed -i "s/autodlPort = 0;/autodlPort = ${irssi_port};/" conf.php
	sed -i "s/autodlPassword = \"\";/autodlPassword = \"${irssi_pass}\";/" conf.php
	sed -i 's/$defaultTheme = ""/$defaultTheme = "club-QuickBox"/g' /var/www/html/plugins/theme/conf.php
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

if [ ! -f /etc/app_configured ]; then
    cp /sources/.rtorrent.rc /torrents/config/rtorrent/.rtorrent.rc
    ln -s /torrents/config/rtorrent/.rtorrent.rc /var/cache/nginx/
    sed -i 's#LISTENING_PORT#'${LISTENING_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#DHT_PORT#'${DHT_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#http://mydomain.com#'${EXTERNAL_DOMAIN}'/no-auth#g' /var/www/html/plugins/fileshare/conf.php
fi

rm -f /torrents/config/rtorrent/session/rtorrent.lock
###########################[ NGINX SETUP ]###############################

if [ ! -f /etc/app_configured ]; then
    printf "${RUTORRENT_USER}:$(openssl passwd -crypt ${RUTORRENT_PASSWORD})\n" >> /var/www/html/.htpasswd && chmod 755 /var/www/html/.htpasswd
    rm -rf /var/www/html/index.php
fi

###########################[ PERMISSIONS ]###############################

chown -R nginx:nginx /torrents
chown -R nginx:nginx /var/cache/nginx
chown -R nginx:nginx /var/www/html

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
fi

exec "$@"
