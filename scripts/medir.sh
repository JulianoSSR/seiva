#!/usr/bin/env bash
# Mede quanto uma tarefa da seiva gastou, pelos transcripts locais do Claude Code (o terminal e o app desktop gravam do
# mesmo jeito, em ~/.claude/projects/), com a régua do orcamento-local.sh: cada resposta pesa entrada + saída + escrita
# de cache + PESO_CACHE_LEITURA × leitura de cache, contada uma vez (a chave é message.id + requestId).
#
# Uso: medir.sh --tarefa <pasta-da-tarefa> [--sessao <id>]... [--fechar]
#   --tarefa   a pasta criada pelo nova-tarefa.sh
#   --sessao   sessão do orquestrador medida inteira, além das marcadas em <pasta>/sessoes. Serve para tarefa de antes
#              da 1.3.0, que não tem marca. Pode repetir
#   --fechar   marca a sessão atual ($CLAUDE_CODE_SESSION_ID) em <pasta>/sessoes antes de medir: é o fim da parte do
#              orquestrador. Use no fechamento, na sessão do orquestrador
#
# De onde vem cada parte:
#   - subagentes: os das sessões da tarefa cujo pacote (a 1ª mensagem que o agente recebe) cita o nome da pasta da
#     tarefa. Atribuição exata. Os que não citam ficam fora da conta e saem contados como "de outra tarefa";
#   - orquestrador: em cada sessão, as respostas entre a 1ª e a última marca desta tarefa em <pasta>/sessoes. Marcam o
#     nova-tarefa.sh, o orcamento-local.sh --tarefa (a cada leva) e o medir.sh --fechar. Sessão sem marca, passada por
#     --sessao, conta inteira. Se outra tarefa marcou a mesma sessão nesse intervalo, ou se a sessão tem subagente que
#     não é desta tarefa, a parte do orquestrador é dividida pela proporção do gasto dos subagentes (em partes iguais,
#     quando só esta tarefa teve subagente no intervalo) e sai "estimado";
#   - quedas: respostas de erro da API no transcript do agente (limite de uso, sobrecarga); corridas: mensagens que o
#     agente recebeu do orquestrador (a 1ª é o pacote; as outras, retomadas).
#
# Saída: de 3 a 7 linhas, a 1ª começando por MEDICAO. Grava <pasta>/medicao.md, uma linha por agente com a descrição
# que o orquestrador deu, e acrescenta ao histórico ${XDG_CACHE_HOME:-$HOME/.cache}/seiva/custos.jsonl (modo 600) uma
# linha por agente encerrado: papel, família do modelo, nível da tarefa, ponderado, entrada e leitura de cache, quedas
# e corridas. O histórico não leva texto: nem descrição, nem nome de tarefa, nem caminho. É dele que o
# orcamento-local.sh --leva tira a previsão de custo de uma leva. Medir de novo a mesma tarefa substitui as linhas dos
# mesmos agentes, sem duplicar. Agente com transcript mexido nos últimos 2 minutos está rodando: aparece na saída e não
# entra no histórico.
# Do pacote do agente só sai se ele cita a pasta (sim ou não), nunca o texto.
# Códigos: 0 (mediu, ou não tinha o que medir, com o motivo na linha) e 2 (uso errado).
set -uo pipefail
export LC_ALL=C
umask 077

uso() { echo "uso: medir.sh --tarefa <pasta-da-tarefa> [--sessao <id>]... [--fechar]" >&2; exit 2; }

tarefa=""
fechar=0
explicitas=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --tarefa | --sessao)
      [ "$#" -ge 2 ] && [ -n "$2" ] || uso
      if [ "$1" = --tarefa ]; then tarefa=$2; else
        s=${2//[^A-Za-z0-9._-]/}
        [ -n "$s" ] && [ "$s" = "$2" ] || { echo "--sessao: id de sessão só tem letra, número, ponto, hífen e sublinhado" >&2; exit 2; }
        explicitas+=("$s")
      fi
      shift 2
      ;;
    --fechar)
      fechar=1
      shift
      ;;
    *) uso ;;
  esac
done
[ -n "$tarefa" ] || uso
[ -d "$tarefa" ] || { echo "--tarefa: $tarefa não é uma pasta" >&2; exit 2; }

