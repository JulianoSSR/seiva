#!/usr/bin/env bash
# Testa scripts/nova-tarefa.sh numa pasta temporária, fora de qualquer repositório: a trava de pasta (a pasta de tarefa
# e a tarefas/ são recusadas antes de criar algo) e o caso feliz (pasta nova ou vazia, e pasta de trabalho).
# Uso: bash testes/scripts/teste-nova-tarefa.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
NOVA="$RAIZ/scripts/nova-tarefa.sh"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/cache"
export HOME="$T/home" XDG_CACHE_HOME="$T/cache"
unset CLAUDE_CODE_SESSION_ID

n=0
erros=0
eq() {
  n=$((n + 1))
  if [ "$2" != "$3" ]; then
    erros=$((erros + 1))
    echo "FALHA: $1"
    printf '  | esperado: %s\n  | obtido:   %s\n' "$2" "$3"
  fi
}
tem() {
  n=$((n + 1))
  case $2 in
    *"$3"*) ;;
    *)
      erros=$((erros + 1))
      echo "FALHA: $1"
      printf '  | trecho: %s\n  | texto:  %s\n' "$3" "$2"
      ;;
  esac
}
roda() {
  SAI=$(cd "$T" && bash "$NOVA" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}
existe() { [ -e "$1" ] && echo sim || echo nao; }
dia=$(date +%F)

# --- uso errado ---------------------------------------------------------------------
roda "$T/x"
eq "sem slug: uso errado" 2 "$RC"
roda "$T/x" "Slug Ruim"
eq "slug inválido: código 2" 2 "$RC"
eq "slug inválido: nada criado" nao "$(existe "$T/x")"

# --- N-a · a pasta de tarefa (ou a tarefas/) no lugar da pasta de trabalho: código 2, sem <tarefa>/tarefas/ ----------
A=$T/tarefa-a
mkdir -p "$A"
printf '# Registro\n' >"$A/registro.md"
AR=$(cd -- "$A" && pwd -P)
roda "$A" x
eq "N-a · pasta de tarefa (registro.md): código 2" 2 "$RC"
eq "N-a · pasta de tarefa: stdout vazio" "" "$SAI"
eq "N-a · pasta de tarefa: a mensagem da trava" "nova-tarefa.sh: $AR é pasta de tarefa; nova-tarefa.sh pede a pasta de trabalho, a que contém tarefas/" "$ERR"
eq "N-a · pasta de tarefa: sem tarefas/ dentro" nao "$(existe "$A/tarefas")"
B=$T/tarefa-b
mkdir -p "$B"
printf '# Progresso\n' >"$B/progresso.md"
roda "$B" x
eq "N-a · pasta de tarefa (progresso.md): código 2" 2 "$RC"
eq "N-a · pasta de tarefa (progresso.md): sem tarefas/ dentro" nao "$(existe "$B/tarefas")"
roda "$A/" x
eq "N-a · pasta de tarefa com barra final: código 2" 2 "$RC"
roda "$A/../tarefa-a/." x
eq "N-a · pasta de tarefa por caminho com '..' e '.': código 2" 2 "$RC"
eq "N-a · pasta de tarefa por caminho com '..' e '.': sem tarefas/ dentro" nao "$(existe "$A/tarefas")"

# --- N-a · a tarefas/ no lugar da pasta de trabalho: código 2 e nomeia o pai ------------------------------------
W=$T/trabalho
mkdir -p "$W/tarefas/2026-01-01-uma"
printf '# Registro\n' >"$W/tarefas/2026-01-01-uma/registro.md"
WR=$(cd -- "$W" && pwd -P)
roda "$W/tarefas" x
eq "N-a · tarefas/: código 2" 2 "$RC"
eq "N-a · tarefas/: stdout vazio" "" "$SAI"
eq "N-a · tarefas/: a mensagem nomeia o pai" "nova-tarefa.sh: $WR/tarefas é a pasta tarefas/; nova-tarefa.sh pede a pasta que a contém, $WR" "$ERR"
eq "N-a · tarefas/: sem tarefas/ dentro" nao "$(existe "$W/tarefas/tarefas")"
roda "$W/tarefas/." x
eq "N-a · tarefas/ por caminho com '.': código 2" 2 "$RC"
eq "N-a · tarefas/ por caminho com '.': o pai sai resolvido" "$WR" "${ERR##*a contém, }"

# --- N-b · pasta vazia, pasta nova e pasta de trabalho: cria como hoje ----------------------------------------
V=$T/vazia
mkdir -p "$V"
roda "$V" x
eq "N-b · pasta vazia: código 0" 0 "$RC"
eq "N-b · pasta vazia: imprime o destino" "$V/tarefas/$dia-x" "$SAI"
eq "N-b · pasta vazia: registro.md criado" sim "$([ -f "$V/tarefas/$dia-x/registro.md" ] && echo sim)"
eq "N-b · pasta vazia: progresso.md criado" sim "$([ -f "$V/tarefas/$dia-x/progresso.md" ] && echo sim)"
eq "N-b · pasta vazia: relatorios/ criada" sim "$([ -d "$V/tarefas/$dia-x/relatorios" ] && echo sim)"
tem "N-b · pasta vazia: o registro traz a foto inicial" "$(cat "$V/tarefas/$dia-x/registro.md")" "## Foto inicial da árvore"
roda "$T/nova/fundo" y
eq "N-b · pasta que ainda não existe: código 0" 0 "$RC"
eq "N-b · pasta que ainda não existe: criada" sim "$([ -f "$T/nova/fundo/tarefas/$dia-y/registro.md" ] && echo sim)"
roda "$W" z
eq "N-b · pasta de trabalho com tarefas/: código 0" 0 "$RC"
eq "N-b · pasta de trabalho: a nova tarefa ao lado da antiga" sim "$([ -f "$W/tarefas/$dia-z/registro.md" ] && echo sim)"
roda "$W" z
eq "N-b · a mesma tarefa de novo: código 1, como hoje" 1 "$RC"
tem "N-b · a mesma tarefa de novo: diz que já existe" "$ERR" "já existe"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
