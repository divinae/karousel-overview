VERSION = $(shell grep '"Version":' ./package/metadata.json | grep -o '[0-9\.]*')
QMLLINT ?= /usr/lib/qt6/bin/qmllint

.PHONY: lint test install uninstall package nested

lint:
	$(QMLLINT) ./package/contents/ui/*.qml

test:
	node --test tests/

install: lint test
	kpackagetool6 --type=KWin/Effect --install=./package || kpackagetool6 --type=KWin/Effect --upgrade=./package

uninstall:
	kpackagetool6 --type=KWin/Effect --remove=karousel_overview

package: lint test
	tar -czf ./karousel_overview_${subst .,_,${VERSION}}.tar.gz ./package --transform s/package/karousel_overview/

# headless KWin with its own D-Bus session and config, for testing without restarting the real KWin
NESTED_STATE ?= /tmp/karousel-overview-nested
nested: install
	rm -rf $(NESTED_STATE)
	./tools/nested.sh $(NESTED_STATE)
