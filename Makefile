PREFIX ?= $(HOME)/.local

.PHONY: test lint install uninstall

test:
	bash tests/test-cmux-berth.sh bin/cmux-berth

lint:
	shellcheck -S warning bin/* tests/*.sh

# A symlink, so a git pull in this clone updates the installed copy.
install:
	mkdir -p "$(PREFIX)/bin"
	ln -sfn "$(CURDIR)/bin/cmux-berth" "$(PREFIX)/bin/cmux-berth"

uninstall:
	rm -f "$(PREFIX)/bin/cmux-berth"
