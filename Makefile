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

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-adguardhome/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
    logger -t luci-app-adguardhome "prerm triggered, action: $$1"
    if [ "$$1" != "upgrade" ]; then
        logger -t luci-app-adguardhome "Performing full uninstall, cleaning configuration..."
        rm -rf /etc/adguardhome
        rm -f /etc/config/adguardhome
        rm -f /usr/bin/AdGuardHome
    else
        logger -t luci-app-adguardhome "Detected package upgrade, skipping configuration deletion."
    fi

    logger -t luci-app-adguardhome "Cleaning up system users/groups and cache..."
    sed -i '/adguardhome/d' /etc/passwd
    sed -i '/adguardhome/d' /etc/group
    rm -f /tmp/luci-indexcache
    /etc/init.d/dnsmasq restart
    logger -t luci-app-adguardhome "prerm finished successfully."
}
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
