ifneq ($(METASH_DEFAULTS_FILE),)
METASH_VDEF_OPTS += -F '$(METASH_DEFAULTS_FILE)'
endif

METASH_VDEF_OPTS += $(foreach f,$(METASH_DEFAULTS_FILES),-F '$(f)')

METASH_OPTS += -V "VERSION=$(VERSION)"

RUN_METASH = $(X_METASH) $(METASH_VDEF_OPTS) $(METASH_OPTS)



# f_run_metash_convert_file ( srcfile, dstfile, [extra_opts] )
define f_run_metash_convert_file
	$(RUN_METASH) $(3) -O '$(strip $(2))' '$(strip $(1))'
endef

# f_run_metash_convert_dir ( srcdir, outdir, ["--stdin"], [extra_opts] )
define f_run_metash_convert_dir
	$(X_METASH_MULTI) $(3) \
		'$(strip $(1))' '$(strip $(2))' -- $(RUN_METASH) $(4)
endef

# f_run_metash_convert_dir_ifexist ( srcdir, outdir, ["--stdin"], [extra_opts] )
define f_run_metash_convert_dir_ifexist
	test ! -e '$(strip $(1))' || \
		$(call f_run_metash_convert_dir,$(1),$(2),$(3),$(4))
endef

# _f_metash_do_build ( tmpdir, srcdir, dstdir )
define _f_metash_do_build
	$(RMF) -r -- '$(1)'
	$(MKDIRP) -- '$(1)'

	$(call f_run_metash_convert_dir_ifexist,$(2),$(1))

	$(call f_run_shell_syntax_check_recursive,$(1))

	$(call f_copy_tree,$(1),$(3))
endef

# f_metash_do_build(...)
define f_metash_do_build
	$(call _f_metash_do_build,$(strip $(1)),$(strip $(2)),$(strip $(3)))
endef



# _metash_prepare_files_recursive ( srcdir, dstdir, [extra_opts] )
define _metash_prepare_files_recursive
	cd "$(1)" ## test

	$(MKDIRP) -- $(2)

	( cd "$(1)" && find ./ \( -type f -or -type l \) -print0; ) | \
		xargs -0 -r -n 1 -I '{F}' \
			$(SHELL) -c '\
				set -e; \
				farg={F}; farg="$${farg#./}"; \
				fname=$${farg##*/}; \
				\
				infile="$(1)/$${farg}"; \
				outfile="$(2)/$${farg}"; \
				\
				if [ -f "$${infile}" ]; then \
					$(MKDIRP) -- "$${outfile%/*}"; \
					\
					case "$${fname}" in \
						*.sh|*.bash) \
							$(RUN_METASH) $(3) -O "$${outfile}" "$${infile}" || exit ; \
						;; \
						*) \
							$(CP) -- "$${infile}" "$${outfile}" || exit ; \
						;; \
					esac; \
				fi;' __prog__
endef


# metash_prepare_files_recursive ( srcdir, dstdir, [extra_opts] )
define metash_prepare_files_recursive
	$(RMF) -r -- '$(strip $(2))'

	$(call _metash_prepare_files_recursive,$(strip $(1)),$(strip $(2)),$(3))
	$(call f_run_shell_syntax_check_recursive,$(strip $(2)))
endef
