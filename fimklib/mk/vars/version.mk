ifeq ($(VERSION),)
ifneq ($(S),)
override VERSION := $(shell head -n 1 $(S)/VERSION 2>/dev/null)
endif

ifeq ($(VERSION),)
ifneq ($(__PRJROOT),)
override VERSION := $(shell head -n 1 $(__PRJROOT)/VERSION 2>/dev/null)
endif

ifeq ($(VERSION),)
override VERSION := undef
endif
endif
endif


PHONY += version
version:
	@printf '%s\n' '$(VERSION)'
