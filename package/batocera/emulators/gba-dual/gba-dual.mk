################################################################################
#
# gba-dual
#
################################################################################

GBA_DUAL_SITE = $(BR2_EXTERNAL_BATOCERA_PATH)/package/batocera/emulators/gba-dual
GBA_DUAL_SITE_METHOD = local
GBA_DUAL_LICENSE = MPL-2.0
GBA_DUAL_DEPENDENCIES = sdl2 libretro-mgba
GBA_DUAL_EMULATOR_INFO = gba-dual.emulator.yml

GBA_DUAL_CONF_OPTS += -DCMAKE_BUILD_TYPE=Release

define GBA_DUAL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_BATOCERA_PATH)/package/batocera/emulators/gba-dual/batocera-gba2p \
		$(TARGET_DIR)/usr/bin/batocera-gba2p
endef

GBA_DUAL_POST_INSTALL_TARGET_HOOKS += GBA_DUAL_INSTALL_TARGET_CMDS

$(eval $(cmake-package))
$(eval $(emulator-info-package))