.PHONY: init check

init:
	@scripts/install-git-hooks.sh

check:
	@scripts/check-plugin-shape.sh
