require("luci.sys")
require("luci.util")
require("io")
local m, s, o, o1
local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()
local configpath = uci:get("AdGuardHome", "AdGuardHome", "configpath") or "/etc/AdGuardHome.yaml"
local binpath = uci:get("AdGuardHome", "AdGuardHome", "binpath") or "/usr/bin/AdGuardHome"
httpport = uci:get("AdGuardHome", "AdGuardHome", "httpport") or "3008"
m = Map("AdGuardHome", "AdGuard Home")
m.description = translate("Free and open source, powerful network-wide ads & trackers blocking DNS server.")
    .. [[<style>
    div[id^="cbid.AdGuardHome.AdGuardHome."] {
        display: flex;
        flex-wrap: wrap;
        gap: 1em;
    }
    div[id^="cbid.AdGuardHome.AdGuardHome."] .cbi-checkbox {
        display: inline-flex;
        align-items: center;
    }
    #cbi-AdGuardHome-AdGuardHome .cbi-value-field > br {
    display: none;
    }
    </style>]]
m:section(SimpleSection).template = "AdGuardHome/AdGuardHome_status"

s = m:section(TypedSection, "AdGuardHome")
s.anonymous = true
s.addremove = false
o = s:option(Flag, "enabled", translate("Enable"))
o.default = 0
o.optional = false
o = s:option(Value,"httpport",translate("WebUI management port"))
o.placeholder = 3008
o.default = 3008
o.datatype = "port"
o.optional = false
o.description = translate(
    "<input type='button' class='cbi-button cbi-button-link' "
    .. "style='width:210px;font-weight:bold;' "
    .. "value='AdGuardHome Web:" .. httpport .. "' "
    .. "onclick=\"window.open('http://' + window.location.hostname + ':' + " .. httpport .. ")\"/>"
)
local binmtime = uci:get("AdGuardHome", "AdGuardHome", "binmtime") or "0"
local e = ""
if not fs.access(configpath) then e = e .. " " .. translate("no config") end
if not fs.access(binpath) then
    e = e .. " " .. translate("no core")
else
    local version = uci:get("AdGuardHome", "AdGuardHome", "version")
    local testtime = fs.stat(binpath, "mtime")
    if testtime ~= tonumber(binmtime) or version == nil then
        version = luci.sys.exec(string.format("echo -n $(%s --version 2>&1 | awk -F 'version ' '{print $2}' | awk -F ',' '{print $1}')", binpath))
        if version == "" then version = "core error" end
        uci:set("AdGuardHome", "AdGuardHome", "version", version)
        uci:set("AdGuardHome", "AdGuardHome", "binmtime", testtime)
        uci:commit("AdGuardHome")
    end
    e = version .. e
end

o = s:option(ListValue, "core_version", translate("Core Branch"))
o:value("latest", translate("Latest Version"))
o:value("beta", translate("Beta Version"))
o.default = "latest"
o = s:option(Button, "restart", translate("Update Core-bin"))
o.inputtitle = translate("Update core-bin")
o.template = "AdGuardHome/AdGuardHome_check"
o.showfastconfig = (not fs.access(configpath))
o.description = string.format(translate("Current core version: ") .. "<strong><font id='updateversion' style='color:green'>%s </font></strong>", e)
local portcommand = "awk '/port:/ && ++count == 2 {sub(/[^0-9]+/, \"\", $2); printf(\"%s\\n\", $2); exit}' " .. configpath .. " 2>nul"
local port = luci.util.exec(portcommand)
if (port == "") then port = "?" end
o = s:option(ListValue, "redirect", port .. translate("Redirect"), translate("AdGuardHome redirect mode"))
-- o.placeholder = "none"
o:value("none", translate("No redirect"))
o:value("dnsmasq-upstream", translate("As the upstream server of dnsmasq"))
o:value("redirect", translate("Redirect port 53 to AdGuardHome"))
o:value("exchange", translate("Use port 53 to replace dnsmasq"))
o.default = "none"
o.optional = true
o = s:option(Value, "binpath", translate("Core-bin Path"), translate("AdGuardHome Core-bin Path. Auto-download if binary is not found."))
o.default = "/usr/bin/AdGuardHome"
o.datatype = "string"
o.optional = false
o.rmempty = false
o.readonly = true

