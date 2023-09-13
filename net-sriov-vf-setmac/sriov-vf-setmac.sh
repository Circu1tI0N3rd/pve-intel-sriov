#!/usr/bin/env bash

if [ $# -lt 2 ]; then
	echo "Missing arguments: <interface> <config-path>"
	exit 1
fi

inf=$1
path=$2
force=/bin/false

if [ $# -eq 3 && "$3" = "-f" ]; then
	force=/bin/true
fi
if [ -f ${path}/${inf}.conf ]; then
	path=${path}/${inf}.conf
else
	echo "No matching config file for interface ${inf}"
	exit 1
fi

. $path

maccurr=(`/usr/sbin/ip link show ${inf} | /usr/bin/grep "vf" | awk '{print $4}'`)

for VF in ${VFS[@]}; do
	idx=`echo ${VF} | tr -d -c 0-9`
	mac=${!VF}
	if [ "${maccurr[$idx]}" = "${mac}" ]; then
		echo "Skip: Virtual function ${idx} MAC address is recent (${maccurr[$idx]})."
		continue
	elif [ "${maccurr[$idx]}" = "00:00:00:00:00:00" ]; then
		echo "Update: Virtual function ${idx} MAC address sets to ${mac}."
	elif [ $force ]; then
		echo "Change: Virtual function ${idx} MAC address sets to ${mac} (previous: ${maccurr[$idx]})."
	else
		echo "Skip: Virtual function ${idx} is active; won't change."
		continue
	fi
	/usr/sbin/ip link set ${inf} vf ${idx} mac ${mac}
done
exit 0
