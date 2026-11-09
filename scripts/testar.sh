#!/usr/bin/env bash
# seiva · JulianoSSR · MIT
# Suíte determinística; testes usam diretórios temporários e não chamam modelos.
set -uo pipefail
cd "$(dirname -- "$0")/.." || exit 2
falhas=0
bash scripts/checar-skill.sh || falhas=$((falhas+1))
python3 -m unittest discover -s testes -p 'test_*.py' -v || falhas=$((falhas+1))
for teste in testes/scripts/teste-*.sh; do
  bash "$teste" || falhas=$((falhas+1))
done
printf 'grupos com falha: %s\n' "$falhas"
[ "$falhas" -eq 0 ]
