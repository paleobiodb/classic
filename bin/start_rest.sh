#!/bin/bash
# . /data/Wing/bin/dataapps.sh
export WING_HOME=/data/Wing
export WING_APP=/data/MyApp
export WING_CONFIG=/data/MyApp/etc/wing.conf

export PATH=/data/Wing/bin:$PATH
export ANY_MOOSE=Moose

cd /data/MyApp/logs

touch rest_log
chown www-data rest_log
chgrp www-data rest_log

touch wing_rest_errors.log
chown www-data wing_rest_errors.log
chgrp www-data wing_rest_errors.log

cd /data/MyApp/bin

if [ $UID == 0 ] 
  then
	echo "switching root to www-data"
	export RUNAS="--user www-data --group www-data"
fi

start_server --port 6000 -- starman --workers 2 $RUNAS --preload-app rest.psgi

