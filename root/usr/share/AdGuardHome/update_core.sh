#!/bin/sh

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
binpath="/usr/bin/AdGuardHome"
update_mode=$1

upxflag=$(uci get AdGuardHome.AdGuardHome.upxflag 2>/dev/null || true)
[ -z "${upxflag}" ] && upxflag=off
enabled=$(uci get AdGuardHome.AdGuardHome.enabled 2>/dev/null || true)
core_version=$(uci get AdGuardHome.AdGuardHome.core_version 2>/dev/null || true)
update_url=$(uci get AdGuardHome.AdGuardHome.update_url 2>/dev/null || true)

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

	if [ -f "${binpath}" ]; then
		Current_Version="$(${binpath} --version 2>/dev/null | egrep -o "v[0-9].+[0-9]" | sed -r 's/(.*), c(.*)/\1/')"
	else
		Current_Version="unknown"
	fi
	[ -z "${Current_Version}" ] && Current_Version="unknown"

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

UPX_Compress(){
	GET_Arch
	upx_name="upx-${upx_latest_ver}-${Arch_upx}_linux.tar.xz"
	echo -e "开始下载 ${upx_name} ...\n"
	$Downloader /tmp/upx-${upx_latest_ver}-${Arch_upx}_linux.tar.xz "https://github.com/upx/upx/releases/download/v${upx_latest_ver}/${upx_name}"
	if [ ! -e "/tmp/upx-${upx_latest_ver}-${Arch_upx}_linux.tar.xz" ]; then
		echo -e "\n${upx_name} 下载失败!\n" 
		EXIT 1
	else
		echo -e "\n${upx_name} 下载成功!\n" 
	fi
	if ! command -v xz >/dev/null 2>&1; then
		echo "xz not found, attempting to install..." >&2
		opkg update >/dev/null 2>&1 || true
		opkg install xz >/dev/null 2>&1 || { echo "软件包 xz 安装失败!" >&2; EXIT 1; }
	fi
	mkdir -p /tmp/upx-${upx_latest_ver}-${Arch_upx}_linux
	echo -e "正在解压 ${upx_name} ...\n" 
	xz -d -c /tmp/upx-${upx_latest_ver}-${Arch_upx}_linux.tar.xz | tar -x -C "/tmp"
	[ ! -f "/tmp/upx-${upx_latest_ver}-${Arch_upx}_linux/upx" ] && echo -e "\n${upx_name} 解压失败!" && EXIT 1
}

Update_Core(){
	rm -rf "/tmp/AdGuardHome_Update" > /dev/null 2>&1
	mkdir -p "/tmp/AdGuardHome_Update" || { echo "无法创建临时目录"; EXIT 1; }

	GET_Arch
	eval link="${update_url}"
	echo "Download link: ${link}"
	echo "File name: ${link##*/}"
	echo "Downloading AdGuardHome core ..."

	if ! $Downloader "/tmp/AdGuardHome_Update/${link##*/}" "${link}"; then
		echo "Download failed."
		rm -rf "/tmp/AdGuardHome_Update"
		EXIT 1
	fi

	if [ "${link##*.}" = "gz" ]; then
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
	else
		downloadbin="/tmp/AdGuardHome_Update/${link##*/}"
	fi

	chmod +x "${downloadbin}" 2>/dev/null || true
	echo "Core size: $(awk 'BEGIN{printf "%.2fMB\n",'$((`ls -l $downloadbin | awk '{print $5}'`))'/1000000}')"

	if [ "${upxflag}" != "off" ]; then
		UPX_Compress
		echo "UPX compression enabled, this may take a while ..."
		/tmp/upx-${upx_latest_ver}-${Arch_upx}_linux/upx $upxflag $downloadbin > /dev/null 2>&1
		echo "\n压缩后的核心体积: $(awk 'BEGIN{printf "%.2fMB\n",'$((`ls -l $downloadbin | awk '{print $5}'`))'/1000000}')"
	else
		echo "UPX compression disabled, skipping ..."
	fi

	/etc/init.d/AdGuardHome stop > /dev/null 2>&1
	echo "Moving AdGuardHome binary to ${binpath%/*} ..."

	if ! mv -f "${downloadbin}" "${binpath}"; then
		echo -e "AdGuardHome 核心移动失败!\n可能是设备空间不足导致, 请尝试开启 UPX 压缩。"
		rm -rf "/tmp/AdGuardHome_Update"
		EXIT 1
	fi

	rm -f /tmp/upx*.tar.xz
	rm -rf /tmp/upx* /tmp/AdGuardHome_Update
	chmod +x ${binpath}

	if [ "${enabled}" = 1 ]; then
		echo "Restarting AdGuardHome service ..."
		/etc/init.d/AdGuardHome restart
	fi

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
	case "${Archt}" in
	mipsel)
		Arch_upx="mipsel"
		upx_latest_ver="3.95"
	;;
	*)
		Arch_upx="${Arch}"
		upx_latest_ver="$(${_Downloader} https://api.github.com/repos/upx/upx/releases/latest 2>/dev/null | egrep 'tag_name' | egrep '[0-9.]+' -o 2>/dev/null)"

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
rm - rf /var/run/update_core_error 2>/dev/null

main
