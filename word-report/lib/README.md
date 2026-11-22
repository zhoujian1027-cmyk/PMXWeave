# System library dependencies

This distribution does not contain copied native shared libraries. Install the dependencies required by the worker’s R packages through its operating-system package manager. Debian-based images may need `libwebpmux3` and `libwebpdemux2` for the Word graphics dependencies.

`preload_word_libs.R` still supports explicitly supplied deployment fallback libraries, but this release does not provide one. Do not treat an unchanged Word environment error as a data/model problem or repeatedly resubmit a failed report. See `references/troubleshooting.md` and `analyses_template/tools/preflight_word.R`.
