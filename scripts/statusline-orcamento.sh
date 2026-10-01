#!/usr/bin/env bash
# Statusline do orçamento vivo da seiva. Só no Claude Code, e só quando o USUÁRIO a instala
# (bloco de instalação em referencias/harness.md, seção "Orçamento vivo"). Nenhum script da seiva escreve no settings.json.
#
# O Claude Code chama este script a cada mensagem e manda um JSON no stdin, com rate_limits.five_hour e .seven_day
# (used_percentage, resets_at em epoch), context_window.used_percentage e session_id. O script:
#   1. junta esses números com os do arquivo anterior, janela por janela;
#   2. grava ${XDG_CACHE_HOME:-$HOME/.cache}/seiva/orcamento.json (modo 600, troca atômica);
#   3. imprime uma linha para a barra: "5h 42% até 14:30 · 7d 18% · ctx 35%".
#
# Junção, por janela (duas sessões abertas gravam no mesmo arquivo):
#   - entrada sem dado da janela: fica a janela gravada;
#   - entrada com dado: fica a de maior "reinicia"; se for a mesma janela, fica o maior "usado" (o uso só cresce dentro
#     da janela, então uma sessão atrasada não baixa o número); "visto_em" acompanha a escolhida;
#   - arquivo anterior inválido ou de outra "versao": conta como ausente;
#   - "contexto" e "sessao" vêm sempre da entrada.
# Com 70% ou mais na janela de 5 horas, a linha ganha "estourou? sessão nova + retome <tarefa>", com a tarefa lida do
# arquivo "retomar" (que o scripts/orcamento.sh --tarefa grava, só com [A-Za-z0-9._-], até 40 caracteres).
#
# Garantias: só bash e jq; sem rede; sai sempre com 0; nada no stderr. Entrada inválida imprime
# "seiva: orçamento sem dado" e não mexe no arquivo. Sem jq, imprime "seiva: sem jq".
set -uo pipefail
umask 077
exec 2>/dev/null
export LC_ALL=C

command -v jq >/dev/null || { echo "seiva: sem jq"; exit 0; }

base=${XDG_CACHE_HOME:-}
[ -n "$base" ] || { [ -n "${HOME:-}" ] && base=$HOME/.cache; }
dir=${base:+$base/seiva}

entrada=$(head -c 1048576)

anterior=/dev/null
[ -n "$dir" ] && [ -r "$dir/orcamento.json" ] && anterior=$dir/orcamento.json

tarefa=""
# O "retomar" vale por 6 horas depois da última leva (o orcamento.sh o regrava a cada uma). Mais velho,
# a tarefa provavelmente acabou: a dica volta ao texto genérico. Sem `stat -c` (macOS), vale como velho.
mtime=$(stat -c %Y "$dir/retomar" 2>/dev/null) || mtime=0
case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
if [ -n "$dir" ] && [ -r "$dir/retomar" ] && [ $(( $(date +%s) - mtime )) -le 21600 ]; then
  p=""
  IFS= read -r -n 4096 p < "$dir/retomar"
  p=${p%/registro.md}
  p=${p##*/}
  p=${p//[^A-Za-z0-9._-]/}
  tarefa=${p:0:40}
fi

saida=$(printf '%s' "$entrada" | jq -r --rawfile ant "$anterior" --arg script "$0" --arg tarefa "$tarefa" '
  def num: if type == "number" then . else null end;
  def vazia: {usado: null, reinicia: null, visto_em: null};
  def anterior($prev; $k):
    ($prev // {}) | .[$k]
    | if type == "object" then {usado: (.usado | num), reinicia: (.reinicia | num), visto_em: (.visto_em | num)} else vazia end;
  def juntar($prev; $k; $ent; $agora):
    anterior($prev; $k) as $a
    | ($ent | if type == "object" then {usado: (.used_percentage | num), reinicia: (.resets_at | num)} else {usado: null, reinicia: null} end) as $n
    | {usado: $n.usado, reinicia: $n.reinicia, visto_em: $agora} as $novo
    | if $n.usado == null then $a
      elif $a.usado == null then $novo
      elif ($n.reinicia // 0) > ($a.reinicia // 0) then $novo
      elif ($n.reinicia // 0) < ($a.reinicia // 0) then $a
      elif $n.usado >= $a.usado then $novo
      else $a end;
  def pct: if . == null then "--" else "\((. * 10 + 1e-9 | floor) / 10)%" end;
  def valida($agora): .usado != null and (.reinicia == null or .reinicia > $agora);
  (now | floor) as $agora
  | if type != "object" then error("entrada") else . end
  | ($ant | try fromjson catch null | if type == "object" and .versao == 1 then . else null end) as $prev
  | (.session_id | if type == "string" then gsub("[^A-Za-z0-9._-]"; "") | .[0:64] else "" end) as $sid
  | (.rate_limits | if type == "object" then . else {} end) as $rl
  | juntar($prev; "cinco_horas"; $rl.five_hour; $agora) as $c5
  | juntar($prev; "sete_dias"; $rl.seven_day; $agora) as $d7
  | {usado: (.context_window | if type == "object" then .used_percentage | num else null end), sessao: $sid} as $ctx
  | {versao: 1, harness: "claude-code", script: $script, gravado_em: $agora, sessao: $sid,
     cinco_horas: $c5, sete_dias: $d7, contexto: $ctx} as $arq
  | ($c5 | valida($agora)) as $c5ok
  | ("5h " + (if $c5ok then ($c5.usado | pct) + " até " + (if $c5.reinicia == null then "--:--" else ($c5.reinicia | strflocaltime("%H:%M")) end) else "--" end)
     + " · 7d " + (if ($d7 | valida($agora)) then ($d7.usado | pct) else "--" end)
     + " · ctx " + ($ctx.usado | pct)
     + (if $c5ok and $c5.usado >= 70 then " · estourou? sessão nova + retome " + (if $tarefa == "" then "pelo registro.md" else $tarefa end) else "" end)) as $linha
  | ($arq | tojson), $linha
') || saida=""

json="" linha=""
{ IFS= read -r json; IFS= read -r linha; } <<< "$saida"
if [ -z "$json" ] || [ -z "$linha" ]; then
  echo "seiva: orçamento sem dado"
  exit 0
fi

# Gravação: temporário na mesma pasta e troca atômica. Falha ao gravar não tira a linha da barra.
if [ -n "$dir" ] && mkdir -p "$dir" && tmp=$(mktemp "$dir/.orcamento.XXXXXX"); then
  if printf '%s\n' "$json" > "$tmp" && mv -f "$tmp" "$dir/orcamento.json"; then
    :
  else
    rm -f "$tmp"
  fi
fi

printf '%s\n' "$linha"
exit 0
