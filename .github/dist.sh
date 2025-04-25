#!/bin/bash

set -euo pipefail
IFS=$'\t\n'

if [[ -d dist ]]; then
	rm -r dist
fi
mkdir dist
cp -r tptasm modulepack.conf dist/
cd dist
git submodule update --init
luajit ../TPT-Script-Manager/modulepack.lua modulepack.conf > tptasm.dist.lua
