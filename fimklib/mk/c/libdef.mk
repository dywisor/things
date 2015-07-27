### _C_LIB_VARS_DEF ( make_name, lib_name, lib_sover:=0 )
###
define _C_LIB_VARS_DEF
$(eval LIB$(1)_SO_VERSION            = $(if $(3),$(3),0))
$(eval LIB$(1)_SO_NAME               = $(2))
$(eval LIB$(1)_SO_LIBNAME            = lib$(LIB$(1)_SO_NAME))
$(eval LIB$(1)_SO_FILENAME           = $(LIB$(1)_SO_LIBNAME).so)
$(eval LIB$(1)_SO_FILENAME_VERSIONED = \
	$(LIB$(1)_SO_FILENAME).$(LIB$(1)_SO_VERSION))

$(eval LIB$(1)_DEP                   = $(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME))
$(eval LIB$(1)_INCLUDE               = $(LIB$(1)_SO_NAME))
endef
### END;


### _C_LIB_OBJ_STD_BUILD_DEF ( make_name, lib_name, <components> )
###
define _C_LIB_OBJ_STD_BUILD_DEF
$(eval LIB$(1)_OBJECTS += $(call get_c_objects,$(3)))
$(eval LIB$(1)_HEADERS += $(call get_c_headers,$(3)))
$(eval LIB$(1)_SRCDEPS  = $(LIB$(1)_OBJECTS) $$(LIB$(1)_HEADERS))

# $(PRJ_C_OLIB)/lib<name>.so.<version>
$(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME_VERSIONED): $(LIB$(1)_SRCDEPS)
	$(MKDIRP) -- $$(@D)
	$(COMPILE_C_SHARED) -Wl,-soname,$$(@F) $$(filter-out %.h,$$^) -o $$@
	$(TARGET_STRIP_IF_REQUESTED) -s $$@

# $(PRJ_C_OLIB)/lib<name>.so
$(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME): $(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME_VERSIONED)
	$(DOSYM) -- $$(<F) $$(@)

# lib<name> (phony)
PHONY     += $(LIB$(1)_SO_LIBNAME)
LIB_NAMES += $(LIB$(1)_SO_LIBNAME)

$(LIB$(1)_SO_LIBNAME): \
	$(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME_VERSIONED) \
	$(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME)

endef
### END;


### _C_LIB_OBJ_STD_INSTALL_DEF__COMMON ( make_name )
###
define _C_LIB_OBJ_STD_INSTALL_DEF__COMMON

# install-lib<name>
$(call DEF_INSTALL_TARGET,$(LIB$(1)_SO_LIBNAME))


uninstall-$(LIB$(1)_SO_LIBNAME):
	$(RMF) -- $(DESTDIR)$(LIBDIR)/$(LIB$(1)_SO_FILENAME_VERSIONED)
	$(RMF) -- $(DESTDIR)$(LIBDIR)/$(LIB$(1)_SO_FILENAME)

endef
### END;


### _C_LIB_OBJ_STD_INSTALL_DEF_VERSIONED ( make_name )
###
define _C_LIB_OBJ_STD_INSTALL_DEF_VERSIONED

$(call _C_LIB_OBJ_STD_INSTALL_DEF__COMMON,$(1))

install-$(LIB$(1)_SO_LIBNAME):
	$(DOEXE) $(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME_VERSIONED) \
		$(DESTDIR)$(LIBDIR)/$(LIB$(1)_SO_FILENAME_VERSIONED)
	$(DOSYM) -- $(LIB$(1)_SO_FILENAME_VERSIONED) \
		$(DESTDIR)$(LIBDIR)/$(LIB$(1)_SO_FILENAME)

endef
### END;


### _C_LIB_OBJ_STD_INSTALL_DEF_UNVERSIONED ( make_name )
###
define _C_LIB_OBJ_STD_INSTALL_DEF_UNVERSIONED

$(call _C_LIB_OBJ_STD_INSTALL_DEF__COMMON,$(1))

install-$(LIB$(1)_SO_LIBNAME):
	$(DOEXE) $(PRJ_C_OLIB)/$(LIB$(1)_SO_FILENAME_VERSIONED) \
		$(DESTDIR)$(LIBDIR)/$(LIB$(1)_SO_FILENAME)

endef
### END;


### _C_LIB_DEF_VERSIONED ( make_name, lib_name, lib_sover, <components> )
###
define _C_LIB_DEF_VERSIONED
$(call _C_LIB_VARS_DEF,$(1),$(2),$(3))
$(call _C_LIB_OBJ_STD_BUILD_DEF,$(1),$(2),$(4))
$(call _C_LIB_OBJ_STD_INSTALL_DEF_VERSIONED,$(1))
endef
### END;


### _C_LIB_DEF_UNVERSIONED ( make_name, lib_name, lib_sover, <components> )
###
define _C_LIB_DEF_UNVERSIONED
$(call _C_LIB_VARS_DEF,$(1),$(2),$(3))
$(call _C_LIB_OBJ_STD_BUILD_DEF,$(1),$(2),$(4))
$(call _C_LIB_OBJ_STD_INSTALL_DEF__UNVERSIONED,$(1))
endef
### END;


### C_LIB_VARS_DEF ( lib_name, lib_sover:=0 )
C_LIB_VARS_DEF = $(call _C_LIB_VARS_DEF,$(call _f_convert_name,$(1)),$(1),$(2))

### C_LIB_DEF_V ( lib_name, lib_sover, <components> )
### C_LIB_DEF_U ( lib_name, lib_sover, <components> )
C_LIB_DEF_V    = $(call _C_LIB_DEF_VERSIONED,$(call _f_convert_name,$(1)),$(1),$(2),$(3))
C_LIB_DEF_U    = $(call _C_LIB_DEF_UNVERSIONED,$(call _f_convert_name,$(1)),$(1),$(2),$(3))

### C_LIB_DEF ( lib_name, <components> )
###  backwards-compat hack.
C_LIB_DEF      = $(call _C_LIB_DEF_VERSIONED,$(call _f_convert_name,$(1)),$(1),0,$(2))
