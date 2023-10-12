#!/usr/bin/env bash
git clone --depth 1 https://github.com/minetest-tools/update_translations upd
chmod +x upd/i18n.py
upd/i18n.py .
rm -rf upd

echo "up to date"
