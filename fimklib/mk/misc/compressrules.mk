X_BZIP2 ?= bzip2
X_GZIP  ?= gzip
X_XZ    ?= xz

%.bz2: % | _basedep_clean
	$(X_BZIP2) -c $(<) > $(@)

%.gz: % | _basedep_clean
	$(X_GZIP)  -c $(<) > $(@)

%.xz: % | _basedep_clean
	$(X_XZ)    -c $(<) > $(@)