pcl=${PESO_CACHE_LEITURA:-0.01}
awk -v p="$pcl" 'BEGIN { exit !(p ~ /^[0-9]*\.?[0-9]+$/ && p + 0 <= 1) }' ||
  { echo "PESO_CACHE_LEITURA precisa ser um número de 0 a 1 (veio '$pcl')" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "MEDICAO desligada — jq não está instalado"; exit 0; }

pasta=$(cd -- "$tarefa" 2>/dev/null && pwd -P) || { echo "--tarefa: não consegui entrar em $tarefa" >&2; exit 2; }
nome=${pasta##*/}
trans=${SEIVA_TRANSCRIPTS:-${HOME:-/nonexistent}/.claude/projects}
agora=$(date +%s)
avisos=()

# --fechar: a marca de agora fecha a janela do orquestrador desta sessão.
if [ "$fechar" = 1 ]; then
  atual=${CLAUDE_CODE_SESSION_ID:-}
  atual=${atual//[^A-Za-z0-9._-]/}
  if [ -z "$atual" ]; then
    avisos+=("--fechar sem CLAUDE_CODE_SESSION_ID: a parte do orquestrador vai até a última marca")
  elif ! printf '%s %s fechar\n' "$agora" "$atual" >>"$pasta/sessoes" 2>/dev/null; then
    avisos+=("--fechar: não consegui gravar $pasta/sessoes")
  fi
fi

# Marcas: "<epoch> <sessao> [fechar|deduzida]" por linha. As das outras tarefas da mesma pasta de trabalho dizem se a
# sessão foi dividida.
marcas_de() {
  [ -r "$1" ] && jq -Rnc --arg t "$2" '[inputs | capture("^(?<ts>[0-9]{9,11}) (?<s>[A-Za-z0-9._-]+)(?<r>.*)$")?
    | {ts: (.ts | tonumber), s, t: $t, fecha: (.r | test("fechar"))}]' "$1" 2>/dev/null || echo '[]'
}
marcas=$(marcas_de "$pasta/sessoes" "")
outras='[]'
i=0
for f in "$pasta"/../*/sessoes; do
  [ -r "$f" ] || continue
  [ "$(cd -- "${f%/sessoes}" 2>/dev/null && pwd -P)" = "$pasta" ] && continue
  i=$((i + 1))
  outras=$(jq -c --argjson a "$outras" --argjson b "$(marcas_de "$f" "$i")" -n '$a + $b')
done

sessoes=$(jq -rn --argjson m "$marcas" --args '[$m[].s] + $ARGS.positional | unique | .[]' ${explicitas[@]+"${explicitas[@]}"})

# Sem sessão nenhuma: lista as candidatas (transcripts do projeto que citam a pasta) e sai.
if [ -z "$sessoes" ]; then
  proj=""
  for loc in C.UTF-8 C.utf8 C; do
    p=$(printf '%s' "$PWD" | LC_ALL=$loc sed 's/[^A-Za-z0-9]/-/g' 2>/dev/null)
    [ -n "$p" ] && [ -d "$trans/$p" ] && { proj=$p; break; }
  done
  cand=""
  if [ -n "$proj" ]; then
    while IFS= read -r f; do
      a=$(head -c 300000 "$f" | grep -o '"timestamp":"[^"]*"' | head -n 1 | cut -d'"' -f4 | cut -c1-16)
      z=$(tail -c 300000 "$f" | grep -o '"timestamp":"[^"]*"' | tail -n 1 | cut -d'"' -f4 | cut -c1-16)
      s=${f##*/}
      cand+=" · ${s%.jsonl} ($a → $z)"
    done < <(grep -l -F -- "$nome" "$trans/$proj"/*.jsonl 2>/dev/null | head -n 8)
  fi
  echo "MEDICAO $nome sem-sessao — a pasta não tem marca de sessão (tarefa de antes da 1.3.0, ou nenhuma leva rodou o orcamento-local.sh --tarefa). Passe a sessão do orquestrador com --sessao <id>${cand:+. Sessões do projeto que citam a pasta (confira: sessão que só citou a tarefa também aparece)$cand}"
  exit 0
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/seiva-medir.XXXXXX") || { echo "MEDICAO desligada — não consegui criar pasta temporária"; exit 0; }
trap 'rm -rf -- "$tmp"' EXIT
: >"$tmp/linhas"
metas='{}'
rodando='[]'
sem=()
for s in $sessoes; do
  principal=$(find "$trans" -mindepth 2 -maxdepth 2 -type f -name "$s.jsonl" 2>/dev/null | head -n 1)
  [ -n "$principal" ] || { sem+=("$s"); continue; }
  sub=${principal%.jsonl}/subagents
  arqs=("$principal")
  if [ -d "$sub" ]; then
    for f in "$sub"/agent-*.jsonl; do [ -f "$f" ] && arqs+=("$f"); done
    for f in "$sub"/agent-*.meta.json; do
      [ -f "$f" ] || continue
      a=${f##*/agent-}
      a=${a%.meta.json}
      metas=$(jq -c --argjson m "$metas" --arg a "$a" '$m + {($a): {d: (.description // "" | tostring | .[0:120])}}' "$f" 2>/dev/null || printf '%s' "$metas")
    done
    for f in $(find "$sub" -name 'agent-*.jsonl' -mmin -2 2>/dev/null); do
      a=${f##*/agent-}
      rodando=$(jq -c --argjson r "$rodando" --arg a "${a%.jsonl}" -n '$r + [$a]')
    done
  fi
  # Uma linha pequena por resposta (u), erro da API (e), mensagem do orquestrador ao agente (p) e descrição de agente
  # na chamada do Agent, no transcript principal (t), de reserva para quando falta o meta.json.
  jq -cR --arg s "$s" --arg n "$nome" '
    fromjson? | select(type == "object")
    | (input_filename | split("/") | last | sub("\\.jsonl$"; "")) as $f
    | (if ($f | startswith("agent-")) then ($f | ltrimstr("agent-")) else "" end) as $a
    | (.timestamp | if type == "string" then (sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null) else null end) as $ts
    | if .type == "assistant" and $ts != null then
        if .apiErrorStatus != null or .isApiErrorMessage == true then {k: "e", s: $s, a: $a, ts: $ts}
        elif (.message.usage | type) == "object" then
          {k: "u", s: $s, a: $a, ts: $ts, sc: (.isSidechain == true),
           id: ((.message.id // "" | tostring) + ":" + (.requestId // "" | tostring)),
           m: (.message.model // "" | tostring | .[0:60]),
           u: (.message.usage | [.input_tokens, .output_tokens, .cache_creation_input_tokens, .cache_read_input_tokens]
               | map(if type == "number" then . else 0 end))}
        else empty end
      elif .type == "user" and $a != "" then
        .message.content as $c
        | (if ($c | type) == "string" then $c
           elif ($c | type) == "array" and all($c[]; (.type? // "") != "tool_result") then [$c[] | .text? // empty | strings] | join(" ")
           else null end) as $t
        # Lembrete do harness começa por tag e não é corrida; a mensagem do orquestrador a um agente rodando vem marcada
        # isMeta, sem tag, e é.
        | if $t == null or ($t | ltrimstr("\n") | startswith("<")) then empty
          else {k: "p", s: $s, a: $a, ln: input_line_number, cita: ($t | contains($n))} end
      elif .type == "user" and $a == "" and (.toolUseResult | type) == "object" and (.toolUseResult.agentId | type) == "string" then
        {k: "t", a: (.toolUseResult.agentId | gsub("[^A-Za-z0-9]"; "")), d: (.toolUseResult.description // "" | tostring | .[0:120])}
      else empty end
  ' "${arqs[@]}" >>"$tmp/linhas" 2>/dev/null
done

# Nível: só quando o registro diz um só.
nivel=""
if [ -r "$pasta/registro.md" ]; then
  nv=$(grep -oE 'N(í|i)vel[^:]*: *N[0-4]' "$pasta/registro.md" | grep -oE 'N[0-4]$' | sort -u)
  [ "$(printf '%s' "$nv" | grep -c .)" = 1 ] && nivel=$nv
fi
[ ${#sem[@]} -gt 0 ] && avisos+=("${#sem[@]} sessão(ões) sem transcript (o Claude Code apaga depois de 30 dias): ${sem[*]}")

jq -s -c --argjson marcas "$marcas" --argjson outras "$outras" --argjson metas "$metas" --argjson rodando "$rodando" \
  --argjson agora "$agora" --argjson pcl "$pcl" --arg nome "$nome" --arg nivel "$nivel" --args '
  def fmt: if . >= 1000000 then "\((. / 100000 | floor) / 10) mi" else "\(. / 1000 | floor) mil" end | gsub("\\."; ",");
  def milhar: floor | tostring | explode | reverse | [recurse(.[3:]; length > 0) | .[0:3] | reverse | implode] | reverse | join(".");
  def hora: if . == null then "?" else strftime("%Y-%m-%d %H:%M") end;
  def familia: if test("opus") then "opus" elif test("sonnet") then "sonnet" elif test("haiku") then "haiku"
               elif test("fable") then "fable" elif . == "" then "?" else . end;
  # O papel é a 1ª palavra conhecida da descrição que o orquestrador deu ao agente.
  def papel: ascii_downcase as $d
    | [["batedor", "batedor"], ["construtor", "construtor"], ["advers", "adversario"], ["lente", "lente"],
       ["implementador", "implementador"], ["verificador", "verificador"], ["invasor", "invasor"], ["revisor", "revisor"]]
    | map(.[0] as $k | .[1] as $p | ($d | index($k)) as $i | select($i != null) | {i: $i, p: $p})
    | if length == 0 then "outro" else (min_by(.i) | .p) end;
  def celula: tostring | gsub("[\r\n]+"; " ") | gsub("\\|"; "\\|");

  (map(select(.k == "u")) | unique_by(.id) | map(. + {x: (.u[0] + .u[1] + .u[2]), y: .u[3]} | . + {w: (.x + $pcl * .y)})) as $us
  | map(select(.k == "e")) as $es
  | map(select(.k == "p")) as $ps
  | (map(select(.k == "t") | {key: .a, value: .d}) | from_entries) as $descs
  | ([$us[], $es[] | select(.a != "") | .a] | unique) as $ids
  | [$ids[] as $a
      | [$us[] | select(.a == $a)] as $u | [$es[] | select(.a == $a)] as $e | ([$ps[] | select(.a == $a)] | sort_by(.ln)) as $p
      | ($metas[$a].d // $descs[$a] // "") as $d
      | ([$u[] | .m | select(. != "<synthetic>" and . != "")] | group_by(.) | max_by(length) // [] | .[0] // "") as $m
      | {a: $a, s: (($u + $e)[0].s), cita: ($p[0].cita // false), corridas: ($p | length), quedas: ($e | length),
         respostas: ($u | length), x: ($u | map(.x) | add // 0), y: ($u | map(.y) | add // 0), w: ($u | map(.w) | add // 0),
         ini: (($u + $e) | map(.ts) | min), fim: (($u + $e) | map(.ts) | max), modelo: $m, familia: ($m | familia),
         d: $d, papel: ($d | papel), rodando: (($rodando | index($a)) != null)}] as $ag
  | ($ag | map(select(.cita))) as $daq
  | ($ag | map(select(.cita | not))) as $fora

  # Orquestrador, sessão por sessão.
  | ($marcas | group_by(.s) | map({key: .[0].s, value: (sort_by(.ts) | {ts: map(.ts), fecha: last.fecha})}) | from_entries) as $ms
  | ((($ms | keys) + $ARGS.positional) | unique) as $sessoes
  | [$sessoes[] as $s
      | ($ms[$s].ts // []) as $m
      | (if ($m | length) > 0 then {ini: $m[0], fim: $m[-1], modo: "marcas", fecha: $ms[$s].fecha}
         else {ini: 0, fim: 1e15, modo: "inteira", fecha: true} end) as $j
      | [$us[] | select(.s == $s and .a == "" and (.sc | not) and .ts >= $j.ini and .ts <= $j.fim)] as $o
      | [$es[] | select(.s == $s and .a == "" and .ts >= $j.ini and .ts <= $j.fim)] as $oe
      | ([$outras[] | select(.s == $s and .ts >= $j.ini and .ts <= $j.fim) | .t] | unique) as $ot
      | [$ag[] | select(.s == $s and (.ini // -1) >= $j.ini and (.ini // -1) <= $j.fim)] as $base
      | (($base | map(select(.cita) | .w) | add) // 0) as $wt
      | (($base | map(.w) | add) // 0) as $wa
      | ((($ot | length) > 0) or ($base | any(.cita | not))) as $div
      | (($o | map(.w) | add) // 0) as $wo
      # Dividida: pela proporção dos subagentes; se só esta tarefa gastou com subagente na janela, em partes iguais.
      | (if ($div | not) then 1 elif ($wa - $wt) > 0 then $wt / $wa else 1 / (1 + ([($ot | length), 1] | max)) end) as $fr
      | {s: $s, modo: $j.modo, ini: $j.ini, fim: $j.fim, fecha: $j.fecha, respostas: ($o | length), quedas: ($oe | length),
         x: ($o | map(.x) | add // 0), y: ($o | map(.y) | add // 0), w: ($wo * $fr), bruto: $wo, estimado: $div,
         fr: $fr, sc: ([$us[] | select(.s == $s and .a == "" and .sc)] | length),
         inim: ($o | map(.ts) | min), fimm: ($o | map(.ts) | max)}] as $orq

  | (($daq | map(.w) | add) // 0) as $wsub
  | (($orq | map(.w) | add) // 0) as $worq
  | ($daq | map(select(.quedas > 0))) as $caiu
  | ($orq | map(select(.estimado))) as $est
  | ($orq | map(select(.fecha | not))) as $aberta

  | {saida: [
      "MEDICAO \($nome) · \($sessoes | length) sessão(ões) · \($daq | length) agente(s) da tarefa · régua: entrada + saída + escrita de cache + \($pcl) × leitura de cache",
      "subagentes ≈ \($wsub | fmt) · orquestrador ≈ \($worq | fmt) (\(if ($est | length) == 0 then "medido" else "estimado em \($est | length) de \($orq | length) sessão(ões) dividida(s) com outra tarefa; ver medicao.md" end)) · total ≈ \(($wsub + $worq) | fmt) · quedas: \($daq | map(.quedas) | add // 0) em \($caiu | length) agente(s)\(if ($caiu | length) > 0 then ", que gastaram \($caiu | map(.w) | add | fmt) (com o que entregaram antes de cair)" else "" end)",
      (if ($daq | length) == 0 then empty else
        "por papel: " + ($daq | group_by([.papel, .familia]) | map("\(.[0].papel) \(.[0].familia) ×\(length) = \(map(.w) | add | fmt)") | join(" · ")) end),
      (if ($daq | map(select(.rodando)) | length) > 0 then "\($daq | map(select(.rodando)) | length) agente(s) rodando: medidos até agora, fora do histórico" else empty end),
      (if ($fora | length) > 0 then "\($fora | length) subagente(s) das mesmas sessões cujo pacote não cita a pasta: \($fora | map(.w) | add | fmt), fora da conta" else empty end),
      (if ($orq | map(.sc) | add // 0) > 0 then "\($orq | map(.sc) | add) resposta(s) de subagente no transcript principal (formato antigo do Claude Code): fora da conta" else empty end),
      (if ($orq | any(.modo == "inteira")) then "sessão sem marca contada inteira: \($orq | map(select(.modo == "inteira") | .s[0:8]) | join(", "))" else empty end),
      (if ($aberta | length) > 0 then "orquestrador contado até a última marca (\($aberta | map(.fim | strftime("%H:%M UTC")) | join(", "))): no fechamento, rode com --fechar" else empty end)
    ],
    md: ([
      "# Medição — \($nome)",
      "",
      "Gerado por `medir.sh` em \($agora | todate). Régua: entrada + saída + escrita de cache + \($pcl) × leitura de cache, cada resposta uma vez. Tudo em tokens ponderados.",
      "",
      "| Agente | Papel | Modelo | Início → fim (UTC) | Corridas | Quedas | Respostas | Ponderado | Descrição |",
      "|---|---|---|---|---|---|---|---|---|",
      ($daq | sort_by(.ini)[] | "| \(.a[0:8]) | \(.papel) | \(.modelo | sub("^claude-"; "")) | \(.ini | hora) → \(.fim | hora) | \(.corridas) | \(.quedas) | \(.respostas) | \(.w | milhar)\(if .rodando then " (rodando)" else "" end) | \(.d | celula) |"),
      ($orq[] | "| orquestrador \(.s[0:8]) | — | — | \(.inim | hora) → \(.fimm | hora) | — | \(.quedas) | \(.respostas) | \(.w | milhar)\(if .estimado then " (estimado: \(.fr * 100 | floor)% de \(.bruto | milhar))" else "" end) | \(if .modo == "inteira" then "sessão inteira, sem marca" else "entre a 1ª e a última marca" end) |"),
      "",
      "Subagentes: \($wsub | milhar) · orquestrador: \($worq | milhar)\(if ($est | length) > 0 then " (estimado em parte)" else "" end) · total: \(($wsub + $worq) | milhar)"
    ] | join("\n")),
    hist: ([$daq[] | select(.rodando | not)
             | {v: 1, agente: .a, papel, modelo: .familia, nivel: (if $nivel == "" then null else $nivel end),
                ponderado: (.w | floor), x, y, respostas, quedas, corridas, ini, fim, medido_em: $agora}]
           + [$orq[] | select(.respostas > 0)
             | {v: 1, agente: ("orq-" + .s), papel: "orquestrador", modelo: null, nivel: (if $nivel == "" then null else $nivel end),
                ponderado: (.w | floor), x: (.x * .fr | floor), y: (.y * .fr | floor), respostas, quedas, corridas: null,
                ini: .inim, fim: .fimm, estimado, medido_em: $agora}])}
' ${sessoes} <"$tmp/linhas" >"$tmp/r.json" 2>"$tmp/err" ||
  { echo "MEDICAO desligada — não consegui ler os transcripts em $trans ($(head -c 200 "$tmp/err"))"; exit 0; }

jq -r '.saida[]' "$tmp/r.json" | head -n 1
jq -r '.saida[1:][]' "$tmp/r.json"
[ ${#avisos[@]} -eq 0 ] || printf '%s\n' "${avisos[@]}"

# medicao.md, por cima do anterior.
if jq -r '.md' "$tmp/r.json" >"$tmp/md" && mv -f "$tmp/md" "$pasta/medicao.md" 2>/dev/null; then
  det="detalhe: $pasta/medicao.md"
else
  det="medicao.md não gravado"
fi

# Histórico: as linhas destes agentes substituem as anteriores deles. Linha ilegível não some: o arquivo velho é
# guardado ao lado antes de ser refeito.
base=${XDG_CACHE_HOME:-}
[ -n "$base" ] || { [ -n "${HOME:-}" ] && base=$HOME/.cache; }
hist=""
if [ -n "$base" ] && mkdir -p -- "$base/seiva" 2>/dev/null; then
  custos=$base/seiva/custos.jsonl
  if command -v flock >/dev/null 2>&1 && { exec 8>"$base/seiva/.trava-custos"; } 2>/dev/null; then
    flock -w 60 8 2>/dev/null || hist="histórico não gravado: outra execução segura a trava há mais de 60 s"
  fi
  if [ -z "$hist" ]; then
    : >"$tmp/velho"
    if [ -e "$custos" ]; then
      ruins=$(jq -R 'fromjson? // "x" | if type == "object" and (.agente | type) == "string" then empty else 1 end' "$custos" 2>/dev/null | wc -l)
      jq -cR 'fromjson? | select(type == "object" and (.agente | type) == "string")' "$custos" >"$tmp/velho" 2>/dev/null
      if [ "$ruins" -gt 0 ]; then
        guarda=$custos.invalido-$agora-$$
        cp -p -- "$custos" "$guarda" 2>/dev/null && hist="$ruins linha(s) ilegível(is) no histórico, guardado inteiro em ${guarda##*/}; "
      fi
    fi
    n=$(jq '.hist | length' "$tmp/r.json")
    t2=""
    if { cat "$tmp/velho"; jq -c '.hist[]' "$tmp/r.json"; } |
      jq -sc 'to_entries | group_by(.value.agente) | map(max_by(.key) | .value) | sort_by(.fim // 0) | .[-2000:] | .[]' >"$tmp/novo" &&
      t2=$(mktemp "$base/seiva/.custos.XXXXXX") && cp "$tmp/novo" "$t2" && mv -f "$t2" "$custos"; then
      hist+="histórico: $n linha(s) gravada(s) em $custos"
    else
      [ -n "$t2" ] && rm -f -- "$t2"
      hist+="histórico não gravado"
    fi
  fi
else
  hist="histórico não gravado: sem HOME nem XDG_CACHE_HOME"
fi
echo "$det · $hist"
exit 0
