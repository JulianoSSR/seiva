#!/usr/bin/env bash
# seiva · JulianoSSR · MIT
# Monta o diff.patch de uma tarefa só com os arquivos que ela entregou, incluindo arquivo novo.
# `git diff` puro deixa de fora arquivo não rastreado e pega o que outra sessão mexeu na mesma árvore.
#
# Uso: diff-tarefa.sh <pasta-da-tarefa> <arquivo> [arquivo...]
# Grava <pasta-da-tarefa>/diff.patch e imprime um resumo por arquivo.
# Uso errado sai com 2, e inclui apontar a pasta errada: a de trabalho (a que tem tarefas/) ou a própria tarefas/ no
# lugar da pasta da tarefa. Nesses dois casos o diff.patch não é gravado; a mensagem diz o que apontar.
set -u

if [ "$#" -lt 2 ]; then
  echo "uso: $0 <pasta-da-tarefa> <arquivo> [arquivo...]" >&2
  echo "     a pasta da tarefa é <trabalho>/tarefas/<tarefa>; a pasta de trabalho ou a tarefas/ sai com 2, sem gravar nada." >&2
  exit 2
fi

pasta=$1; shift
# Trava de pasta: o script pede a pasta da tarefa. Com a pasta de trabalho (tem tarefas/) ou com a tarefas/ (o nome é
# tarefas e alguma subpasta tem registro.md ou progresso.md), recusa com 2 antes de gravar qualquer coisa. O caminho é
# resolvido antes: "." e ".." e link simbólico caem no mesmo lugar. Pasta que não existe segue como hoje.
if abs=$(cd -- "$pasta" 2>/dev/null && pwd -P); then
  if [ -d "$abs/tarefas" ]; then
    echo "diff-tarefa.sh: $abs é pasta de trabalho (tem tarefas/); <pasta-da-tarefa> pede a pasta da tarefa, $abs/tarefas/<tarefa>" >&2
    exit 2
  fi
  if [ "${abs##*/}" = tarefas ]; then
    for sub in "$abs"/*/; do
      if [ -f "${sub}registro.md" ] || [ -f "${sub}progresso.md" ]; then
        echo "diff-tarefa.sh: $abs é a pasta tarefas/; <pasta-da-tarefa> pede uma tarefa dentro dela, $abs/<tarefa>" >&2
        exit 2
      fi
    done
  fi
fi
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