o = s:option(ListValue, "upxflag", translate("UPX compress downloaded bin"))
o:value("", translate("none"))
o:value("-1", translate("Fast compression"))
o:value("-9", translate("Better compression"))
o:value("--best", translate("The best compression (large files may be slow)"))
o:value("--brute", translate("Try all possible compression methods and filters [slow]"))
o:value("--ultra-brute", translate("Try more variant compression methods [very slow]"))
o.default = ""
o.description = translate("Space Saving Option, but may lead to compatibility issues on some systems.")
o.rmempty = true
o = s:option(Value, "configpath", translate("Configuration File Path"), translate("AdGuardHome Configuration File Path"))
o.default = "/etc/AdGuardHome.yaml"
o.datatype = "string"
o.optional = false
o.rmempty = false
o.validate = function(self, value)
if value == nil then return nil end
if fs.stat(value,"type") == "dir" then
    fs.rmdir(value)
end
if fs.stat(value,"type") == "dir" then
    if m.message then
    m.message = m.message .. "\nerror!config path is a dir"
    else
    m.message = "error!config path is a dir"
    end
    return nil
end
return value
end
o = s:option(Value, "workdir", translate("Working Directory"), translate("This directory contains rules, audit logs, and the database."))
o.default = "/var/AdGuardHome"
o.datatype = "string"
o.optional = false
o.rmempty = false
o.validate = function(self, value)
if value == "" then return nil end
if fs.stat(value,"type") == "reg" then
    if m.message then
    m.message = m.message .. "\nerror!work dir is a file"
    else
    m.message = "error!work dir is a file"
    end
    return nil
end
if string.sub(value, -1) == "/" then
    return string.sub(value, 1, -2)
else
    return value
end
end
o = s:option(Value, "logfile", translate("Runtime Log File Path"), translate("Specify the path for runtime logs. Enter 'syslog' to write to the system log, or leave blank to disable logging."))
o.datatype = "string"
o.rmempty = true
o.validate = function(self, value)
if fs.stat(value,"type") == "dir" then
    fs.rmdir(value)
end
if fs.stat(value,"type") == "dir" then
    if m.message then
    m.message = m.message .. "\nerror!log file is a dir"
    else
    m.message = "error!log file is a dir"
    end
    return nil
