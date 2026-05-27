#!/bin/sh

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
binpath="/usr/bin/AdGuardHome"
update_mode=$1

core_version=$(uci get adguardhome.config.core_version 2>/dev/null || echo "latest")

case "${core_version}" in
beta)
	core_api_url=https://api.github.com/repos/AdguardTeam/AdGuardHome/releases
	;;
*)
	core_api_url=https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest
	;;
esac

Check_Task(){
	running_tasks="$(ps w | grep -v grep | grep 'AdGuardHome' | grep 'update_core' | wc -l)"
	case $1 in
	force)
		echo "Force update requested"
		echo "Killing ${running_tasks} running tasks ..."
		ps w | grep -v grep | grep -v $$ | grep 'AdGuardHome' | grep 'update_core' | awk '{print $1}' | xargs kill -9 2>/dev/null
		;;
	*)
		[ "${running_tasks}" -gt 2 ] && echo -e "There are ${running_tasks} update tasks already running. Please wait or stop them manually." && EXIT 2
		;;
	esac
}

Check_Downloader() {
	if command -v curl >/dev/null 2>&1; then
		PKG="curl"
		return
	fi

	if command -v wget >/dev/null 2>&1; then
		PKG="wget"
		return
	fi

	echo "Neither curl nor wget is installed, cannot check updates!" >&2
	EXIT 1
}

Check_Updates(){
	Check_Downloader
	GET_Arch
	case "${PKG}" in
	curl)
		Downloader="curl -L -k -o"
		_Downloader="curl -s"
	;;
	wget)
		Downloader="wget --no-check-certificate -T 5 -O"
		_Downloader="wget -q -O -"
	;;
	esac
	echo "[${PKG}] Checking for updates ..."
	
	Cloud_Version="$(${_Downloader} ${core_api_url} 2>/dev/null | grep 'tag_name' | egrep -o "v[0-9].+[0-9.]" | awk 'NR==1')"
	if [ -z "${Cloud_Version}" ]; then
		echo "Failed to check updates, please check network." >&2
		EXIT 1
	fi

	update_url=$(uci get adguardhome.config.update_url 2>/dev/null)
	if [ -z "${update_url}" ]; then
		update_url='https://github.com/AdguardTeam/AdGuardHome/releases/download/${Cloud_Version}/AdGuardHome_linux_${Arch}.tar.gz'
	fi

	eval link="${update_url}"

	if [ -f "${binpath}" ]; then
		Raw_Ver="$(${binpath} --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
		if [ -n "${Raw_Ver}" ]; then
			Current_Version="v${Raw_Ver}"
		else
			Current_Version="unknown"
		fi
	else
		Current_Version="unknown"
	fi

	echo "Binary path: ${binpath%/*}"
	echo "Current version: ${Current_Version}"
	echo "Latest version: ${Cloud_Version}"

	if [ ! "${Cloud_Version}" = "${Current_Version}" ] || [ "$1" = force ]; then
		Update_Core || EXIT 1
	else
		echo "Already up to date."
		EXIT 0
	fi
	EXIT 0
}

Update_Core(){
	rm -rf "/tmp/AdGuardHome_Update" > /dev/null 2>&1
	mkdir -p "/tmp/AdGuardHome_Update" || { echo "无法创建临时目录"; EXIT 1; }

	echo "Download link: ${link}"
	echo "File name: ${link##*/}"
	echo "Downloading AdGuardHome core ..."

	if ! $Downloader "/tmp/AdGuardHome_Update/${link##*/}" "${link}"; then
		echo "Download failed."
		rm -rf "/tmp/AdGuardHome_Update"
		EXIT 1
	fi

	echo "Extracting AdGuardHome ..."
	if ! tar -zxf "/tmp/AdGuardHome_Update/${link##*/}" -C "/tmp/AdGuardHome_Update/"; then
		echo "Extraction failed!"
		rm -rf "/tmp/AdGuardHome_Update"
		EXIT 1
	fi
	
	if [ ! -e "/tmp/AdGuardHome_Update/AdGuardHome/AdGuardHome" ]; then
		echo "Extraction failed: binary not found!"
		rm -rf "/tmp/AdGuardHome_Update"
		EXIT 1
	fi
	downloadbin="/tmp/AdGuardHome_Update/AdGuardHome/AdGuardHome"

	chmod +x "${downloadbin}" 2>/dev/null || true
	echo "Core size: $(awk 'BEGIN{printf "%.2fMB\n",'$((`ls -l $downloadbin | awk '{print $5}'`))'/1000000}')"

	# 先盲停，静音掉可能存在的 procd 报错
	/etc/init.d/adguardhome stop > /dev/null 2>&1
	echo "Moving AdGuardHome binary to ${binpath%/*} ..."

	if ! mv -f "${downloadbin}" "${binpath}"; then
		echo -e "AdGuardHome 核心移动失败!\n可能是设备空间不足导致。"
		rm -rf "/tmp/AdGuardHome_Update"
		EXIT 1
	fi

	rm -rf /tmp/AdGuardHome_Update
	chmod +x ${binpath}

	echo "Restarting AdGuardHome service ..."
	/etc/init.d/adguardhome restart > /dev/null 2>&1

	echo "AdGuardHome core updated successfully!"
	touch /var/run/update_core_done
}

GET_Arch() {
	Archt="$(uname -m)"
	case "${Archt}" in
	i386|i686)
		Arch="i386"
	;;
	x86_64|amd64)
		Arch="amd64"
	;;
	mipsel|mipsel*)
		Arch="mipsle_softfloat"
	;;
	mips|mips*)
		Arch="mips_softfloat"
	;;
	mips64el)
		Arch="mips64le_softfloat"
	;;
	mips64)
		Arch="mips64_softfloat"
	;;
	armv5*|armv5l|armv5tel)
		Arch="armv5"
	;;
	armv6*|armv6l)
		Arch="armv6"
	;;
	armv7*|armv7l)
		Arch="armv7"
	;;
	arm|armhf)
		Arch="armv7"
	;;
	aarch64)
		Arch="arm64"
	;;
	*)
		echo "Unsupported architecture: [${Archt}]" 
		EXIT 1
	esac
	echo "Detected architecture: ${Arch}"
}

EXIT(){
	rm -rf /var/run/update_core $LOCKU 2>/dev/null
	[ "$1" != 0 ] && touch /var/run/update_core_error
	exit $1
}

main(){
	Check_Task ${update_mode}
	Check_Updates ${update_mode}
}

trap "EXIT 1" SIGTERM SIGINT
touch /var/run/update_core
rm -rf /var/run/update_core_error 2>/dev/null

main
