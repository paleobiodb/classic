#!/bin/bash
# . /data/Wing/bin/dataapps.sh
export WING_APP=/data/MyApp
export WING_CONFIG=/data/MyApp/etc/wing.conf
export WING_HOME=/data/Wing
export PATH=/data/Wing/bin:$PATH

cd /data/MyApp/logs

touch access_log
chown www-data access_log
chgrp www-data access_log

touch wing_web_errors.log
chown www-data wing_web_errors.log
chgrp www-data wing_web_errors.log

touch pbdb_classic.log
chown www-data pbdb_classic.log
chgrp www-data pbdb_classic.log

cd /data/MyApp/bin

if [ $UID == 0 ] 
  then
	echo "switching root to www-data"
	export RUNAS="--user www-data --group www-data"
fi

start_server --port 6001 -- starman --workers 2 $RUNAS --preload-app web.psgi

