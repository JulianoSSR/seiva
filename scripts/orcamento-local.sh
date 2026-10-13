#!/usr/bin/env bash
# Orçamento vivo sem statusline. Lê os transcripts locais do Claude Code, que o terminal e o app desktop escrevem do
# mesmo jeito (~/.claude/projects/**/*.jsonl), estima o uso da janela de 5 horas e mede o contexto da sessão atual.
# Grava o resultado no formato do orcamento.json, com o campo "fonte", e passa a decisão ao scripts/orcamento.sh, que
# continua sendo o único que decide entre ok, restrito e parar. Não precisa de statusline, de hook nem de terminal.
#
# Uso: orcamento-local.sh [--tarefa <pasta-da-tarefa>] [--sessao <id>] [--calibrar <pct> [--em <hora>] | --calibrar auto]
#   --tarefa          repassado ao orcamento.sh, que grava o "retomar" da barra
#   --sessao          a sessão cujo contexto se mede. Padrão: $CLAUDE_CODE_SESSION_ID (o app desktop define; medido em
#                     2026-10-13). Sem ela, o transcript mais recente da pasta do projeto, com o aviso "sessão deduzida"
#   --calibrar <pct>  leitura do /usage (ou da página de uso do claude.ai): <pct> é o uso da janela de 5 horas que
#                     ele mostrou (de 10 a 100). Vira um ponto de calibração, como um limite batido
#   --em <hora>       quando a leitura foi feita: epoch ou ISO em UTC (2026-10-13T14:04:42.667Z, como o relatório do
#                     /usage traz). Sem ela, agora. Conta só o que a janela tinha gastado até aquela hora
#   --calibrar auto   refaz a calibração automática varrendo os transcripts dos últimos 30 dias
#
# Variáveis: PESO_CACHE_LEITURA (padrão 0.01), SEIVA_JANELA_CONTEXTO (tokens; sem ela, 1 milhão para o modelo que já
# passou de 200 mil de contexto em algum transcript e 200 mil para os outros), SEIVA_TRANSCRIPTS (~/.claude/projects).
#
# Saída: a linha do orcamento.sh com a fonte no fim. Códigos iguais aos dele: 0, 10 (restrito), 20 (parar); 2 é uso errado.
#
# Como estima (detalhe e limites em referencias/harness.md, seção "Orçamento vivo"):
#   - cada resposta pesa entrada + saída + escrita de cache + PESO_CACHE_LEITURA × leitura de cache, contada uma vez
#     (o transcript repete a mesma resposta numa linha por bloco de conteúdo; a chave é message.id + requestId);
#   - a janela começa na 1ª resposta depois do fim da anterior, arredondada para baixo em 10 minutos, e dura 5 horas.
#     Quando a conta bateu no limite, a mensagem "You've hit your session limit · resets <hora> (<fuso>)" dá a janela exata;
#   - o percentual divide os tokens da janela pelo limite calibrado. Cada vez que a conta bateu no limite, o total da
#     janela até ali vale 100%; cada leitura do /usage vale o percentual lido. O limite é o MENOR dos 5 pontos mais
#     recentes: freio conservador. (Em 2026-10-13 a mediana dos 20 limites anteriores dava 40% quando o /usage dava 73%.)
#     Com leitura do /usage dentro da janela aberta, ela é a âncora: o percentual parte do valor lido, e só o gasto
#     depois da leitura é estimado (duas leituras de 2026-10-13 não fecharam com peso nenhum: a janela tinha gasto
#     que os transcripts não veem).
#   - o contexto é o tamanho da última resposta da sessão (entrada + leitura e escrita de cache) sobre a janela do modelo.
#   O percentual é ESTIMADO: a contabilidade da assinatura não é pública. É freio, não medidor oficial.
#
# Arquivos, em ${XDG_CACHE_HOME:-$HOME/.cache}/seiva/, modo 600: orcamento-local.json (o estado) e calibracao.json.
# Do transcript só saem números, horários, o nome do modelo e o texto do aviso de limite: nenhum texto de conversa.
set -uo pipefail
export LC_ALL=C
umask 077

