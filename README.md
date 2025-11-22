# luci-app-adguardhome（nft 版）

将 **DNS** 重定向从 `iptables` 迁移到 `nftables`, 核心语义不变。

## 变更概览
- 修订 Makefile 对 adguardhome 的依赖，因为那会去安装 Openwrt 的 adguardhome 包，导致 `procd` 注册两个 `adguardhome` 服务
- 修订 Makefile 中 postinst 和 prerm 冗余的 `stop` `reload`，全部交给 Openwrt `rc.common` 执行，以解决 `opkg upgrade` 时报错：`command failed: not found` 的问题
- nft 应用/清理规则模板路径：`/usr/share/AdGuardHome/adguardhome.nft.tpl`
- 修订 init 脚本，固化bin路径 `PROG=/usr/bin/AdGuardHome`，删除了冗余代码
- 修订 init 脚本 `START` `STOP` 顺序，以完全适配 Openwrt 的 dnsmasq 和 networking
- 修订 init 脚本，动态获取 ***WAN*** 接口传递给 nft 规则
- 修订 init 脚本 `service_triggers()` 函数，等待 interface 启动后再真正启动 AdGuardHome，删除 `waitnet.sh` 及相关逻辑块。防止相关问题 https://github.com/openwrt/packages/issues/21868 发生
- 添加 `50-adguardhome.conf` 以增加 QUIC 协议需要大缓存的需求
- 修订 `AdGuardHome.lua` `base.lua` `AdGuardHome_status.htm` `update_core.sh` 部分代码

## 模板与默认行为
> [!CAUTION]
> 修订模版以适配动态获取 ***WAN*** 接口, 使用如下规则排除来自 **WAN** 的入站流量<br>避免把路由器暴露为‼️**公共解析器**‼️
> ```
> iifname { __WAN_EXCLUDES__ } return
> ```
> 
> 其余匹配到 `目标为本机` 的 `53` 端口流量会被重定向至 **AdGuard Home** 的监听端口
> ```
> fib daddr type local udp dport 53 redirect to :__AGH_PORT__
> fib daddr type local tcp dport 53 redirect to :__AGH_PORT__
> ```

> [!TIP]
> *仅适配OpenWRT官方源码，第三方源码产生的问题不作解答*
> 
> *仅支持 `nftables`，旧版 Openwrt 以及仍在使用 `iptables` 的新版 Openwrt 无法使用*
> 
> *设备名可通过 `ip a` / `ifconfig` 查看*

## 声明
基于 [@w9315273 的nft版](https://github.com/w9315273/luci-app-adguardhome) 修改。
如原作者有任何异议，请联系我处理。
