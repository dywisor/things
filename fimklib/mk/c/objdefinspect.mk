f_get_objectsv  = $(addprefix $(PRJ_C_O)/,$(addsuffix .o,$(1)))
f_get_headersv  = $(addprefix $(PRJ_C_SRCDIR)/,$(addsuffix .h,$(1)))

get_c_headers = \
	$(foreach x,$(1),\
		$(call f_get_headersv,$($(x)_ANY_NAMES) $($(x)_HEADERS_NAMES)))

get_c_objects = \
	$(foreach x,$(1),\
		$(call f_get_objectsv,$($(x)_ANY_NAMES) $($(x)_OBJECTS_NAMES)))
