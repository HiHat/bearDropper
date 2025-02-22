#!/bin/sh
# https://github.com/marjancinober/bearDropper
# forked from https://github.com/robzr/bearDropper
# bearDropper install script - @marjancinober

if [ -f /etc/init.d/bearDropper ] ; then
  echo Detected previous version of bearDropper - stopping
  /etc/init.d/bearDropper stop
fi
echo -e 'Retrieving and installing latest version'
wget -qO /etc/init.d/bearDropper https://raw.githubusercontent.com/marjancinober/bearDropper/master/src/init.d/bearDropper 
wget -qO /etc/config/bearDropper https://raw.githubusercontent.com/marjancinober/bearDropper/master/src/config/bearDropper
wget -qO /usr/sbin/bearDropper https://raw.githubusercontent.com/marjancinober/bearDropper/master/bearDropper
chmod 755 /usr/sbin/bearDropper /etc/init.d/bearDropper
echo -e 'Processing historical log data (this can take a while)'
/usr/sbin/bearDropper -m entire -f stdout
echo -e 'Starting background process'
/etc/init.d/bearDropper enable
/etc/init.d/bearDropper start

dropbear_count=$(uci show dropbear | grep -c =dropbear)
dropbear_count=$((dropbear_count - 1))
dropbear_conf_updated=
for instance in $(seq 0 $dropbear_count); do
  dropbear_verbose=$(uci -q get dropbear.@dropbear[$instance].verbose || echo 0)
  if [ $dropbear_verbose -eq 0 ]; then
    uci set dropbear.@dropbear[$instance].verbose=1 
    echo "dropbear.@dropbear[$instance].verbose=1 logging was configured, restart..."
    dropbear_conf_updated=yes
  fi
done
[ $dropbear_conf_updated ] && {
    uci commit
    /etc/init.d/bearDropper restart
}
