# luci-app-adguardhome（nft 版）简要说明

面向已熟悉原项目的用户: 仅将 **DNS** 重定向从 `iptables` 迁移到 `nftables`, 核心语义不变

## 变更概览
- `iptables` → `nftables`：使用 nft 应用/清理规则 `/var/etc/adguardhome.nft`
- 模板路径：`/usr/share/AdGuardHome/adguardhome.nft.tpl`

## 模板与默认行为
> [!CAUTION]
> 模板中默认 **WAN** 接口设备名为 `eth0`, 因此使用如下规则排除来自 **WAN** 的入站流量<br>避免把路由器暴露为‼️**公共解析器**‼️
> ```
> iifname { "eth0" } return
> ```
> 
> 其余匹配到 `目标为本机` 的 `53` 端口流量会被重定向至 **AdGuard Home** 的监听端口
> ```
> fib daddr type local udp dport 53 redirect to :__AGH_PORT__
> fib daddr type local tcp dport 53 redirect to :__AGH_PORT__
> ```

> [!CAUTION]
> ## ‼️如果你的 **WAN** 不是 `eth0`
> 请手动把上面的接口名改为你的实际 **WAN** 设备名; 多个接口用逗号分隔
> ```
> iifname { "eth1" } return
> ```
> ```
> iifname { "eth0", "eth1", "macvlan0" } return
> ```

> [!TIP]
> *设备名可通过 `ip a` / `ifconfig` 查看*

## 声明
本项目基于 https://github.com/rufengsuixing/luci-app-adguardhome 修改。
原项目未提供明确的开源协议，当前仅用于个人学习研究，不用于商业用途。如原作者有任何异议，请联系我处理。
