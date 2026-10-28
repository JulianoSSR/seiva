#!/usr/bin/env bash
# Cria a pasta de uma tarefa com registro, plano, achados, progresso, contexto e a 1ª marca de sessão (sessoes),
# e grava no registro a foto do `git status` de agora: o que já estava mexido antes da
# tarefa começar é de outra sessão, não desta.
#
# Uso: nova-tarefa.sh <pasta-de-trabalho> <slug>
# Exemplo: nova-tarefa.sh .claude/seiva bug-088-errors
# A pasta de trabalho é a que contém (ou vai conter) tarefas/; pasta nova ou vazia serve, é o primeiro uso num projeto.
# Uso errado sai com 2, e inclui apontar a pasta errada: a de uma tarefa (raiz com registro.md ou progresso.md) ou a
# própria tarefas/. Nesses dois casos nada é criado; a mensagem diz o que apontar.
set -eu

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <pasta-de-trabalho> <slug>" >&2
  echo "     a pasta de trabalho é a que contém tarefas/ (nova ou vazia serve); a pasta de uma tarefa ou a tarefas/ sai com 2, sem criar nada." >&2
  exit 2
fi

base=$1
slug=$2

case "$slug" in
  *[!a-z0-9-]* | '' | -* )
    echo "slug inválido: use só letras minúsculas, números e hífen (ex.: bug-088-errors)" >&2
    exit 2
    ;;
esac

# Trava de pasta: o script pede a pasta de trabalho. Com a pasta de uma tarefa (raiz com registro.md ou progresso.md) ou
# com a tarefas/ (o nome é tarefas e alguma subpasta tem registro.md ou progresso.md), recusa com 2 antes de criar
# qualquer coisa. Quem tem tarefas/ dentro é pasta de trabalho, e isso vence. O caminho é resolvido antes; pasta que
# ainda não existe, ou vazia, segue (é o primeiro uso num projeto).
if abs=$(cd -- "$base" 2>/dev/null && pwd -P) && [ ! -d "$abs/tarefas" ]; then
  if [ "${abs##*/}" = tarefas ]; then
    for sub in "$abs"/*/; do
      if [ -f "${sub}registro.md" ] || [ -f "${sub}progresso.md" ]; then
        echo "nova-tarefa.sh: $abs é a pasta tarefas/; nova-tarefa.sh pede a pasta que a contém, $(dirname -- "$abs")" >&2
        exit 2
      fi
    done
  fi
  if [ -f "$abs/registro.md" ] || [ -f "$abs/progresso.md" ]; then
    echo "nova-tarefa.sh: $abs é pasta de tarefa; nova-tarefa.sh pede a pasta de trabalho, a que contém tarefas/" >&2
    exit 2
  fi
fi

skill=$(cd "$(dirname "$0")/.." && pwd)
dia=$(date +%F)
destino="$base/tarefas/$dia-$slug"

if [ -e "$destino" ]; then
  echo "já existe: $destino" >&2
  exit 1
fi

mkdir -p "$destino/relatorios"
sed -e "s/{{DATA}}/$dia/g" -e "s/{{SLUG}}/$slug/g" "$skill/moldes/registro.md" > "$destino/registro.md"
sed -e "s/{{SLUG}}/$slug/g" "$skill/moldes/plano.md" > "$destino/plano.md"
sed -e "s/{{SLUG}}/$dia-$slug/g" "$skill/moldes/progresso.md" > "$destino/progresso.md"
sed -e "s/{{SLUG}}/$dia-$slug/g" "$skill/moldes/contexto-tarefa.md" > "$destino/contexto-tarefa.md"
printf '# Achados — %s\n' "$slug" > "$destino/achados.md"

# 1ª marca de sessão: o medir.sh conta o orquestrador a partir dela. Sem o id da sessão, a 1ª marca vem do
# orcamento-local.sh --tarefa, na 1ª leva.
sid=${CLAUDE_CODE_SESSION_ID:-}
sid=${sid//[^A-Za-z0-9._-]/}
[ -z "$sid" ] || printf '%s %s\n' "$(date +%s)" "$sid" > "$destino/sessoes"

{
  echo
  echo "## Foto inicial da árvore"
  echo '```'
  git log -1 --format='%h %cs %s' 2>/dev/null || echo "(fora de repositório git)"
  git status --porcelain 2>/dev/null || true
  echo '```'
} >> "$destino/registro.md"

echo "$destino"
