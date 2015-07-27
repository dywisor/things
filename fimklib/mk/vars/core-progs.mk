f_which = $(shell which '$(1)' 2>/dev/null)

AWK      = awk
AWKF     = $(AWK) -f
SED      = sed
CP       = cp
CPF      = $(CP) -f
RM       = rm
RMF      = $(RM) -f
MV       = mv
MVF      = $(MV) -f
LN       = ln
LNF      = $(LN) -f
TOUCH    = touch
INSTALL  = install
MKDIR    = mkdir
MKDIRP   = $(MKDIR) -p
CHMOD    = chmod
CHOWN    = chown
X_RSYNC  = $(call f_which,rsync)
