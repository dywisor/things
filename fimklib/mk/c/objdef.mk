define _C_OBJ_DEFS
$(eval $(1)_ANY_NAMES     += $(addprefix $(2)/,$(ODEF_$(1)_ANY)))
$(eval $(1)_OBJECTS_NAMES += $(addprefix $(2)/,$(ODEF_$(1)_OBJECTS)))
$(eval $(1)_HEADERS_NAMES += $(addprefix $(2)/,$(ODEF_$(1)_HEADERS)))

$(eval $(3)_ANY_NAMES     += $($(1)_ANY_NAMES))
$(eval $(3)_OBJECTS_NAMES += $($(1)_OBJECTS_NAMES))
$(eval $(3)_HEADERS_NAMES += $($(1)_HEADERS_NAMES))
endef

C_OBJ_DEFS = $(call _C_OBJ_DEFS,$(call f_convert_name,$(1)),$(1),$(call f_convert_name,$(2)))
