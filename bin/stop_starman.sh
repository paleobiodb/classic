#!/bin/bash
. /data/Wing/bin/dataapps.sh
cd /data/MyApp/bin
export WING_CONFIG=/data/MyApp/etc/wing.conf
killall start_server
