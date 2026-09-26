#!/usr/bin/env bash
# Impressão digital curta de cada fonte de lei do perfil.
# Serve para saber, sem reler nada, se alguma fonte mudou desde a última tarefa.
#
# Uso: impressao.sh FONTE [FONTE...]
#   FONTE = arquivo                 -> impressão do arquivo inteiro
#   FONTE = 'arquivo::Título'       -> impressão só da seção que começa no título "Título"
#                                      (até o próximo título do mesmo nível ou acima)
# Exemplo: impressao.sh CLAUDE.md 'CONSTITUICAO.md::PARTE I'
set -u

if [ "$#" -eq 0 ]; then
  echo "uso: $0 arquivo[::Título da seção] ..." >&2
  exit 2
fi

hash_stdin() {
  git hash-object --stdin 2>/dev/null || sha256sum | cut -d' ' -f1
}

for fonte in "$@"; do
  arquivo=${fonte%%::*}
  secao=""
  [ "$arquivo" != "$fonte" ] && secao=${fonte#*::}

  if [ ! -f "$arquivo" ]; then
    printf '%-12s  %s\n' 'AUSENTE' "$fonte"
    continue
  fi

  if [ -z "$secao" ]; then
    h=$(hash_stdin < "$arquivo")
  else
    # Linha começando com "#" dentro de bloco de código (comentário de shell) não é título.
    trecho=$(awk -v alvo="$secao" '
      /^[ \t]*(```|~~~)/ { cerca = !cerca }
      !cerca && /^#+[ \t]/ {
        match($0, /^#+/); nivel = RLENGTH
        titulo = substr($0, nivel + 1); sub(/^[ \t]+/, "", titulo)
        if (dentro && nivel <= nivel_alvo) exit
        if (!dentro && index(titulo, alvo) == 1) { dentro = 1; nivel_alvo = nivel }
      }
      dentro { print }
    ' "$arquivo")
    if [ -z "$trecho" ]; then
      printf '%-12s  %s\n' 'SEM-SECAO' "$fonte"
      continue
    fi
    h=$(printf '%s\n' "$trecho" | hash_stdin)
  fi
  printf '%s  %s\n' "${h:0:12}" "$fonte"
done
