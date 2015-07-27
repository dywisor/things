PYTHON ?= python
ifeq ($(PYTHON3),)
PYTHON3 := $(shell which python3 2>/dev/null)
endif

ifeq ($(PYTHON2),)
PYTHON2 := $(shell which python2 2>/dev/null)
endif

ifeq ($(PYTHON3),)
PYTHON_PREFER3 = $(PYTHON)
else
PYTHON_PREFER3 = $(PYTHON3)
endif
