#!/usr/bin/env bash
# Testa o scripts/checar-skill.sh da árvore de trabalho, numa cópia em pasta temporária.
# Uso: bash testes/scripts/teste-checar-skill.sh
# A cópia se chama "seiva" porque o checar-skill compara o nome da pasta.
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

n=0
erros=0

# Cópia nova da árvore, sem .git e sem a pasta de trabalho do repositório de verdade.
nova_copia() {
  rm -rf "$T/seiva"
  mkdir -p "$T/seiva" &&
    cp -r "$RAIZ/." "$T/seiva" &&
    rm -rf "$T/seiva/.git" "$T/seiva/.seiva"
}

# caso <descrição> <código esperado> <regex esperado na saída>
caso() {
  n=$((n + 1))
  local saida rc
  saida=$(bash "$T/seiva/scripts/checar-skill.sh" 2>&1)
  rc=$?
  if [ "$rc" -ne "$2" ] || ! printf '%s\n' "$saida" | grep -Eq "$3"; then
    erros=$((erros + 1))
    echo "FALHA: $1 (código $rc, esperado $2; padrão $3)"
    printf '%s\n' "$saida" | sed 's/^/  | /'
  fi
}

# (a) link quebrado dentro da pasta de trabalho não conta
nova_copia || exit 2
mkdir -p "$T/seiva/.seiva/tarefas/x" "$T/seiva/.claude"
printf '[some](nao-existe.md)\n' > "$T/seiva/.seiva/tarefas/x/plano.md"
printf '[some](tambem-nao-existe.md)\n' > "$T/seiva/.claude/y.md"
caso "pasta de trabalho (.seiva e .claude) é ignorada" 0 '^OK:'

# (b) link quebrado de verdade continua reprovando
nova_copia || exit 2
printf '[some](nao-existe.md)\n' > "$T/seiva/referencias/z.md"
caso "link quebrado em referencias/ reprova" 1 '^FALHA: link quebrado em \./referencias/z\.md'

# (c) teste com erro de sintaxe reprova
nova_copia || exit 2
mkdir -p "$T/seiva/testes/scripts"
printf 'if then\n' > "$T/seiva/testes/scripts/ruim.sh"
caso "sintaxe inválida em testes/scripts/ reprova" 1 '^FALHA: sintaxe em testes/scripts/ruim\.sh'

# (d) sem testes/scripts/ o script passa
nova_copia || exit 2
rm -rf "$T/seiva/testes/scripts"
caso "sem testes/scripts/ passa" 0 '^OK:'

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
