#!/usr/bin/env bash
# seiva · JulianoSSR · MIT
# Compara caches privados e registra só o conceito; nunca imprime diff, logs ou hashes da origem.
set -uo pipefail
exec python3 "$(dirname -- "$0")/aprendizado.py" extrair "$@"