uso() { echo "uso: orcamento-local.sh [--tarefa <pasta-da-tarefa>] [--sessao <id>] [--calibrar <pct> [--em <hora>] | --calibrar auto]" >&2; exit 2; }

tarefa=""
sessao=""
calibrar=""
em=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --tarefa | --sessao | --calibrar | --em)
      [ "$#" -ge 2 ] && [ -n "$2" ] || uso
      case $1 in
        --tarefa) tarefa=$2 ;;
        --sessao) sessao=$2 ;;
        --calibrar) calibrar=$2 ;;
        --em) em=$2 ;;
      esac
      shift 2
      ;;
    *) uso ;;
  esac
done
case $calibrar in
  '' | auto) ;;
  *[!0-9.]* | *.*.* | .*) uso ;;
  *)
    awk -v p="$calibrar" 'BEGIN { exit !(p + 0 >= 10 && p + 0 <= 100) }' ||
      { echo "--calibrar: o percentual vai de 10 a 100 (abaixo de 10, o erro da conta fica grande demais)" >&2; exit 2; }
    ;;
esac

if [ -n "$em" ]; then
  case $calibrar in '' | auto) echo "--em só vale com --calibrar <pct>" >&2; exit 2 ;; esac
  case $em in
    *[!0-9]*) em=$(jq -nr --arg t "$em" '$t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2>/dev/null) || em="" ;;
  esac
  [ -n "$em" ] || { echo "--em: use epoch ou ISO em UTC, como 2026-10-13T14:04:42Z" >&2; exit 2; }
fi

pcl=${PESO_CACHE_LEITURA:-0.01}
awk -v p="$pcl" 'BEGIN { exit !(p ~ /^[0-9]*\.?[0-9]+$/ && p + 0 <= 1) }' ||
  { echo "PESO_CACHE_LEITURA precisa ser um número de 0 a 1 (veio '$pcl')" >&2; exit 2; }
janela_env=${SEIVA_JANELA_CONTEXTO:-}
case $janela_env in '' | *[!0-9]*) janela_env=0 ;; esac

