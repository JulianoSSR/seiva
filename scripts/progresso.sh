#!/usr/bin/env bash
# seiva · JulianoSSR · MIT
# Interface compatível: estado.json canônico, progresso.md derivado.
# marcar N feita exige artefatos e --attempt ID ou --evidence para etapa mecânica.
# Conferir revalida artefatos, dependências e terminal; legado sem prova pede revalidação.
set -uo pipefail

uso() {
  echo "uso: progresso.sh <pasta-da-tarefa> marcar <0-9> <pendente|em-curso|feita|pulada[: nota]> [artefato...] [--attempt ID | --evidence TEXTO]" >&2
  echo "     progresso.sh <pasta-da-tarefa> conferir" >&2
  echo "     progresso.sh <pasta-de-trabalho> pendentes" >&2
  echo "     pasta errada (pendentes numa tarefa ou na tarefas/; marcar ou conferir numa pasta com tarefas/ ou na tarefas/) sai com 2, sem criar nada." >&2
  exit 2
}

[ "$#" -ge 2 ] || uso
pasta=${1%/}
acao=$2
shift 2
[ -d "$pasta" ] || { echo "a pasta não existe: $pasta" >&2; exit 2; }
abs=$(cd -- "$pasta" 2>/dev/null && pwd -P) || { echo "a pasta não existe: $pasta" >&2; exit 2; }

classe() {
  local sub
  if [ -d "$1/tarefas" ]; then
    echo trabalho
    return
  fi
  if [ "${1##*/}" = tarefas ]; then
    for sub in "$1"/*/; do
      if [ -f "${sub}registro.md" ] || [ -f "${sub}progresso.md" ]; then
        echo tarefas
        return
      fi
    done
  fi
  if [ -f "$1/progresso.md" ] || [ -f "$1/registro.md" ]; then echo tarefa
  else echo outra
  fi
}

classe_pasta=$(classe "$abs")
case $acao in
  pendentes)
    [ "$#" -eq 0 ] || uso
    if [ "$classe_pasta" = tarefas ]; then
      echo "progresso.sh: $abs é a pasta tarefas/; pendentes pede a pasta que a contém, $(dirname -- "$abs")" >&2
      exit 2
    fi
    if [ "$classe_pasta" = tarefa ]; then
      pai=$(dirname -- "$abs")
      msg="$abs é pasta de tarefa; pendentes pede a pasta de trabalho, a que contém tarefas/"
      if [ "$(basename -- "$pai")" = tarefas ]; then
        msg="$msg: $(dirname -- "$pai")"
      fi
      echo "$msg" >&2
      exit 2
    fi
    exec python3 "$(dirname -- "$0")/estado_tarefa.py" pending "$pasta"
    ;;
  marcar | conferir)
    if [ "$classe_pasta" = trabalho ]; then
      echo "progresso.sh: $abs é pasta de trabalho (tem tarefas/); $acao pede a pasta da tarefa, $abs/tarefas/<tarefa>" >&2
      [ ! -f "$abs/progresso.md" ] || echo "há um progresso.md solto em $abs: veio de um marcar errado e pode ser apagado à mão" >&2
      exit 2
    fi
    if [ "$classe_pasta" = tarefas ]; then
      echo "progresso.sh: $abs é a pasta tarefas/; $acao pede uma tarefa dentro dela, $abs/<tarefa>" >&2
      exit 2
    fi
    if [ "$acao" = marcar ]; then
      exec python3 "$(dirname -- "$0")/estado_tarefa.py" mark "$pasta" "$@"
    fi
    exec python3 "$(dirname -- "$0")/estado_tarefa.py" check "$pasta" "$@"
    ;;
  *) uso ;;
esac
