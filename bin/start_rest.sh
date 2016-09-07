#!/bin/bash
. /data/Wing/bin/dataapps.sh
export WING_APP=/data/MyApp
export WING_CONFIG=/data/MyApp/etc/wing.conf
cd /data/MyApp/bin

if [ $UID == 0 ] 
  then
	echo "switching root to nobody"
	export RUNAS="--user nobody --group nobody"
fi

start_server --port 5000 -- starman --workers 2 $RUNAS --preload-app rest.psgi

