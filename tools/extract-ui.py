#!/usr/bin/env python3
"""Prints the translatable strings of a Qt Designer .ui file as i18n() calls, for xgettext to pick up, like KDE's
extractrc: the KCM translates them by their text alone, see KLocalizedTranslator."""
import sys
import xml.etree.ElementTree as ElementTree


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


for path in sys.argv[1:]:
    root = ElementTree.parse(path).getroot()
    for prop in root.iter("property"):
        string = prop.find("string")
        if string is None or not (string.text or "").strip() or string.get("notr") == "true":
            continue
        comment = string.get("comment")
        if comment:
            print(f'// i18n: {comment}')
        print(f'i18n("{escape(string.text)}");')
