#!/usr/bin/env bash
# seiva · JulianoSSR · MIT
# Capture o escopo antes da primeira edição. Exclusividade é compromisso do operador,
# além da trava compartilhada entre tarefas Seiva; não prova autoria contra editores externos.
set -eu
if [ "$#" -lt 3 ]; then
  echo "uso: base-tarefa.sh <pasta-da-tarefa> --exclusive <arquivo> [arquivo...]" >&2
  exit 2
fi
pasta=$1
shift
exec python3 "$(dirname -- "$0")/estado_tarefa.py" base "$pasta" "$@"
