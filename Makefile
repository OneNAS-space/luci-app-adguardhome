# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

LUCI_NAME:=luci-app-adguardhome
LUCI_MAINTAINER:=George Sapkin <george@sapk.in>
PKG_LICENSE:=GPL-2.0-only

LUCI_TITLE:=LuCI support for AdGuard Home
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all
USERID:=adguardhome=853:adguardhome=853

PKG_UNPACK:=$(CURDIR)/.prepare.sh $(PKG_NAME) $(CURDIR) $(PKG_BUILD_DIR)

define Package/luci-app-adguardhome/conffiles
/etc/adguardhome/adguardhome.yaml
/etc/config/adguardhome
endef

LOCK_FILE:=/etc/adguardhome/.upgrading

define Package/luci-app-adguardhome/preinst
#!/bin/sh
mkdir -p /etc/adguardhome
rm -f $(LOCK_FILE)
touch $(LOCK_FILE)
exit 0
endef

define Package/luci-app-adguardhome/prerm
#!/bin/sh
# 检查标记：如果锁存在，说明是在做升级，保留配置
if [ -f "$LOCK_FILE" ]; then
    logger -t luci-app-adguardhome "Detected upgrade, preserving configuration."
    exit 0
fi

# 否则是卸载，清空配置文件
logger -t luci-app-adguardhome "Performing full uninstall, cleaning configuration..."
rm -rf /etc/adguardhome
rm -f /etc/config/adguardhome
rm -f /usr/bin/AdGuardHome

logger -t luci-app-adguardhome "Cleaning up system users/groups and cache..."
sed -i '/adguardhome/d' /etc/passwd
sed -i '/adguardhome/d' /etc/group

[ -n "${IPKG_INSTROOT}" ] || { 
    rm -f /tmp/luci-indexcache.*
    rm -rf /tmp/luci-modulecache/
    /etc/init.d/rpcd reload 2>/dev/null
}
logger -t luci-app-adguardhome "prerm finished successfully."
exit 0
endef

define Package/luci-app-adguardhome/postinst
#!/bin/sh
rm -f "$LOCK_FILE"
[ -n "${IPKG_INSTROOT}" ] || { 
    rm -f /tmp/luci-indexcache.*
    rm -rf /tmp/luci-modulecache/
    /etc/init.d/rpcd reload 2>/dev/null
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
