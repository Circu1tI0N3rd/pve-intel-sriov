#!/usr/bin/env bash

if [ $# -lt 2 ]; then
	echo "Missing arguments: <interface> <config-path>"
	exit 1
fi

envfn=$1
path=$2
force=/bin/false

if [ $# -eq 3 && "$3" = "-f" ]; then
	force=/bin/true
fi
if [ -f ${path}/${envfn}.conf ]; then
	path=${path}/${envfn}.conf
else
	echo "No matching config file for interface with address ${envfn}"
	exit 1
fi

# Find interface from MAC
pfmac=${envfn//-/:}
inf=
# Find interface name from $pfmac
for sysif in $(ls -1 /sys/class/net); do
	if [ -f /sys/class/net/${sysif}/address -a -f /sys/class/net/${sysif}/addr_assign_type ]; then
		if [ "$(cat /sys/class/net/${sysif}/address)" = "${pfmac}" ]; then
			# check interface does not steal address from another (notably bridges)
			if [ `cat /sys/class/net/${sysif}/addr_assign_type` -ne 3 ]; then
				inf=${sysif}
				break
			fi
		fi
	fi
done

. $path

maccurr=(`/usr/sbin/ip link show ${inf} | /usr/bin/grep "vf" | awk '{print $4}'`)

for VF in ${VFS[@]}; do
	idx=`echo ${VF} | tr -d -c 0-9`
	mac=${!VF}
	
	if [ -n "${mac}" ]; then
		echo "Skip: Virtual function's MAC address is unspecified."
		continue
	elif [ "${maccurr[$idx]}" = "${mac}" ]; then
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