case $0 in */*) aqui=${0%/*} ;; *) aqui=. ;; esac
lei="$aqui/orcamento.sh"
[ -r "$lei" ] || { echo "ORCAMENTO desligado — o orcamento.sh não está ao lado do orcamento-local.sh"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "ORCAMENTO desligado — jq não está instalado · fonte transcripts"; exit 0; }

base=${XDG_CACHE_HOME:-}
[ -n "$base" ] || { [ -n "${HOME:-}" ] && base=$HOME/.cache; }
[ -n "$base" ] || { echo "ORCAMENTO desligado — sem HOME nem XDG_CACHE_HOME para gravar o estado"; exit 0; }
dir=$base/seiva
mkdir -p -- "$dir" 2>/dev/null || { echo "ORCAMENTO desligado — não consegui criar $dir"; exit 0; }
arq=$dir/orcamento-local.json
cal=$dir/calibracao.json
stl=$dir/orcamento.json
trans=${SEIVA_TRANSCRIPTS:-${HOME:-/nonexistent}/.claude/projects}
agora=$(date +%s)
[ -n "$em" ] || em=$agora
avisos=""

# Sessão: a do harness; sem ela, a do transcript mais recente na pasta do projeto (o nome da pasta é o caminho com
# tudo que não é letra ou número trocado por hífen).
[ -n "$sessao" ] || sessao=${CLAUDE_CODE_SESSION_ID:-}
sessao=${sessao//[^A-Za-z0-9._-]/}
if [ -z "$sessao" ] && [ -d "$trans" ]; then
  proj=$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9]/-/g')
  ultimo=$(ls -t -- "$trans/$proj"/*.jsonl 2>/dev/null | head -n 1)
  if [ -n "$ultimo" ]; then
    sessao=${ultimo##*/}
    sessao=${sessao%.jsonl}
    sessao=${sessao//[^A-Za-z0-9._-]/}
    avisos+=" · sessão deduzida pelo transcript mais recente do projeto"
  fi
fi

calj=null
if [ -r "$cal" ]; then
  calj=$(jq -c 'if type == "object" and .versao == 1 then . else null end' "$cal" 2>/dev/null) || calj=null
  [ -n "$calj" ] || calj=null
fi

# Quanto varrer: 30 dias na 1ª vez e no --calibrar auto; depois, desde a última varredura mais 5 horas, no mínimo
# 24 horas (o encadeamento das janelas precisa do dia anterior).
minutos=1440
recalibrou=0
if [ "$calibrar" = auto ] || [ "$calj" = null ]; then
  minutos=43200
  recalibrou=1
else
  desde=$(printf '%s' "$calj" | jq -r '.varrido_ate // 0 | if type == "number" then floor else 0 end')
  m=$(((agora - desde) / 60 + 300))
  [ "$m" -gt "$minutos" ] && minutos=$m
  [ "$minutos" -gt 43200 ] && minutos=43200
fi

tmp=$(mktemp "$dir/.registros.XXXXXX") || { echo "ORCAMENTO desligado — não consegui criar arquivo temporário em $dir"; exit 0; }
tmpj=""
tmpc=""
trap 'rm -f -- "$tmp" ${tmpj:+"$tmpj"} ${tmpc:+"$tmpc"}' EXIT

# Extração: uma linha pequena por resposta (k=u) e por aviso de limite da janela de 5 horas (k=h).
# s: 1 = transcript desta sessão, 2 = subagente desta sessão, 0 = outra.
if [ -d "$trans" ]; then
  find "$trans" -type f -name '*.jsonl' -mmin "-$minutos" -exec jq -cR --arg sid "$sessao" '
    def epoch: sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null;
    fromjson? | select(type == "object" and .type == "assistant")
    | (.timestamp | if type == "string" then epoch else null end) as $ts | select($ts != null)
    | if .apiErrorStatus != null or .isApiErrorMessage == true then
        ((.message.content // []) | if type == "array" then ((.[0].text? // "") | tostring) else tostring end) as $t
        | select($t | test("session limit")) | {k: "h", ts: $ts, t: ($t | .[0:200])}
      elif (.message.usage | type) == "object" then
        input_filename as $f
        | {k: "u", ts: $ts, id: ((.message.id // "" | tostring) + ":" + (.requestId // "" | tostring)),
           m: (.message.model // "" | tostring | .[0:60]), sc: (.isSidechain == true),
           s: (if $sid == "" then 0 elif ($f | endswith("/" + $sid + ".jsonl")) then 1
               elif ($f | contains("/" + $sid + "/")) then 2 else 0 end),
           u: (.message.usage | [.input_tokens, .output_tokens, .cache_creation_input_tokens, .cache_read_input_tokens]
               | map(if type == "number" then . else 0 end))}
      else empty end
  ' {} + >"$tmp" 2>/dev/null
else
  avisos+=" · pasta de transcripts não encontrada: $trans"
fi

# O horário do aviso de limite vem no fuso do usuário, com o nome dele entre parênteses. A conta da hora usa esse fuso.
tz=$(jq -r 'select(.k == "h") | .t | (capture("\\((?<z>[A-Za-z0-9_/+-]+)\\)\\s*$").z? // empty)' "$tmp" 2>/dev/null | tail -n 1)

stlj=null
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" != claude-desktop ] && [ -r "$stl" ]; then
  stlj=$(jq -c --argjson agora "$agora" '
    if type == "object" and .versao == 1 and (.cinco_horas.usado | type) == "number"
       and ((.gravado_em // 0) | type == "number" and . >= $agora - 600) then . else null end' "$stl" 2>/dev/null) || stlj=null
  [ -n "$stlj" ] || stlj=null
fi

saida=$(env ${tz:+TZ="$tz"} jq -s -r \
  --argjson agora "$agora" --argjson pcl "$pcl" --argjson janela_env "$janela_env" --argjson inicio "$((agora - minutos * 60))" \
  --arg sid "$sessao" --argjson cal "$calj" --argjson stl "$stlj" --arg calibrar "$calibrar" --argjson em "$em" --arg script "$0" '
  def mediana: sort | .[(length - 1) / 2 | floor];
  def fmt: if . >= 1000000 then "\((. / 100000 | floor) / 10) mi" else "\(. / 1000 | floor) mil" end | gsub("\\."; ",");
  def pct: (. * 10 + 1e-9 | floor) / 10;
  # Hora de reinício do aviso ("resets 1:10pm", "resets 11am") como epoch: a próxima ocorrência depois do aviso, até 5h10.
  def reinicio($ts):
    (capture("resets (?<h>[0-9]{1,2})(:(?<m>[0-9]{2}))?(?<ap>am|pm)")? // null) as $c
    | if $c == null then null else
        ((($c.h | tonumber) % 12) + (if $c.ap == "pm" then 12 else 0 end)) as $H
        | (($c.m // "0") | tonumber) as $M
        | ($ts | floor) as $t
        | (($t | localtime | mktime) - $t) as $off
        | ($t | localtime) as $l
        | ([$l[0], $l[1], $l[2], $H, $M, 0, 0, 0] | mktime) - $off
        | if . <= $t then . + 86400 else . end
        | if . - $t <= 18600 then . else null end
      end;

  (map(select(.k == "u")) | unique_by(.id) | map(. + {x: (.u[0] + .u[1] + .u[2]), y: .u[3]}) | sort_by(.ts)) as $us
  | (map(select(.k == "h")) | map(.ts as $t | {ts: $t, r: (.t | reinicio($t))}) | map(select(.r != null))
     | group_by(.r) | map({r: .[0].r, hit: (map(.ts) | min)})) as $hits

  # Janelas em sequência; a de um aviso de limite manda sobre a estimada.
  | (reduce $us[] as $e ({ini: 0, fim: 0, x: 0, y: 0};
      ([$hits[] | select(.r - 18000 <= $e.ts and $e.ts < .r)] | first) as $a
      | if $a != null then
          (if .fim == $a.r then .x += $e.x | .y += $e.y else {ini: ($a.r - 18000), fim: $a.r, x: $e.x, y: $e.y} end)
        elif $e.ts < .fim then .x += $e.x | .y += $e.y
        else (($e.ts / 600 | floor) * 600) as $i | {ini: $i, fim: ($i + 18000), x: $e.x, y: $e.y}
        end)) as $bloco
  | ($bloco.fim > $agora) as $aberta
  | ($bloco.x + $pcl * $bloco.y) as $w

  # Pontos de calibração: janela inteira dentro da varredura e aberta por uso que aparece nos transcripts (até 10 min
  # depois do início). Janela aberta pelo claude.ai ou por outra máquina sairia com total baixo demais.
  | ([$hits[] | select(.r - 18000 >= $inicio) | . as $h
      | [$us[] | select(.ts >= $h.r - 18000 and .ts <= $h.hit)] as $j
      | select(($j | length) > 0 and (($j | map(.ts) | min) - ($h.r - 18000)) < 600)
      | {r: $h.r, hit: $h.hit, x: ($j | map(.x) | add), y: ($j | map(.y) | add)}]) as $novos
  | ((if $calibrar == "auto" then [] else ($cal.pontos // []) end) + $novos | unique_by(.r) | sort_by(.r) | .[-30:]) as $pontos
  # Leitura do /usage: o percentual lido em $em, contra o total da janela até $em.
  | (if $calibrar != "" and $calibrar != "auto" then
       ([$us[] | select(.ts >= $bloco.ini and .ts <= $em)]) as $ate
       | (if $aberta and $em >= $bloco.ini and $em <= $agora and ($ate | length) > 0
          then {em: $em, pct: ($calibrar | tonumber), x: ($ate | map(.x) | add), y: ($ate | map(.y) | add)} else "erro" end)
     else null end) as $nova
  | if $nova == "erro" then "erro", "--calibrar: a hora da leitura não cai na janela de 5 horas aberta nos transcripts (ou não há janela aberta agora)"
    else
  ((($cal.leituras // []) + (if $nova != null then [$nova] else [] end)) | group_by(.em) | map(last) | sort_by(.em) | .[-10:]) as $leituras
  # Cada ponto estima o limite (limite batido = 100%; leitura = o percentual lido). Vale o menor dos 5 mais recentes.
  | (([$pontos[] | {t: .hit, l: (.x + $pcl * .y), k: "l"}] + [$leituras[] | {t: .em, l: ((.x + $pcl * .y) / (.pct / 100)), k: "u"}])
     | map(select(.l > 0)) | sort_by(.t) | .[-5:]) as $rec
  | (if ($rec | length) == 0 then null else
      ($rec | map(.l)) as $v | ($v | add / length) as $m
      | ($rec | map(select(.k == "l")) | length) as $nl | ($rec | map(select(.k == "u")) | length) as $nu
      | {limite: ($v | min),
         rotulo: ("menor de \($v | length) ponto\(if ($v | length) > 1 then "s" else "" end): \($nl) limite\(if $nl == 1 then "" else "s" end) batido\(if $nl == 1 then "" else "s" end) e \($nu) leitura\(if $nu == 1 then "" else "s" end) do /usage"
                  + (if ($v | length) >= 3 and $m > 0 then ", dispersão \(($v | map((. - $m) * (. - $m)) | add / length | sqrt) / $m * 100 | floor)%" else "" end))}
     end) as $lim

  # Contexto: o da última resposta do transcript desta sessão.
  | (($cal.contexto_max // {}) as $antes
     | reduce ($us[] | {m, c: (.u[0] + .u[2] + .u[3])}) as $e ($antes;
         .[$e.m] = ([(.[$e.m] // 0), $e.c] | max))) as $ctxmax
  | ($us | map(select(.s == 1 and (.sc | not))) | last) as $ult
  | (if $ult == null then null else ($ult.u[0] + $ult.u[2] + $ult.u[3]) end) as $ctx
  | (if $janela_env > 0 then $janela_env
     elif $ult != null and (($ctxmax[$ult.m] // 0) > 200000) then 1000000 else 200000 end) as $jan
  | ($us | map(select(.s > 0)) | if length == 0 then null else map(.x + $pcl * .y) | add end) as $tsessao
  | ([$hits[] | select(.r > $agora)] | last) as $limitada
  | ([$leituras[] | select(.em >= $bloco.ini and .em <= $agora)] | last) as $anc
  | (if $anc == null then null else $w - ($anc.x + $pcl * $anc.y) end) as $depois

  | (if $stl != null then {fonte: "statusline", c5: $stl.cinco_horas, d7: $stl.sete_dias, script: ($stl.script // "")}
     elif $limitada != null then {fonte: "jsonl", c5: {usado: 100, reinicia: $limitada.r, visto_em: $agora}}
     elif $lim == null then {fonte: "jsonl", c5: {usado: null, reinicia: (if $aberta then $bloco.fim else null end), visto_em: $agora,
       motivo: "sem calibração: a conta não bateu no limite de 5 horas nos transcripts dos últimos 30 dias e não há leitura do /usage. Rode orcamento-local.sh --calibrar <percentual que o /usage mostra>"}}
     elif $aberta and $anc != null then {fonte: "jsonl", c5: {usado: ($anc.pct + 100 * $depois / $lim.limite), reinicia: $bloco.fim, visto_em: $agora}}
     elif $aberta then {fonte: "jsonl", c5: {usado: (100 * $w / $lim.limite), reinicia: $bloco.fim, visto_em: $agora}}
     else {fonte: "jsonl", c5: {usado: 0, reinicia: null, visto_em: $agora}} end) as $f

  | {versao: 1, harness: "claude-code", fonte: $f.fonte, script: ($f.script // $script), gravado_em: $agora, sessao: $sid,
     cinco_horas: $f.c5, sete_dias: ($f.d7 // {usado: null, reinicia: null, visto_em: null}),
     contexto: {usado: (if $ctx == null then null else 100 * $ctx / $jan end), sessao: $sid, desta_sessao: ($ctx != null),
                tokens: $ctx, janela: $jan},
     estimativa: {tokens: ($w | floor), limite: ($lim.limite // null | if . == null then null else floor end),
                  calibracao: ($lim.rotulo // null), peso_cache_leitura: $pcl, sessao_tokens: ($tsessao // null | if . == null then null else floor end)}} as $obj

  | ([
      (if $f.fonte == "statusline" then "fonte statusline (5h oficial) e transcripts (contexto)"
       elif $limitada != null then "fonte transcripts: a conta bateu no limite de 5 horas às \($limitada.hit | strflocaltime("%H:%M"))"
       elif $lim == null then "fonte transcripts: ≈ \($w | fmt) tokens ponderados na janela, sem calibração"
       elif $aberta and $anc != null then "âncora: /usage das \($anc.em | strflocaltime("%H:%M")) com \($anc.pct)%, mais ≈ \($depois | fmt) tokens ponderados desde então sobre \($lim.limite | fmt) (\($lim.rotulo))"
       else "estimado pelos transcripts: ≈ \($w | fmt) de \($lim.limite | fmt) tokens ponderados (\($lim.rotulo))" end),
      (if $ctx == null then "contexto não medido: \(if $sid == "" then "sem id de sessão" else "sessão sem resposta nos transcripts" end)"
       else "contexto \($ctx | fmt) de \($jan | fmt)" end),
      (if $tsessao == null then empty else "sessão ≈ \($tsessao | fmt) com subagentes" end)
    ] | join(" · ")) as $nota

  | ($obj | tojson),
    ({versao: 1, varrido_ate: $agora, pontos: $pontos, leituras: $leituras, contexto_max: $ctxmax} | tojson),
    $nota
    end
' "$tmp" 2>/dev/null)
rc_jq=$?

json="" calnovo="" nota=""
{ IFS= read -r json; IFS= read -r calnovo; IFS= read -r nota; } <<<"$saida"
if [ "$json" = erro ]; then
  echo "$calnovo" >&2
  exit 2
fi
if [ "$rc_jq" -ne 0 ] || [ -z "$json" ] || [ -z "$calnovo" ]; then
  echo "ORCAMENTO desligado — não consegui ler os transcripts em $trans (jq saiu com $rc_jq)"
  exit 0
fi

# Gravação atômica dos dois arquivos. Falha ao gravar a calibração não impede a linha.
if tmpc=$(mktemp "$dir/.calibracao.XXXXXX") && printf '%s\n' "$calnovo" >"$tmpc" && mv -f "$tmpc" "$cal"; then
  tmpc=""
else
  avisos+=" · calibração não gravada"
fi
if ! { tmpj=$(mktemp "$dir/.orcamento-local.XXXXXX") && printf '%s\n' "$json" >"$tmpj" && mv -f "$tmpj" "$arq"; }; then
  echo "ORCAMENTO desligado — não consegui gravar $arq"
  exit 0
fi
tmpj=""
[ "$recalibrou" = 1 ] && avisos+=" · varredura de 30 dias feita agora"

args=()
[ -n "$tarefa" ] && args+=(--tarefa "$tarefa")
linha=$(bash "$lei" ${args[@]+"${args[@]}"} "$arq")
rc=$?
printf '%s · %s%s\n' "$linha" "$nota" "$avisos"
exit "$rc"
