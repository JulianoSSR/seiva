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
exec python3 "$(dirname -- "$0")/estado_tarefa.py" diff "$pasta" "$@"
