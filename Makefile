VERSION = $(shell grep '"Version":' ./package/metadata.json | grep -o '[0-9\.]*')
QMLLINT ?= /usr/lib/qt6/bin/qmllint

.PHONY: *

lint:
	$(QMLLINT) ./package/contents/ui/*.qml

install: lint
	kpackagetool6 --type=KWin/Effect --install=./package || kpackagetool6 --type=KWin/Effect --upgrade=./package

uninstall:
	kpackagetool6 --type=KWin/Effect --remove=karousel_overview

package: lint
	tar -czf ./karousel_overview_${subst .,_,${VERSION}}.tar.gz ./package --transform s/package/karousel_overview/

# headless KWin with its own D-Bus session and config, for testing without restarting the real KWin
NESTED_STATE ?= /tmp/karousel-overview-nested
nested: install
	rm -rf $(NESTED_STATE)
	./tools/nested.sh $(NESTED_STATE)