end
return value
end
o = s:option(Flag, "verbose", translate("Verbose log"))
o.default = 0
o.optional = true
local a = luci.sys.call("grep -m 1 -q programadd " .. configpath)
if (a == 0) then
a = "Added"
else
a = "Not added"
end
o = s:option(Button,"gfwdel",translate("Del gfwlist"),translate(a))
o.optional = true
o.inputtitle = translate("Del")
o.write = function()
    luci.sys.exec("sh /usr/share/AdGuardHome/gfw2adg.sh del 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "AdGuardHome"))
end
o = s:option(Button,"gfwadd",translate("Add gfwlist"),translate(a))
o.optional = true
o.inputtitle = translate("Add")
o.write = function()
    luci.sys.exec("sh /usr/share/AdGuardHome/gfw2adg.sh 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "AdGuardHome"))
end
o = s:option(Value, "gfwupstream", translate("Gfwlist upstream dns server"), translate("Gfwlist domain upstream dns service")
.. translate(a))
o.default = "tcp://208.67.220.220:5353"
o.datatype = "string"
o.optional = true
o = s:option(Value, "hashpass", translate("Change WebUI management password"), translate("Press load calculate model and calculate finally save/apply"))
o.default = ""
o.datatype = "string"
o.template = "AdGuardHome/AdGuardHome_chpass"
o.optional = true
o = s:option(MultiValue, "upprotect", translate("File retention during upgrade"))
o:value("$binpath",translate("core-bin"))
o:value("$configpath",translate("config file"))
o:value("$logfile",translate("log file"))
o:value("$workdir/data/sessions.db",translate("sessions.db"))
o:value("$workdir/data/stats.db",translate("stats.db"))
o:value("$workdir/data/querylog.json",translate("querylog.json"))
o:value("$workdir/data/filters",translate("filters"))
o.widget = "checkbox"
o.default = nil
o.optional = true
local workdir = uci:get("AdGuardHome", "AdGuardHome", "workdir") or "/usr/bin/AdGuardHome"
o = s:option(MultiValue, "backupfile", translate("Automatic backup on shutdown"))
o1 = s:option(Value, "backupwdpath", translate("Backup workdir path"))
local name
o:value("sessions.db", translate("sessions.db"))
o:value("stats.db", translate("stats.db"))
o:value("querylog.json", translate("querylog.json"))
o:value("filters", translate("filters"))
o1:depends ("backupfile", "sessions.db")
o1:depends ("backupfile", "stats.db")
o1:depends ("backupfile", "querylog.json")
o1:depends ("backupfile", "filters")
for name in fs.glob(workdir.."/data/*")
do
    name = fs.basename (name)
    if name ~= "sessions.db" and name ~= "stats.db" and name ~= "querylog.json" and name ~= "filters" then
        o:value(name, name)
        o1:depends ("backupfile", name)
    end
end
o.widget = "checkbox"
o.default = nil
o.optional = false
o.description = translate("Data will be automatically restored if the workdir/data directory is empty.")

o1.default = "/etc/AdGuardHome/backup"
o1.datatype = "string"
o1.optional = false
o1.validate = function(self, value)
if fs.stat(value,"type") == "reg" then
    if m.message then
    m.message = m.message .. "\nerror!backup dir is a file"
    else
    m.message = "error!backup dir is a file"
    end
    return nil
end
if string.sub(value, -1) == "/" then
    return string.sub(value, 1, -2)
else
    return value
end
end

o = s:option(MultiValue, "crontab", translate("Crontab task"),translate("Please change time and args in crontab"))
o:value("autoupdate",translate("Update core-bin"))
o:value("cutquerylog",translate("Tail querylog"))
o:value("cutruntimelog",translate("Tail runtime log"))
o:value("autohost",translate("Update ipv6 hosts and restart"))
o:value("autogfw",translate("Update gfwlist and restart"))
o.widget = "checkbox"
o.default = nil
o.optional = true

o = s:option(Value, "update_url", translate("Core-bin Update URL"))
o.default = "https://github.com/AdguardTeam/AdGuardHome/releases/download/${Cloud_Version}/AdGuardHome_linux_${Arch}.tar.gz"
o.placeholder = "https://github.com/AdguardTeam/AdGuardHome/releases/download/${Cloud_Version}/AdGuardHome_linux_${Arch}.tar.gz"
o.rmempty = false
o.optional = false

function m.on_commit(map)
    if (fs.access("/var/run/AdGserverdis")) then
        io.popen("/etc/init.d/AdGuardHome reload &")
        return
    end
    local ucitracktest = uci:get("AdGuardHome", "AdGuardHome", "ucitracktest")
    if ucitracktest == "1" then
        return
    elseif ucitracktest == "0" then
        io.popen("/etc/init.d/AdGuardHome reload &")
    else
        if (fs.access("/var/run/AdGlucitest")) then
            uci:set("AdGuardHome", "AdGuardHome", "ucitracktest", "0")
            io.popen("/etc/init.d/AdGuardHome reload &")
        else
            fs.writefile("/var/run/AdGlucitest", "")
            if (ucitracktest == "2") then
                uci:set("AdGuardHome", "AdGuardHome", "ucitracktest", "1")
            else
                uci:set("AdGuardHome", "AdGuardHome", "ucitracktest", "2")
            end
        end
        uci:commit("AdGuardHome")
    end
end
return m
