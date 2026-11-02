#!/usr/bin/env bash
# seiva · JulianoSSR · MIT
# Checklist das etapas 0 a 9 de uma tarefa, com o hash dos artefatos de cada etapa feita. É o que garante, numa sessão
# nova, que etapa feita não roda de novo: quem retoma confere aqui e segue da próxima.
#
# Uso:
#   progresso.sh <pasta-da-tarefa> marcar <etapa> <status> [artefato...]
#       etapa: 0 a 9. status: pendente | em-curso | feita | pulada, e pode trazer nota depois de dois-pontos
#       ("em-curso: rodada 1/2 · leva adversario, seguranca"). Com feita, grava o sha256 (12 primeiros) de cada
#       artefato. Caminho relativo é relativo à pasta da tarefa; o resto vai absoluto.
#   progresso.sh <pasta-da-tarefa> conferir
#       Uma linha por etapa que não está pendente, o hash de cada artefato de etapa feita conferido de novo, o tamanho
#       estimado do contexto-tarefa.md e, por último, "PROXIMA <n> <nome>" (a 1ª etapa nem feita nem pulada) ou
#       "PROXIMA nenhuma". Sai com 1 se algum artefato mudou ou sumiu.
#   progresso.sh <pasta-de-trabalho> pendentes
#       As tarefas de <pasta-de-trabalho>/tarefas/ com a etapa 9 por fazer, da mais recente para a mais antiga (até 5).
#
# Hash que mudou não manda refazer a etapa: manda olhar o artefato (outra sessão, ou uma rodada de correção, pode tê-lo
# mudado de propósito). Uso errado sai com 2, e inclui apontar a pasta errada: pendentes numa pasta de tarefa ou na
# própria tarefas/ (a mensagem nomeia a pasta que a contém), ou marcar e conferir numa pasta de trabalho (a que tem
# tarefas/) ou na tarefas/. A tarefas/ é a pasta de nome tarefas com alguma subpasta que tenha registro.md ou
# progresso.md; o caminho é resolvido antes de classificar ("." e ".." e link simbólico caem no mesmo lugar). Nesses
# casos nada é lido nem criado.
set -uo pipefail

uso() {
  echo "uso: progresso.sh <pasta-da-tarefa> marcar <0-9> <pendente|em-curso|feita|pulada[: nota]> [artefato...]" >&2
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
# O caminho resolvido: a classificação e as mensagens usam este, não o que foi digitado.
abs=$(cd -- "$pasta" 2>/dev/null && pwd -P) || { echo "a pasta não existe: $pasta" >&2; exit 2; }

hash12() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum <"$1" | cut -c1-12
  else
    shasum -a 256 <"$1" | cut -c1-12
  fi
}
caminho() { case $1 in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$pasta/$1" ;; esac; }
# Que pasta é esta, pela raiz dela (caminho já resolvido): trabalho (tem tarefas/, e isso vence sempre), tarefas (o nome
# é tarefas e alguma subpasta tem registro.md ou progresso.md; um progresso.md solto na raiz dela não a muda), tarefa
# (tem progresso.md ou registro.md) ou outra (segue como antes em cada ação).
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

if [ "$acao" = pendentes ]; then
  [ "$#" -eq 0 ] || uso
  classe_pasta=$(classe "$abs")
  if [ "$classe_pasta" = tarefas ]; then
    echo "progresso.sh: $abs é a pasta tarefas/; pendentes pede a pasta que a contém, $(dirname -- "$abs")" >&2
    exit 2
  fi
  if [ "$classe_pasta" = tarefa ]; then
    pai=$(dirname -- "$abs")
    msg="$abs é pasta de tarefa; pendentes pede a pasta de trabalho, a que contém tarefas/"
    # Só nomeia a pasta de trabalho quando a tarefa está em <trabalho>/tarefas/<tarefa>; fora disso não inventa caminho.
    if [ "$(basename -- "$pai")" = tarefas ]; then
      msg="$msg: $(dirname -- "$pai")"
    fi
    echo "$msg" >&2
    exit 2
  fi
  achou=0
  while IFS= read -r p; do
    p=${p%/}
    [ -f "$p/progresso.md" ] || continue
    linha9=$(grep -E '^\| 9 ' "$p/progresso.md" | head -n 1)
    case $linha9 in *'| feita'* | *'| pulada'*) continue ;; esac
    atual=$(awk -F'|' '/^\| [0-9] / { s = $3; gsub(/^ +| +$/, "", s); if (s !~ /^(feita|pulada)/) { e = $2; gsub(/^ +| +$/, "", e); print e " · " s; exit } }' "$p/progresso.md")
    printf '%s · %s · mexida em %s\n' "$p" "${atual:-sem etapa}" "$(date -r "$p/progresso.md" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    achou=$((achou + 1))
    [ "$achou" -ge 5 ] && break
  done < <(ls -td -- "$pasta"/tarefas/*/ 2>/dev/null | head -n 20)
  [ "$achou" -gt 0 ] || echo "nenhuma tarefa por terminar em $pasta/tarefas"
  exit 0
fi

case $acao in
  marcar | conferir)
    classe_pasta=$(classe "$abs")
    if [ "$classe_pasta" = trabalho ]; then
      echo "progresso.sh: $abs é pasta de trabalho (tem tarefas/); $acao pede a pasta da tarefa, $abs/tarefas/<tarefa>" >&2
      [ ! -f "$abs/progresso.md" ] || echo "há um progresso.md solto em $abs: veio de um marcar errado e pode ser apagado à mão" >&2
      exit 2
    fi
    if [ "$classe_pasta" = tarefas ]; then
      echo "progresso.sh: $abs é a pasta tarefas/; $acao pede uma tarefa dentro dela, $abs/<tarefa>" >&2
      exit 2
    fi
    ;;
esac

arq=$pasta/progresso.md
if [ ! -f "$arq" ]; then
  [ "$acao" = marcar ] || { echo "$arq não existe: a tarefa é de antes do progresso.md; retome pelo registro.md" >&2; exit 2; }
  aqui=$(cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd) || exit 2
  slug=${pasta##*/}
  sed -e "s/{{SLUG}}/$slug/g" "$aqui/moldes/progresso.md" >"$arq" || exit 2
