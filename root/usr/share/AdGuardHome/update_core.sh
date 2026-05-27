#!/bin/sh

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
binpath="/usr/bin/AdGuardHome"
update_mode=$1

# 每次执行前，立即清理旧的错误标志文件
rm -f /var/run/update_core_error 2>/dev/null

core_version=$(uci get adguardhome.config.core_version 2>/dev/null || echo "latest")

case "${core_version}" in
beta)
        core_api_url=https://api.github.com/repos/AdguardTeam/AdGuardHome/releases
        ;;
*)
        core_api_url=https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest
        ;;
esac

# 【核心整改】安全锁清理函数。名字绝对不包含关键字 EXIT，杜绝 BusyBox ash 系统保留字冲突
cleanup_lockfile() {
        rm -f /var/run/update_core 2>/dev/null
}

Check_Task(){
        running_tasks="$(ps w | grep -v grep | grep 'update_core\.sh' | wc -l)"
        case $1 in
        force)
                echo "Force update requested. Cleaning up old tasks..."
                ps w | grep -v grep | grep -v $$ | grep 'update_core\.sh' | awk '{print $1}' | xargs kill -9 2>/dev/null
                rm -f /var/run/update_core 2>/dev/null
                ;;
        *)
                # 【对齐运行锁】如果锁存在或有其它实例运行
                if [ -f /var/run/update_core ] || [ "${running_tasks}" -gt 2 ]; then
                        echo "There are update tasks already running. Please wait."
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
        touch /var/run/update_core_error 2>/dev/null
        cleanup_lockfile
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
                touch /var/run/update_core_error 2>/dev/null
                cleanup_lockfile
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

        if [ ! "${Cloud_Version}" = "${Current_Version}" ] || [ "$1" = "force" ]; then
                echo "New version detected or force update enabled. Starting update process..."
                if Update_Core; then
                        echo "AdGuardHome core updated successfully!"
                        cleanup_lockfile
                        exit 0
                else
                        touch /var/run/update_core_error 2>/dev/null
                        cleanup_lockfile
                        exit 1
                fi
        else
                echo "Already up to date."
                cleanup_lockfile
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

        echo "Stopping AdGuardHome service ..."
        /etc/init.d/adguardhome stop > /dev/null 2>&1
        echo "Moving AdGuardHome binary to ${binpath%/*} ..."

        if ! mv -f "${downloadbin}" "${binpath}"; then
                echo "Failed to move binary! Out of space?"
                rm -rf "/tmp/AdGuardHome_Update"
                /etc/init.d/adguardhome start > /dev/null 2>&1
                return 1
        fi

        rm -rf /tmp/AdGuardHome_Update
        chmod +x ${binpath}

        echo "Restarting AdGuardHome service ..."
        /etc/init.d/adguardhome restart > /dev/null 2>&1
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
        *) echo "Unsupported architecture: [${Archt}]"; touch /var/run/update_core_error 2>/dev/null; cleanup_lockfile; exit 1 ;;
        esac
        echo "Detected architecture: ${Arch}"
}

# --- 脚本主执行区 ---
Check_Task "${update_mode}"

cleanup_lockfile() {
    rm -f /var/run/update_core 2>/dev/null
}
trap 'cleanup_lockfile' EXIT

# 针对突发中断信号（兜底）
trap 'cleanup_lockfile; exit 1' SIGINT SIGTERM

touch /var/run/update_core 2>/dev/null
rm -f /var/run/update_core_error 2>/dev/null


Check_Updates "${update_mode}"
