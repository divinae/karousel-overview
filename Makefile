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
