C_RULE_DO_LINK_ONLY  = mkdir -p -- $(@D) && $(LINK_O) $^ -o $@
C_RULE_DO_STRIP_ONLY = $(TARGET_STRIP_IF_REQUESTED) -s $@

define C_RULE_DO_LINK
	$(C_RULE_DO_LINK_ONLY)
	$(C_RULE_DO_STRIP_ONLY)
endef
#C_RULE_DO_STRIP_IF_REQUESTED = $(TARGET_STRIP_IF_REQUESTED) $@


$(PRJ_C_O)/%.o: $(PRJ_C_SRCDIR)/%.c
	mkdir -p -- $(@D)
	$(COMPILE_C) $< -o $@
