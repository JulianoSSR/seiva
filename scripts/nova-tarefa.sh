#!/usr/bin/env bash
# Cria a pasta de uma tarefa com registro, plano e achados a partir dos moldes da skill,
# e grava no registro a foto do `git status` de agora: o que já estava mexido antes da
# tarefa começar é de outra sessão, não desta.
#
# Uso: nova-tarefa.sh <pasta-de-trabalho> <slug>
# Exemplo: nova-tarefa.sh .claude/seiva bug-088-errors
set -eu

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <pasta-de-trabalho> <slug>" >&2
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
printf '# Achados — %s\n' "$slug" > "$destino/achados.md"

{
  echo
  echo "## Foto inicial da árvore"
  echo '```'
  git log -1 --format='%h %cs %s' 2>/dev/null || echo "(fora de repositório git)"
  git status --porcelain 2>/dev/null || true
  echo '```'
} >> "$destino/registro.md"

echo "$destino"
