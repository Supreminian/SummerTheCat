#!/bin/zsh
set -eu
SUMMER_SOURCE_DIR="${0:A:h}"
cd "$SUMMER_SOURCE_DIR"
"${TUXI_PYTHON:-python3}" import_thinking.py
"${TUXI_PYTHON:-python3}" build_chat_preview.py
zsh build.sh
