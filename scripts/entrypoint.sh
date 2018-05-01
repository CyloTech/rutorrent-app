#!/usr/bin/env bash
set -x
###########################[ COPY TO MOUNTS ]###############################

if [ ! -d /torrents/config/rutorrent/html ]; then
    echo "Did not find /torrents/config/rutorrent/html existed. Creating it and copying rutorrent into."
    mkdir -p /torrents/config/rutorrent/html
    cp -avr /sources/html/* /torrents/config/rutorrent/html/
fi

# Remove in this version! we need to reset them all!
if [[ $(grep 'method.insert = d.move_to_complete, simple, "d.directory.set=$argument.1=; execute=mkdir,-p,$argument.1=; execute=mv,-f,$argument.0=,$argument.1=; d.save_full_session=;d.stop=;d.start="' /torrents/config/rtorrent/.rtorrent.rc) ]]; then
    rm -f /torrents/config/rtorrent/.rtorrent.rc
fi

###########################[ SUPERVISOR SCRIPTS ]###############################

if [ ! -d /etc/supervisor/conf.d ]; then
    mkdir -p /etc/supervisor/conf.d
cat << EOF >> /etc/supervisor/conf.d/initplugins.conf
[program:initplugins]
command=
command=/bin/su -s /bin/bash -c "TERM=xterm /usr/local/bin/php /torrents/config/rutorrent/html/php/initplugins.php" nginx
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
command=/bin/su -s /bin/bash -c "TERM=xterm /var/cache/nginx/.local/rtorrent/0.9.6-PS-1.1-dev/bin/rtorrent-extended" nginx
autostart=true
autorestart=true
priority=2
stdout_events_enabled=false
stderr_events_enabled=true
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
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF >> /etc/supervisor/conf.d/rtorrent-log.conf

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
	irssi_port=$(grep gui-server-port /torrents/config/rtorrent/autodl/autodl.cfg | awk '{print $3}')
	irssi_pass=$(grep gui-server-password /torrents/config/rtorrent/autodl/autodl.cfg | awk '{print $3}')
else
	echo "Need to set up a new autodl install."

	irssi_pass=$(perl -le 'print map {(a..z,A..Z,0..9)[rand 62] } 0..pop' 15)
	irssi_port=$((RANDOM%64025+1024))
	
	echo "Creating necessary configuration files ... "
cat << EOF >> /torrents/config/rtorrent/autodl/autodl.cfg
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

if [ ! -d /torrents/config/rutorrent/users/${RUTORRENT_USER}/torrents ]
    then
    mkdir -p /torrents/config/rutorrent/users/${RUTORRENT_USER}/torrents
fi

if [ ! -f /torrents/config/rtorrent/.rtorrent.rc ]
    then
    cp /sources/.rtorrent.rc /torrents/config/rtorrent/.rtorrent.rc
    ln -s /torrents/config/rtorrent/.rtorrent.rc /var/cache/nginx/
    sed -i 's#LISTENING_PORT#'${LISTENING_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#DHT_PORT#'${DHT_PORT}'#g' /torrents/config/rtorrent/.rtorrent.rc
    sed -i 's#http://mydomain.com#'${EXTERNAL_DOMAIN}'/no-auth#g' /torrents/config/rutorrent/html/plugins/fileshare/conf.php
    sed -i 's#300#30#g' /torrents/config/rutorrent/html/plugins/autotools/conf.php
    sed -i 's/$defaultTheme = ""/$defaultTheme = "club-QuickBox"/g' /torrents/config/rutorrent/html/plugins/theme/conf.php
    mkdir -p '/torrents/config/rutorrent/users/'${RUTORRENT_USER}'/settings/'
    cp /sources/autotools.dat '/torrents/config/rutorrent/users/'${RUTORRENT_USER}'/settings/autotools.dat'
fi

if [ ! -f /var/cache/nginx/.rtorrent.rc ]
    then
    ln -s /torrents/config/rtorrent/.rtorrent.rc /var/cache/nginx/
fi

rm -f /torrents/config/rtorrent/session/rtorrent.lock
###########################[ NGINX SETUP ]###############################

if [ ! -f /torrents/config/rutorrent/html/.htpasswd ]; then
    printf "${RUTORRENT_USER}:$(openssl passwd -crypt ${RUTORRENT_PASSWORD})\n" >> //torrents/config/rutorrent/html/.htpasswd && chmod 755 /torrents/config/rutorrent/html/.htpasswd
    rm -rf /torrents/config/rutorrent/html/index.php
fi

###########################[ PERMISSIONS ]###############################

# Don't chown -R /torrents/home !
ls -d /torrents/* | grep -v home | xargs -d "\n" chown -R nginx:nginx
chown -R nginx:nginx /var/cache/nginx

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
fi

exec "$@"