fi

case $acao in
  marcar)
    [ "$#" -ge 2 ] || uso
    etapa=$1
    status=$2
    shift 2
    case $etapa in [0-9]) ;; *) uso ;; esac
    case $status in pendente | em-curso | feita | pulada | pendente:* | em-curso:* | feita:* | pulada:*) ;; *) uso ;; esac
    status=${status//|//}
    artefatos=""
    if [ "${status%%:*}" = feita ]; then
      for a in "$@"; do
        case $a in *'|'* | *','* | *' '*) echo "artefato com |, vírgula ou espaço no nome: $a" >&2; exit 2 ;; esac
        f=$(caminho "$a")
        [ -f "$f" ] || { echo "artefato não existe: $f" >&2; exit 2; }
        artefatos+="${artefatos:+, }$a@$(hash12 "$f")"
      done
    fi
    quando=$(date '+%Y-%m-%d %H:%M')
    tmp=$(mktemp "$arq.XXXXXX") || exit 2
    if awk -v e="$etapa" -v s="$status" -v q="$quando" -v a="$artefatos" -F'|' '
      $0 ~ "^\\| " e " " { nome = $2; gsub(/^ +| +$/, "", nome); print "| " nome " | " s " | " q " | " a " |"; feito = 1; next }
      { print }
      END { exit !feito }' "$arq" >"$tmp"; then
      mv -f "$tmp" "$arq"
      echo "etapa $etapa: $status${artefatos:+ · $artefatos}"
    else
      rm -f "$tmp"
      echo "não achei a linha da etapa $etapa em $arq" >&2
      exit 2
    fi
    ;;
  conferir)
    [ "$#" -eq 0 ] || uso
    falhas=0
    proxima=""
    while IFS='|' read -r _ nome status quando artefatos _; do
      nome=$(printf '%s' "$nome" | sed 's/^ *//; s/ *$//')
      status=$(printf '%s' "$status" | sed 's/^ *//; s/ *$//')
      artefatos=$(printf '%s' "$artefatos" | sed 's/^ *//; s/ *$//')
      case $status in
        feita*) ;;
        pulada*) echo "$nome · $status"; continue ;;
        pendente*)
          [ -n "$proxima" ] || proxima=$nome
          continue
          ;;
        *)
          [ -n "$proxima" ] || proxima=$nome
          echo "$nome · $status"
          continue
          ;;
      esac
      notas=""
      IFS=',' read -ra lista <<<"$artefatos"
      for item in ${lista[@]+"${lista[@]}"}; do
        item=$(printf '%s' "$item" | sed 's/^ *//; s/ *$//')
        [ -n "$item" ] || continue
        a=${item%@*}
        gravado=${item##*@}
        f=$(caminho "$a")
        if [ ! -f "$f" ]; then
          notas+=" · $a SUMIU"
          falhas=$((falhas + 1))
        elif [ "$(hash12 "$f")" != "$gravado" ]; then
          notas+=" · $a MUDOU depois de feita (olhe o artefato; não refaça a etapa)"
          falhas=$((falhas + 1))
        else
          notas+=" · $a confere"
        fi
      done
      echo "$nome · $status${notas}"
    done < <(grep -E '^\| [0-9] ' "$arq")
    ctx=$pasta/contexto-tarefa.md
    if [ -f "$ctx" ]; then
      bytes=$(wc -c <"$ctx" | tr -d ' ')
      tokens=$((bytes * 10 / 35))
      aviso=""
      [ "$tokens" -gt 1500 ] && aviso=" · ACIMA do alvo: enxugue antes de parar"
      echo "contexto-tarefa.md ≈ $tokens tokens (estimativa por bytes; alvo até 1.500)$aviso"
    else
      echo "contexto-tarefa.md não existe: escreva antes de parar"
    fi
    echo "PROXIMA ${proxima:-nenhuma}"
    [ "$falhas" -eq 0 ] || exit 1
    ;;
  *) uso ;;
esac
