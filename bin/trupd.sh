#!/usr/bin/env bash

echo "updating locale...\n"

git clone --depth 1 https://github.com/minetest-tools/update_translations upd
python3 upd/i18n.py .
rm -rf upd

echo "Locale is up to date"
