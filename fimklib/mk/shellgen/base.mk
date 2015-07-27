# f_run_shell_syntax_check_recursive ( dir )
#
define f_run_shell_syntax_check_recursive
	$(X_FIND_SHFILES) $(1) | xargs -r -n 1 $(SHELL) -n
endef

# f_combine_script_files ( srcfiles, dstfile )
define f_combine_script_files
	$(X_MERGE_SCRIPTFILES) -O $(2).new $(1) && \
	$(SHELL) -n $(2).new && \
	$(MVF) -- $(2).new $(2)
endef

# f_combine_script_file_dir ( srcdir, dstfile )
define f_combine_script_file_dir
	$(call f_combine_script_files,$$(find $(1) -type f -not -name '.stamp*' -name '*.sh' | sort -V ),$(2))
endef
