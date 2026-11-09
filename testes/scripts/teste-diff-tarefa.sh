#!/usr/bin/env bash
# Testa scripts/diff-tarefa.sh num repositório git temporário: a trava de pasta (a de trabalho e a tarefas/ são
# recusadas antes de gravar o diff.patch) e o caso feliz (arquivo novo entra no diff). Sem commit.
# Uso: bash testes/scripts/teste-diff-tarefa.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
DT="$RAIZ/scripts/diff-tarefa.sh"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/cache"
export HOME="$T/home" XDG_CACHE_HOME="$T/cache"

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
nao_tem() {
  n=$((n + 1))
  case $2 in
    *"$3"*)
      erros=$((erros + 1))
      echo "FALHA: $1"
      printf '  | trecho proibido: %s\n  | texto: %s\n' "$3" "$2"
      ;;
  esac
}

R=$T/repo
mkdir -p "$R"
git -C "$R" init -q
printf 'echo oi\n' >"$R/a.sh"
roda() {
  SAI=$(cd "$R" && bash "$DT" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}

# --- uso errado ---------------------------------------------------------------------
roda "$R"
eq "sem arquivo: uso errado" 2 "$RC"
tem "sem arquivo: diz o uso" "$ERR" "uso:"

# --- D-a · a pasta de trabalho (ou a tarefas/) no lugar da pasta da tarefa: código 2, sem diff.patch ---------------
W=$T/trabalho
mkdir -p "$W/tarefas/2026-01-01-uma"
printf '# Registro\n' >"$W/tarefas/2026-01-01-uma/registro.md"
WR=$(cd -- "$W" && pwd -P)
roda "$W" a.sh
eq "D-a · pasta de trabalho: código 2" 2 "$RC"
eq "D-a · pasta de trabalho: stdout vazio" "" "$SAI"
eq "D-a · pasta de trabalho: a mensagem da trava" "diff-tarefa.sh: $WR é pasta de trabalho (tem tarefas/); <pasta-da-tarefa> pede a pasta da tarefa, $WR/tarefas/<tarefa>" "$ERR"
eq "D-a · pasta de trabalho: sem diff.patch" nao "$([ -e "$W/diff.patch" ] && echo sim || echo nao)"
roda "$W/tarefas/." a.sh
eq "D-a · tarefas/ por caminho com '.': código 2" 2 "$RC"
eq "D-a · tarefas/ por caminho com '.': a mensagem da trava" "diff-tarefa.sh: $WR/tarefas é a pasta tarefas/; <pasta-da-tarefa> pede uma tarefa dentro dela, $WR/tarefas/<tarefa>" "$ERR"
eq "D-a · tarefas/: sem diff.patch" nao "$([ -e "$W/tarefas/diff.patch" ] && echo sim || echo nao)"
roda "$W/tarefas/" a.sh
eq "D-a · tarefas/ com barra final: código 2" 2 "$RC"

# --- contrato novo: base verificável e escopo explícito antes da edição -----------------
# O arquivo já presente é a base completa, sem presumir que HEAD represente esta tarefa.
P="$W/tarefas/2026-01-01-uma"
(cd "$R" && python3 "$RAIZ/scripts/estado_tarefa.py" init "$P") || exit 2
(cd "$R" && bash "$RAIZ/scripts/base-tarefa.sh" "$P" --exclusive a.sh novo.sh nao-existe.sh) >/dev/null || exit 2
printf 'echo tarefa\n' >>"$R/a.sh"
printf 'echo oi\n' >"$R/novo.sh"
roda "$P" a.sh novo.sh
eq "feliz: código 0" 0 "$RC"
tem "feliz: a.sh aparece como alterado desde a base" "$SAI" "alterado   a.sh"
tem "feliz: novo.sh aparece como novo" "$SAI" "novo       novo.sh"
roda "$P" nao-existe.sh
eq "caminho solicitado ausente na base e entrega: erro" 2 "$RC"
tem "ausente: erro explica o arquivo" "$ERR" "arquivo solicitado ausente"

eq "feliz: diff.patch gravado na pasta da tarefa" sim "$([ -f "$W/tarefas/2026-01-01-uma/diff.patch" ] && echo sim)"
tem "feliz: o diff traz o conteúdo do arquivo novo" "$(cat "$W/tarefas/2026-01-01-uma/diff.patch")" "+echo oi"
nao_tem "feliz: nada de diff.patch na pasta de trabalho" "$(ls "$W")" "diff.patch"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
