#!/bin/sh

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
logread -e AdGuardHome > /tmp/adguardhometmp.log
logread -e AdGuardHome -f >> /tmp/adguardhometmp.log &
pid=$!
echo "1">/var/run/adguardhomesyslog
while true
do
	sleep 12
	watchdog=$(cat /var/run/adguardhomesyslog)
	if [ "$watchdog"x == "0"x ]; then
		kill $pid
		rm /tmp/adguardhometmp.log
		rm /var/run/adguardhomesyslog
		exit 0
	else
		echo "0">/var/run/adguardhomesyslog
	fi
done
