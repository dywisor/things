ifeq ($(PRJ_C_USE_C_LIB),)
ifneq ($(PRJ_C_LIBNAME),)
PRJ_C_USE_C_LIB = 1
endif
endif

include $(FIMKLIB_MK)/c/vars.mk
include $(FIMKLIB_MK)/c/rules.mk
include $(FIMKLIB_MK)/c/objdef.mk
include $(FIMKLIB_MK)/c/objdefinspect.mk
include $(FIMKLIB_MK)/c/libdef.mk

include $(FIMKLIB_MK)/c/progdef.mk
#include $(FIMKLIB_MK)/c/
