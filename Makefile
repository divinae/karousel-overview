VERSION = $(shell grep '"Version":' ./package/metadata.json | grep -o '[0-9\.]*')
QMLLINT ?= /usr/lib/qt6/bin/qmllint
QSB ?= /usr/lib/qt6/bin/qsb

.PHONY: lint test shaders translations messages install uninstall package nested

lint:
	# lint/ describes the part of KWin's QML module the effect uses, qmllint can't load the real one
	$(QMLLINT) -I lint --max-warnings 0 ./package/contents/ui/*.qml

test:
	node --test tests/

# the compiled shaders are committed, so that installing doesn't need Qt's shader tools,
# rebuild them after changing a shader in shaders/
shaders:
	for shader in shaders/*.frag; do $(QSB) --qt6 -o ./package/contents/ui/$$(basename $$shader).qsb $$shader; done

# the translations, compiled into the package, where the settings dialog finds them; the effect only finds them in
# the user's or the system's locale directory, where install puts them too
LOCALE_DIR ?= $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/locale
translations:
	for po in po/*.po; do \
		lang=$$(basename $$po .po); \
		mkdir -p ./package/contents/locale/$$lang/LC_MESSAGES; \
		msgfmt --check -o ./package/contents/locale/$$lang/LC_MESSAGES/karousel_overview.mo $$po; \
	done

# after changing strings: collects them into po/karousel_overview.pot and updates the translations
messages:
	./tools/extract-messages.sh

# lint is for development and CI, installing shouldn't fail on a warning from another version of qmllint
install: test translations
	kpackagetool6 --type=KWin/Effect --install=./package || kpackagetool6 --type=KWin/Effect --upgrade=./package
	for mo in ./package/contents/locale/*/LC_MESSAGES/karousel_overview.mo; do \
		lang=$$(basename $$(dirname $$(dirname $$mo))); \
		install -D -m 644 $$mo $(LOCALE_DIR)/$$lang/LC_MESSAGES/karousel_overview.mo; \
	done

uninstall:
	kpackagetool6 --type=KWin/Effect --remove=karousel_overview
	rm -f $(LOCALE_DIR)/*/LC_MESSAGES/karousel_overview.mo

package: lint test translations
	tar -czf ./karousel_overview_${subst .,_,${VERSION}}.tar.gz ./package --transform s/package/karousel_overview/

# headless KWin with its own D-Bus session and config, for testing without restarting the real KWin
NESTED_STATE ?= /tmp/karousel-overview-nested
nested: install
	rm -rf $(NESTED_STATE)
	./tools/nested.sh $(NESTED_STATE)
