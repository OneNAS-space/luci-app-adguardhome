#
# Copyright (C) 2025 OneNAS.space, Jackie264 (jackie.han@gmail.com).
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-adguardhome
PKG_VERSION:=2.4.20
PKG_RELEASE:=20251201

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=OneNAS-space

PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-adguardhome
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI app for adguardhome
	PKG_MAINTAINER:=https://github.com/OneNAS-space/luci-app-adguardhome
	PKGARCH:=all
	DEPENDS:=+wget-ssl +tar +xz +luci-lua-runtime +luci-compat
endef

define Package/luci-app-adguardhome/description
	LuCI support for adguardhome
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/luci-app-adguardhome/conffiles
/etc/config/AdGuardHome
endef

define Package/luci-app-adguardhome/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	cp -pR ./luasrc/* $(1)/usr/lib/lua/luci
	$(INSTALL_DIR) $(1)/
	cp -pR ./root/* $(1)/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	po2lmo ./po/zh-cn/AdGuardHome.po $(1)/usr/lib/lua/luci/i18n/AdGuardHome.zh-cn.lmo
endef

define Package/luci-app-adguardhome/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/AdGuardHome enable
rm -f /tmp/luci-indexcache
rm -f /tmp/luci-modulecache/*
exit 0
endef

define Package/luci-app-adguardhome/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/AdGuardHome disable
uci -q batch <<-EOF >/dev/null 2>&1
	delete ucitrack.@AdGuardHome[-1]
	commit ucitrack
EOF
fi
exit 0
endef

$(eval $(call BuildPackage,luci-app-adguardhome))
