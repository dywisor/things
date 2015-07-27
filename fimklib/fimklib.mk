override FIMKLIB_ROOT := $(strip $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
override FIMKLIB_MK   := $(FIMKLIB_ROOT)/mk

include $(FIMKLIB_MK)/base.mk

ifeq ($(MAIN_RULES),)
MAIN_RULES = $(S)/rules.mk
endif
include $(MAIN_RULES)

include $(FIMKLIB_MK)/last.mk
