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

define Package/luci-app-adguardhome/prerm
#!/bin/sh
rm -f /usr/bin/AdGuardHome
rm -rf /etc/adguardhome

sed -i '/adguardhome/d' /etc/passwd
sed -i '/adguardhome/d' /etc/group

/etc/init.d/dnsmasq restart

exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
