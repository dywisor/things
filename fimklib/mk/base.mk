##ifeq ($(__PRJROOT),)
##$(error __PRJROOT is not set)
##endif

ifneq ($(DEFAULT_TARGET)$(DEFAULT_TARGETS),)
PHONY += default
default: $(DEFAULT_TARGET) $(DEFAULT_TARGETS)

endif


PHONY += __fimklib_default_target_not_defined
__fimklib_default_target_not_defined:
	@false


ifeq ($(S),)
override S := $(CURDIR)
endif

ifeq ($(O),)
override O := $(CURDIR)/build
endif

include $(FIMKLIB_MK)/vars.mk

include $(FIMKLIB_MK)/copytree.mk
include $(FIMKLIB_MK)/install.mk

include $(FIMKLIB_MK)/misc.mk

include $(FIMKLIB_MK)/build_scripts.mk

ifeq ($(PRJ_USE_SHELLGEN),1)
include $(FIMKLIB_MK)/shellgen.mk
endif

ifeq ($(PRJ_USE_C),1)
include $(FIMKLIB_MK)/c.mk
endif


$(S) $(O)::
	$(MKDIRP) -- "$(@)"


define DEF_INSTALL_TARGET
$(eval PHONY         += install-$(1))
$(eval PHONY         += uninstall-$(1))
$(eval INSTALL_NAMES += $(1))
endef
