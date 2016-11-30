#!/bin/bash
# . /data/Wing/bin/dataapps.sh
export WING_APP=/data/MyApp
export WING_CONFIG=/data/MyApp/etc/wing.conf
export WING_HOME=/data/Wing
export PATH=/data/Wing/bin:$PATH
cd /data/MyApp/bin

if [ $UID == 0 ] 
  then
	echo "switching root to nobody"
	export RUNAS="--user nobody --group nobody"
fi

start_server --port 6001 -- starman --workers 2 $RUNAS --preload-app web.psgi

