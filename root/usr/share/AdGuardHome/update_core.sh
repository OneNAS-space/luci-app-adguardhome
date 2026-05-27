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

# 【全局安全退出钩子】确保任何出口都能精准清理锁文件
exit_handler() {
        exit_code=$?
        rm -f /var/run/update_core 2>/dev/null
        if [ "$exit_code" -ne 0 ]; then
                touch /var/run/update_core_error 2>/dev/null
        fi
}

Check_Task(){
        running_tasks="$(ps w | grep -v grep | grep 'AdGuardHome' | grep 'update_core\.sh' | wc -l)"
        case $1 in
        force)
                echo "Force update requested."
                echo "Killing running tasks ..."
                ps w | grep -v grep | grep -v $$ | grep 'AdGuardHome' | grep 'update_core' | awk '{print $1}' | xargs kill -9 2>/dev/null
                ;;
        *)
                if [ "${running_tasks}" -gt 2 ]; then
                        echo "There are update tasks already running. Please wait."
                        # 避免退出时误删正在运行的另一个主任务的锁
                        trap - EXIT
                        exit 2
                fi
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
        exit 1
}

Check_Updates(){
        Check_Downloader
        GET_Arch
        case "${PKG}" in
        curl)
                Downloader="curl -L -k --connect-timeout 10 -m 300 -o"
                _Downloader="curl -s --connect-timeout 5 -m 15"
        ;;
        wget)
                Downloader="wget --no-check-certificate -T 15 -O"
                _Downloader="wget -q -T 10 -O -"
        ;;
        esac
        echo "[${PKG}] Checking for updates ..."

        Cloud_Version="$(${_Downloader} ${core_api_url} 2>/dev/null | grep 'tag_name' | egrep -o "v[0-9].+[0-9.]" | awk 'NR==1')"
        if [ -z "${Cloud_Version}" ]; then
                echo "Failed to check updates, please check network or GitHub API connectivity." >&2
                exit 1
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

        echo "Binary path: ${binpath}"
        echo "Current version: ${Current_Version}"
        echo "Latest version: ${Cloud_Version}"

        if [ ! "${Cloud_Version}" = "${Current_Version}" ] || [ "$1" = force ]; then
                echo "New version detected or force update enabled. Starting update process..."
                Update_Core || exit 1
                exit 0
        else
                echo "Already up to date."
                exit 0
        fi
}

Update_Core(){
        rm -rf "/tmp/AdGuardHome_Update" > /dev/null 2>&1
        mkdir -p "/tmp/AdGuardHome_Update" || { echo "Failed to create temp dir"; return 1; }

        echo "Download link: ${link}"
        echo "Downloading AdGuardHome core ..."

        if ! $Downloader "/tmp/AdGuardHome_Update/${link##*/}" "${link}"; then
                echo "Download failed."
                rm -rf "/tmp/AdGuardHome_Update"
                return 1
        fi

        echo "Extracting AdGuardHome ..."
        if ! tar -zxf "/tmp/AdGuardHome_Update/${link##*/}" -C "/tmp/AdGuardHome_Update/"; then
                echo "Extraction failed!"
                rm -rf "/tmp/AdGuardHome_Update"
                return 1
        fi

        if [ ! -e "/tmp/AdGuardHome_Update/AdGuardHome/AdGuardHome" ]; then
                echo "Extraction failed: binary not found!"
                rm -rf "/tmp/AdGuardHome_Update"
                return 1
        fi
        downloadbin="/tmp/AdGuardHome_Update/AdGuardHome/AdGuardHome"

        chmod +x "${downloadbin}" 2>/dev/null || true

        core_size=$(ls -lh "$downloadbin" | awk '{print $5}')
        echo "Core size: ${core_size}"

        /etc/init.d/adguardhome stop > /dev/null 2>&1
        echo "Moving AdGuardHome binary to ${binpath%/*} ..."

        if ! mv -f "${downloadbin}" "${binpath}"; then
                echo "Failed to move binary! Out of space?"
                rm -rf "/tmp/AdGuardHome_Update"
                return 1
        fi

        rm -rf /tmp/AdGuardHome_Update
        chmod +x ${binpath}

        echo "Restarting AdGuardHome service ..."
        /etc/init.d/adguardhome restart > /dev/null 2>&1

        echo "AdGuardHome core updated successfully!"
        return 0
}

GET_Arch() {
        Archt=$(uname -m)
        case "${Archt}" in
        i386|i686) Arch="i386" ;;
        x86_64|amd64) Arch="amd64" ;;
        mipsel|mipsel*) Arch="mipsle_softfloat" ;;
        mips|mips*) Arch="mips_softfloat" ;;
        mips64el) Arch="mips64le_softfloat" ;;
        mips64) Arch="mips64_softfloat" ;;
        armv5*|armv5l|armv5tel) Arch="armv5" ;;
        armv6*|armv6l) Arch="armv6" ;;
        armv7*|armv7l) Arch="armv7" ;;
        arm|armhf) Arch="armv7" ;;
        aarch64) Arch="arm64" ;;
        *) echo "Unsupported architecture: [${Archt}]"; exit 1 ;;
        esac
        echo "Detected architecture: ${Arch}"
}

main(){
        Check_Task ${update_mode}
        # 【核心修正】通过本地校验后，在发起耗时的网络请求前立刻落锁，与前端同步
        touch /var/run/update_core 2>/dev/null
        trap exit_handler EXIT SIGTERM SIGINT
        Check_Updates ${update_mode}
}

rm -f /var/run/update_core_error 2>/dev/null
main
