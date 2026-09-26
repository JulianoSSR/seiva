#!/usr/bin/env bash
# Monta o diff.patch de uma tarefa só com os arquivos que ela entregou, incluindo arquivo novo.
# `git diff` puro deixa de fora arquivo não rastreado e pega o que outra sessão mexeu na mesma árvore.
#
# Uso: diff-tarefa.sh <pasta-da-tarefa> <arquivo> [arquivo...]
# Grava <pasta-da-tarefa>/diff.patch e imprime um resumo por arquivo.
set -u

if [ "$#" -lt 2 ]; then
  echo "uso: $0 <pasta-da-tarefa> <arquivo> [arquivo...]" >&2
  exit 2
fi

pasta=$1; shift
saida="$pasta/diff.patch"
: > "$saida"

for f in "$@"; do
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    git diff HEAD -- "$f" >> "$saida"
    estado="alterado"
    [ -e "$f" ] || estado="apagado"
  elif [ -e "$f" ]; then
    # Arquivo novo: diff contra o vazio. O exit 1 do --no-index é esperado (há diferença).
    git diff --no-index -- /dev/null "$f" >> "$saida"
    estado="novo"
  else
    estado="nao-existe"
  fi
  printf '%-10s %s\n' "$estado" "$f"
done

printf 'linhas no diff: %s  ->  %s\n' "$(wc -l < "$saida")" "$saida"
