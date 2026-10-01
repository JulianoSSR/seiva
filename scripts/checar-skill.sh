#!/usr/bin/env bash
# Confere a própria skill antes de publicar uma versão: frontmatter, tamanho e links internos.
# Uso: bash scripts/checar-skill.sh   (a partir da raiz da skill)
set -u
cd "$(dirname "$0")/.." || exit 2
falhas=0
falha() { echo "FALHA: $*"; falhas=$((falhas + 1)); }

# Frontmatter: name igual ao nome da pasta, description com até 1024 caracteres.
nome=$(sed -n 's/^name: *//p' SKILL.md | head -1)
pasta=$(basename "$(pwd)")
[ "$nome" = "seiva" ] || falha "name no frontmatter é '$nome', esperado 'seiva'"
[ "$pasta" = "seiva" ] || echo "aviso: a pasta se chama '$pasta'; alguns harnesses exigem que seja igual ao name"

desc=$(awk '/^description: *\|/{f=1;next} f&&/^[a-z_-]+:/{exit} f{sub(/^  /,"");printf "%s ",$0}' SKILL.md)
tam=${#desc}
[ "$tam" -gt 0 ] || falha "description vazia"
[ "$tam" -le 1024 ] || falha "description com $tam caracteres (máximo 1024)"

# Corpo do SKILL.md abaixo de 500 linhas (recomendação do padrão Agent Skills).
linhas=$(wc -l < SKILL.md)
[ "$linhas" -lt 500 ] || falha "SKILL.md com $linhas linhas (máximo recomendado 500)"

# Links relativos em markdown apontam para arquivo ou pasta que existe.
# A pasta de trabalho da seiva (.seiva/) e a configuração local (.claude/) ficam de fora: não fazem parte da skill.
quebrados=$(
  find . -name '*.md' -not -path './.git/*' -not -path './.seiva/*' -not -path './.claude/*' | while read -r md; do
    dir=$(dirname "$md")
    grep -o '\]([^)#]*)' "$md" | sed 's/^](//; s/)$//' | while read -r alvo; do
      case "$alvo" in http*|mailto:*|'') continue ;; esac
      [ -e "$dir/$alvo" ] || echo "link quebrado em $md -> $alvo"
    done
  done
)
if [ -n "$quebrados" ]; then
  printf '%s\n' "$quebrados" | sed 's/^/FALHA: /'
  falhas=$((falhas + $(printf '%s\n' "$quebrados" | wc -l)))
fi

# Scripts e testes de scripts com sintaxe válida (o padrão sem arquivo é pulado).
for s in scripts/*.sh testes/scripts/*.sh; do
  [ -e "$s" ] || continue
  bash -n "$s" || falha "sintaxe em $s"
done

if [ "$falhas" -eq 0 ]; then
  echo "OK: description $tam caracteres, SKILL.md $linhas linhas, links e scripts em ordem"
else
  echo "$falhas falha(s)"
  exit 1
fi
