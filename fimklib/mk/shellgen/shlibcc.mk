PRJ_SHLIB_SRCDIR         ?= $(S)/src
PRJ_SHLIB_SCRIPTS_SRCDIR ?= $(PRJ_SHLIB_SRCDIR)/scripts
PRJ_SHLIB_LIB_SRCDIR     ?= $(PRJ_SHLIB_SRCDIR)/lib

PRJ_SHLIB_O              ?= $(O)/shlib
PRJ_SHLIB_SCRIPTS_O      ?= $(PRJ_SHLIB_O)/scripts
PRJ_SHLIB_LIB_O          ?= $(PRJ_SHLIB_O)/lib

PRJ_SHLIB_TMP_O          ?= $(PRJ_SHLIB_O)/tmp
PRJ_SHLIB_SCRIPTS_TMP_O  ?= $(PRJ_SHLIB_TMP_O)/scripts
PRJ_SHLIB_LIB_TMP_O      ?= $(PRJ_SHLIB_TMP_O)/lib


SHLIBCC                  ?= shlibcc
SHLIBCC_ARGS             ?= --short-header --strip-all --allow-empty --stable-sort
SHLIBCC_ARGS_EXTRA       ?=
_SHLIBCC_ARGS             = $(SHLIBCC_ARGS) $(SHLIBCC_ARGS_EXTRA)

ifeq ($(SHLIB_INCLUDE),)
ifeq ($(SHLIB_SRCDIR),)
SHLIB_INCLUDE := /usr/share/shlib/default/include
else
SHLIB_INCLUDE := $(SHLIB_SRCDIR)/lib
endif
endif


RUN_SHLIBCC = \
	$(SHLIBCC) -S "$(SHLIB_INCLUDE)" -I "$(PRJ_SHLIB_LIB_TMP_O)" $(_SHLIBCC_ARGS)



$(PRJ_SHLIB_LIB_O)/%.sh: $(PRJ_SHLIB_TMP_O)/.stamp_shlib_lib | _basedep_clean
	$(MKDIRP) -- $(@D)
	$(RMF) -- $(@)
	$(RUN_SHLIBCC) --as-lib --shell sh -O "$(@)" "virtual/$(*)"


$(PRJ_SHLIB_LIB_O)/%.bash: $(PRJ_SHLIB_TMP_O)/.stamp_shlib_lib | _basedep_clean
	$(MKDIRP) -- $(@D)
	$(RMF) -- $(@)
	$(RUN_SHLIBCC) --as-lib --shell bash -O "$(@)" "virtual/$(*)"


$(PRJ_SHLIB_SCRIPTS_O)/%.sh: $(PRJ_SHLIB_TMP_O)/.stamp_shlib_scripts | _basedep_clean
	$(MKDIRP) -- $(@D)
	$(RMF) -- $(@)
	$(RUN_SHLIBCC) -u --shell sh -O "$(@)" \
		--depfile --main $(PRJ_SHLIB_SCRIPTS_TMP_O)/$(*).sh

$(PRJ_SHLIB_SCRIPTS_O)/%.bash: $(PRJ_SHLIB_TMP_O)/.stamp_shlib_scripts | _basedep_clean
	$(MKDIRP) -- $(@D)
	$(RMF) -- $(@)
	{ \
		f="$(PRJ_SHLIB_SCRIPTS_TMP_O)/$(*).bash"; \
		[ -f "$${f}" ] || f="$(PRJ_SHLIB_SCRIPTS_TMP_O)/$(*).sh"; \
		$(RUN_SHLIBCC) -u --shell bash -O "$(@)" --depfile --main "$${f}"; \
	}


# stub - define create_shlib_metash_vdef
$(PRJ_SHLIB_TMP_O)/metash_vdef: FORCE | _basedep_clean
	$(MKDIRP) -- $(@D)
	$(RMF)    -- $(@)
	$(TOUCH)  -- $(@).make_tmp
	$(call create_shlib_metash_vdef,$($(@).make_tmp))
	$(MVF)    -- $(@).make_tmp $(@)


$(PRJ_SHLIB_TMP_O)/.stamp_shlib_lib: $(PRJ_SHLIB_TMP_O)/metash_vdef \
	$(shell find $(PRJ_SHLIB_LIB_SRCDIR) \( -type f -or -type l \) 2>/dev/null) | _basedep_clean

	$(MKDIRP) -- $(@D)

	$(call metash_prepare_files_recursive,\
		$(PRJ_SHLIB_LIB_SRCDIR),$(PRJ_SHLIB_LIB_TMP_O),-F $(<))

	touch $(@)

$(PRJ_SHLIB_TMP_O)/.stamp_shlib_scripts_base: $(PRJ_SHLIB_TMP_O)/metash_vdef \
	$(shell find $(PRJ_SHLIB_SCRIPTS_SRCDIR) \( -type f -or -type l \) 2>/dev/null) | _basedep_clean

	$(MKDIRP) -- $(@D)

	$(call metash_prepare_files_recursive,\
		$(PRJ_SHLIB_SCRIPTS_SRCDIR),$(PRJ_SHLIB_SCRIPTS_TMP_O),-F $(<))

	# create dummy depend files where necessary
	find $(PRJ_SHLIB_SCRIPTS_TMP_O) \
		\( -name "*.sh" -or -name "*.bash" \) \
		\( -type f -or -type l \) -print0 | \
			xargs -0 -r -n 1 -I "{F}" $(SHELL) -c '\
				set -e; f="{F}"; [ -n "$${f}" ] || exit 5; \
				\
				if [ -e "$${f}.depend" ]; then \
					: ; \
				elif [ -e "$${f%.*sh}.depend" ]; then \
					: ; \
				else \
					$(TOUCH) "$${f}.depend" || exit 9; \
				fi; \
				' __prog__


	touch $(@)

# creation of $(PRJ_SHLIB_SCRIPTS_TMP_O) does not depend on
# $(PRJ_SHLIB_LIB_TMP_O), but lib is required for generating scripts
# in $(PRJ_SHLIB_SCRIPTS_O).
$(PRJ_SHLIB_TMP_O)/.stamp_shlib_scripts: \
	$(PRJ_SHLIB_TMP_O)/.stamp_shlib_lib \
	$(PRJ_SHLIB_TMP_O)/.stamp_shlib_scripts_base  | _basedep_clean

	$(MKDIRP) -- $(@D)
	$(TOUCH)  -- $(@)
