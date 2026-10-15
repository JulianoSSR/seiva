#!/usr/bin/env bash
# Testa scripts/orcamento-local.sh com transcripts falsos numa pasta temporária.
# HOME, XDG_CACHE_HOME e SEIVA_TRANSCRIPTS apontam para a pasta temporária: o ~/.cache/seiva e o ~/.claude de verdade
# não podem mudar (o último caso confere). Só valores falsos óbvios (ids de sessão de teste).
# Uso: bash testes/scripts/teste-orcamento-local.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
LOC="$RAIZ/scripts/orcamento-local.sh"

cache_real="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/seiva"
antes_real=$(stat -c %Y "$cache_real" 2>/dev/null || echo ausente)
cal_real=$(sha256sum "$cache_real/calibracao.json" 2>/dev/null | cut -c1-64)

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" TZ=UTC
# Rodando dentro do app desktop, estas chegam herdadas; os casos que precisam delas as definem à mão.
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID PESO_CACHE_LEITURA SEIVA_JANELA_CONTEXTO
AGORA=$(date +%s)
SID=sessao-teste-0001

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

# Cada caso começa do zero: transcripts e cache novos.
novo() {
  rm -rf "$T/c" "$T/tr" "$HOME"
  mkdir -p "$T/c" "$T/tr/-proj" "$HOME"
  export XDG_CACHE_HOME="$T/c" SEIVA_TRANSCRIPTS="$T/tr"
  JS="$T/c/seiva/orcamento-local.json"
  CAL="$T/c/seiva/calibracao.json"
}
iso() { jq -nr --argjson t "$1" '$t | todate'; }
# u <arquivo> <id> <segundos atrás> <in> <out> <escrita cache> <leitura cache> [modelo] [sidechain]
u() {
  mkdir -p "$(dirname "$1")"
  jq -nc --arg id "$2" --arg ts "$(iso $((AGORA - $3)))" --argjson i "$4" --argjson o "$5" --argjson cw "$6" --argjson cr "$7" \
    --arg m "${8:-claude-opus-teste}" --argjson sc "${9:-false}" \
    '{type: "assistant", timestamp: $ts, isSidechain: $sc, requestId: ("req_" + $id), sessionId: "x",
      message: {id: ("msg_" + $id), model: $m, content: [{type: "text", text: "conversa que não pode sair"}],
                usage: {input_tokens: $i, output_tokens: $o, cache_creation_input_tokens: $cw, cache_read_input_tokens: $cr}}}' >>"$1"
}
# h <arquivo> <segundos atrás> <epoch do reinício>: o aviso de limite da janela de 5 horas, em UTC
h() {
  local r=$3 H M h12 ap
  H=$(((r % 86400) / 3600))
  M=$(((r % 3600) / 60))
  h12=$((H % 12))
  [ "$h12" -eq 0 ] && h12=12
  ap=am
  [ "$H" -ge 12 ] && ap=pm
  jq -nc --arg ts "$(iso $((AGORA - $2)))" --arg t "$(printf "You've hit your session limit · resets %d:%02d%s (UTC)" "$h12" "$M" "$ap")" \
    '{type: "assistant", timestamp: $ts, isApiErrorMessage: true, apiErrorStatus: 429,
      message: {id: "erro", model: "<synthetic>", content: [{type: "text", text: $t}],
                usage: {input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}}}' >>"$1"
}
roda() {
  SAI=$(bash "$LOC" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}
campo() { jq -r "$1" "$JS" 2>/dev/null; }
M=$T/tr/-proj/$SID.jsonl
O=$T/tr/-proj/outra.jsonl

# --- uso errado -------------------------------------------------------------------
novo
roda --calibrar 5
eq "--calibrar 5: uso errado" 2 "$RC"
roda --calibrar abc
eq "--calibrar abc: uso errado" 2 "$RC"
roda --xyz
eq "opção desconhecida: uso errado" 2 "$RC"
PESO_CACHE_LEITURA=x roda
eq "PESO_CACHE_LEITURA inválido: uso errado" 2 "$RC"

# --- sem transcript nenhum: desligado, sem calibração; arquivos em modo 600 --------
novo
roda --sessao "$SID"
eq "sem transcripts: código 0" 0 "$RC"
tem "sem transcripts: desligado" "$SAI" "ORCAMENTO desligado"
tem "sem transcripts: motivo é a calibração" "$SAI" "sem calibração"
tem "sem transcripts: varredura de 30 dias na 1ª vez" "$SAI" "varredura de 30 dias feita agora"
eq "estado em modo 600" 600 "$(stat -c %a "$JS")"
eq "calibração em modo 600" 600 "$(stat -c %a "$CAL")"
eq "fonte jsonl" jsonl "$(campo .fonte)"
roda --sessao "$SID"
nao_tem "2ª vez: varredura incremental" "$SAI" "varredura de 30 dias"

# --- dedup, peso da leitura de cache e calibração manual ---------------------------
novo
u "$M" a 600 100 50 1000 10000
u "$M" a 600 100 50 1000 10000
u "$M" a 600 100 50 1000 10000
printf 'linha quebrada {\n' >>"$M"
roda --sessao "$SID" --calibrar 50
eq "dedup + peso 0,01: 100+50+1000+0,01×10000" 1250 "$(campo .estimativa.tokens)"
eq "calibração 50%: limite é o dobro" 2500 "$(campo .estimativa.limite)"
tem "calibração 50%: ok com 50%" "$SAI" "ORCAMENTO ok — 5h 50%"
tem "nota diz que é uma leitura do /usage" "$SAI" "menor de 1 ponto: 0 limites batidos e 1 leitura do /usage"
roda --sessao "$SID"
tem "a leitura vale na rodada seguinte" "$SAI" "5h 50%"
PESO_CACHE_LEITURA=0.1 roda --sessao "$SID"
eq "PESO_CACHE_LEITURA=0.1 muda o total" 2150 "$(campo .estimativa.tokens)"
roda --sessao "$SID" --calibrar 75
eq "75%: restrito, código 10" 10 "$RC"
tem "75%: restrito" "$SAI" "ORCAMENTO restrito"
roda --sessao "$SID" --calibrar 90
eq "90%: parar, código 20" 20 "$RC"
roda --sessao "$SID" --calibrar 30
tem "a leitura mais nova é a âncora, mesmo mais baixa" "$SAI" "5h 30%"
roda --sessao "$SID" --calibrar 45 --em $((AGORA - 30))
n1=$(jq '.leituras | length' "$CAL")
roda --sessao "$SID" --calibrar 46 --em $((AGORA - 30))
eq "leitura na mesma hora substitui a anterior" "$n1" "$(jq '.leituras | length' "$CAL")"
tem "leitura mais antiga não tira a âncora da mais nova" "$SAI" "5h 30%"
nao_tem "nenhum texto de conversa no estado" "$(cat "$JS" "$CAL")" "conversa que não pode sair"

# --- janelas encadeadas: o que é de uma janela velha não conta -----------------------
novo
u "$O" velha 25200 0 0 100000 0
u "$M" nova 3600 0 0 1000 0
roda --sessao "$SID"
eq "janela velha fora do total" 1000 "$(campo .estimativa.tokens)"
fim=$(campo .cinco_horas.reinicia)
ini=$((((AGORA - 3600) / 600) * 600))
eq "janela começa na 1ª resposta arredondada em 10 min" $((ini + 18000)) "$fim"

# --- aviso de limite com reinício no futuro: parar com 100% --------------------------
novo
R=$((((AGORA + 3600) / 600) * 600))
u "$M" a 7200 0 0 5000 0
h "$M" 60 "$R"
roda --sessao "$SID"
eq "limite batido agora: parar" 20 "$RC"
tem "limite batido agora: 100%" "$SAI" "5h 100%"
tem "limite batido agora: a nota diz" "$SAI" "bateu no limite"
eq "limite batido agora: reinício do aviso" "$R" "$(campo .cinco_horas.reinicia)"

# --- calibração automática por limite batido no passado -----------------------------
novo
R=$((((AGORA - 36000) / 600) * 600))
u "$O" p1 $((AGORA - (R - 18000) - 60)) 0 0 40000 0
u "$O" p2 $((AGORA - (R - 3600))) 0 0 60000 0
h "$O" $((AGORA - (R - 3000))) "$R"
u "$M" hoje 600 0 0 50000 0
roda --sessao "$SID"
eq "auto: limite = total da janela do aviso" 100000 "$(campo .estimativa.limite)"
tem "auto: 50% agora" "$SAI" "ORCAMENTO ok — 5h 50%"
tem "auto: a nota diz o ponto" "$SAI" "menor de 1 ponto: 1 limite batido e 0 leituras"
eq "auto: um ponto gravado" 1 "$(jq '.pontos | length' "$CAL")"
# A leitura vira âncora; o gasto depois dela vai sobre o menor limite entre os pontos (o do limite batido).
roda --sessao "$SID" --calibrar 25
tem "a leitura é a âncora" "$SAI" "5h 25%"
tem "a nota conta os dois tipos de ponto" "$SAI" "menor de 2 pontos: 1 limite batido e 1 leitura do /usage"
u "$M" depois 30 0 0 10000 0
roda --sessao "$SID"
tem "gasto depois da âncora vai sobre o menor limite: 25 + 10" "$SAI" "5h 35%"

# --- leitura com hora (--em): só conta o gasto até aquela hora ----------------------
novo
u "$M" a 900 0 0 1000 0
u "$M" b 60 0 0 3000 0
roda --sessao "$SID" --calibrar 50 --em "$(iso $((AGORA - 300)) | sed 's/Z$/.667Z/')"
eq "--em: o limite usa só o gasto até a hora da leitura" 2000 "$(campo .estimativa.limite)"
tem "--em: agora a janela tem o dobro" "$SAI" "5h 200%"
roda --sessao "$SID" --calibrar 50 --em $((AGORA - 7200))
eq "--em fora da janela aberta: uso errado" 2 "$RC"
tem "--em fora da janela: diz por quê" "$ERR" "não cai na janela"
roda --sessao "$SID" --em $((AGORA - 300))
eq "--em sem --calibrar: uso errado" 2 "$RC"
roda --sessao "$SID" --calibrar 50 --em ontem
eq "--em em formato que não é hora: uso errado" 2 "$RC"

# --- leitura do /usage na janela aberta é âncora --------------------------------------
novo
u "$M" a 600 0 0 1000 0
roda --sessao "$SID" --calibrar 50 --em $((AGORA - 500))
u "$M" c 400 0 0 1000 0
roda --sessao "$SID" --calibrar 60 --em $((AGORA - 300))
u "$M" d 60 0 0 400 0
roda --sessao "$SID"
tem "âncora: 60% lidos + 400 tokens sobre o menor limite (2.000)" "$SAI" "5h 80%"
tem "âncora: a nota diz a leitura" "$SAI" "âncora: /usage das"
eq "âncora: o limite continua o menor ponto" 2000 "$(campo .estimativa.limite)"

# --- janela de aviso aberta por uso que não aparece nos transcripts não calibra -------
novo
R=$((((AGORA - 36000) / 600) * 600))
u "$O" tarde $((AGORA - (R - 7200))) 0 0 40000 0
h "$O" $((AGORA - (R - 3000))) "$R"
u "$M" hoje 600 0 0 50000 0
roda --sessao "$SID"
eq "janela aberta por fora: nenhum ponto" 0 "$(jq '.pontos | length' "$CAL")"
tem "janela aberta por fora: sem calibração" "$SAI" "sem calibração"

# --- contexto desta sessão ------------------------------------------------------------
novo
u "$M" a 900 10 5 1000 150000
u "$M" b 300 1 1 1 1 claude-opus-teste true
mkdir -p "$T/tr/-proj/$SID/subagents"
u "$T/tr/-proj/$SID/subagents/agent-1.jsonl" s1 200 100 100 100 0 claude-haiku-teste true
roda --sessao "$SID" --calibrar 20
eq "contexto: última resposta fora de sidechain" 151010 "$(campo .contexto.tokens)"
eq "contexto: janela 200 mil sem histórico maior" 200000 "$(campo .contexto.janela)"
eq "contexto 75%: parar mesmo com 5h em 20%" 20 "$RC"
tem "contexto 75%: o motivo é o contexto" "$SAI" "contexto desta sessão em 75.5%"
tem "contexto 75%: sessão nova já" "$SAI" "a sessão nova pode começar agora"
eq "tokens da sessão contam o subagente" 2818 "$(campo .estimativa.sessao_tokens)"
SEIVA_JANELA_CONTEXTO=1000000 roda --sessao "$SID"
eq "SEIVA_JANELA_CONTEXTO=1 mi: ok" 0 "$RC"
u "$O" grande 7000 0 0 1000 300000 claude-opus-teste
roda --sessao "$SID"
eq "modelo que já passou de 200 mil: janela de 1 mi" 1000000 "$(campo .contexto.janela)"
eq "janela de 1 mi: ok" 0 "$RC"
tem "janela de 1 mi pelo histórico: a nota diz que é deduzida" "$SAI" "janela deduzida pelo histórico do modelo"
eq "janela de 1 mi pelo histórico: a fonte fica no estado" deduzida "$(campo .contexto.janela_fonte)"
roda --sessao outra-sessao
eq "sessão sem transcript: contexto não medido" null "$(campo .contexto.tokens)"
tem "sessão sem transcript: a nota diz" "$SAI" "contexto não medido"

# --- sessão pela variável do harness e sessão deduzida --------------------------------
novo
# A pasta do projeto no ~/.claude/projects é o caminho com tudo que não é letra ou número trocado por hífen.
mkdir -p "$T/w"
W=$T/tr/$(printf '%s' "$T/w" | sed 's/[^A-Za-z0-9]/-/g')/$SID.jsonl
u "$W" a 600 0 0 1000 50000
SAI=$(cd "$T/w" && bash "$LOC" 2>/dev/null)
tem "sem --sessao nem variável: sessão deduzida avisada" "$SAI" "sessão deduzida"
eq "sessão deduzida: contexto medido" 51000 "$(campo .contexto.tokens)"
u "$M" a 600 0 0 1000 50000
CLAUDE_CODE_SESSION_ID=$SID roda
nao_tem "com CLAUDE_CODE_SESSION_ID: sem aviso de dedução" "$SAI" "sessão deduzida"
eq "com CLAUDE_CODE_SESSION_ID: contexto medido" 51000 "$(campo .contexto.tokens)"

# --- app desktop e statusline --------------------------------------------------------
novo
u "$M" a 600 0 0 1000 0
roda --sessao "$SID" --calibrar 40
CLAUDE_CODE_ENTRYPOINT=claude-desktop roda --sessao "$SID"
nao_tem "app desktop com fonte jsonl: sem o aviso do app" "$SAI" "app desktop"
nao_tem "fonte jsonl: sem aviso de statusline" "$SAI" "statusline"
jq -nc --argjson g "$AGORA" --argjson r $((AGORA + 7200)) \
  '{versao: 1, harness: "claude-code", script: "/nao/existe", gravado_em: $g, sessao: "y",
    cinco_horas: {usado: 77, reinicia: $r, visto_em: $g}, sete_dias: {usado: 10, reinicia: ($r + 99999), visto_em: $g},
    contexto: {usado: 5, sessao: "y"}}' >"$T/c/seiva/orcamento.json"
roda --sessao "$SID"
eq "statusline recente no terminal: fonte statusline" statusline "$(campo .fonte)"
tem "statusline recente: usa o percentual oficial" "$SAI" "5h 77%"
eq "statusline recente: restrito" 10 "$RC"
CLAUDE_CODE_ENTRYPOINT=claude-desktop roda --sessao "$SID"
eq "no app desktop a statusline é ignorada" jsonl "$(campo .fonte)"
jq '.gravado_em -= 3600' "$T/c/seiva/orcamento.json" >"$T/x" && mv "$T/x" "$T/c/seiva/orcamento.json"
roda --sessao "$SID"
eq "statusline velha (1 h): fonte jsonl" jsonl "$(campo .fonte)"

# --- --tarefa repassado ao orcamento.sh ---------------------------------------------
novo
u "$M" a 600 0 0 1000 0
mkdir -p "$T/tarefa"
: >"$T/tarefa/registro.md"
roda --sessao "$SID" --tarefa "$T/tarefa"
tem "--tarefa: retomar gravado" "$SAI" "retomar gravado"
eq "--tarefa: o retomar aponta o registro" "$T/tarefa/registro.md" "$(cat "$T/c/seiva/retomar")"

# --- janela de contexto: a da própria sessão manda; o histórico vence em 30 dias -----
novo
u "$M" a 900 0 0 1000 250000
u "$M" b 60 0 0 1000 100000
roda --sessao "$SID"
eq "sessão que já passou de 200 mil: janela de 1 mi" 1000000 "$(campo .contexto.janela)"
eq "sessão acima de 200 mil: janela medida" medida "$(campo .contexto.janela_fonte)"
nao_tem "janela medida: sem aviso de dedução" "$SAI" "janela deduzida"
novo
u "$M" a 60 0 0 1000 100000
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 3600)) --argjson velho $((AGORA - 31 * 86400)) \
  '{versao: 1, varrido_ate: $v, pontos: [], leituras: [], contexto_1m: {"claude-opus-teste": $velho}}' >"$CAL"
roda --sessao "$SID"
eq "histórico de 1 mi com mais de 30 dias: volta a 200 mil" 200000 "$(campo .contexto.janela)"
eq "histórico vencido sai da calibração" null "$(jq -c '.contexto_1m["claude-opus-teste"]' "$CAL")"
# Calibração da 1.2.2 (contexto_max sem data): vira contexto_1m com a data da última varredura.
novo
u "$M" a 60 0 0 1000 100000
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 3600)) '{versao: 1, varrido_ate: $v, pontos: [], leituras: [], contexto_max: {"claude-opus-teste": 300000}}' >"$CAL"
roda --sessao "$SID"
eq "contexto_max da 1.2.2: janela de 1 mi deduzida" deduzida "$(campo .contexto.janela_fonte)"
eq "contexto_max da 1.2.2: migrado para contexto_1m" $((AGORA - 3600)) "$(jq '.contexto_1m["claude-opus-teste"]' "$CAL")"
eq "contexto_max da 1.2.2: o campo velho sai" false "$(jq 'has("contexto_max")' "$CAL")"

# --- leitura do /usage: recibo, lista e volta -------------------------------------------
novo
u "$M" a 900 0 0 1000 0
u "$O" outra 600 0 0 1000 0
roda --sessao "$SID" --calibrar 50 --em $((AGORA - 300))
tem "leitura: o recibo diz como desfazer" "$SAI" "para desfazer: orcamento-local.sh --descartar $(iso $((AGORA - 300)))"
nao_tem "1ª leitura: sem comparação, sem alerta" "$SAI" "ATENÇÃO"
# 10% sobre o mesmo gasto dá um limite 5 vezes maior: alerta.
roda --sessao "$SID" --calibrar 10 --em $((AGORA - 200))
tem "leitura que foge dos outros pontos: alerta" "$SAI" "ATENÇÃO: o limite que ela dá é 5×"
roda --leituras
eq "--leituras: código 0" 0 "$RC"
tem "--leituras: conta as duas" "$SAI" "LEITURAS 2"
tem "--leituras: hora em UTC que o --descartar aceita" "$SAI" "$(iso $((AGORA - 200))) · 10%"
roda --descartar "$(iso $((AGORA - 200)) | sed 's/Z$/.123Z/')"
eq "--descartar por hora ISO: código 0" 0 "$RC"
tem "--descartar: diz qual saiu" "$SAI" "DESCARTADA a leitura de $(iso $((AGORA - 200))) (10%)"
eq "--descartar: sobra uma leitura" 1 "$(jq '.leituras | length' "$CAL")"
roda --descartar ultima
eq "--descartar ultima: sobra nenhuma" 0 "$(jq '.leituras | length' "$CAL")"
roda --descartar ultima
eq "--descartar sem leitura: uso errado" 2 "$RC"
tem "--descartar sem leitura: aponta o --leituras" "$ERR" "--leituras"
roda --descartar ontem
eq "--descartar com hora que não é hora: uso errado" 2 "$RC"
roda --leituras --calibrar 50
eq "--leituras com --calibrar: uso errado" 2 "$RC"
roda --leituras --descartar ultima
eq "--leituras com --descartar: uso errado" 2 "$RC"
# --calibrar auto não apaga leitura: só o --descartar apaga.
roda --sessao "$SID" --calibrar 50 --em $((AGORA - 300))
roda --sessao "$SID" --calibrar auto
eq "--calibrar auto mantém as leituras" 1 "$(jq '.leituras | length' "$CAL")"

# --- calibração ilegível ou de outra forma: guardada à parte, nunca em silêncio --------
novo
u "$M" a 60 0 0 1000 0
mkdir -p "$T/c/seiva"
printf '{versao: quebrado' >"$CAL"
roda --sessao "$SID"
tem "calibração ilegível: aviso na linha" "$SAI" "guardada em calibracao.json.invalido-"
eq "calibração ilegível: cópia guardada" 1 "$(ls "$T/c/seiva" | grep -c '^calibracao\.json\.invalido-')"
eq "calibração ilegível: refeita" 1 "$(jq '.versao' "$CAL")"
novo
u "$M" a 60 0 0 1000 0
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 3600)) '{versao: 1, varrido_ate: $v, pontos: [], leituras: "73"}' >"$CAL"
roda --sessao "$SID"
tem "campo de tipo errado: guardada, não desligado" "$SAI" "guardada em calibracao.json.invalido-"
nao_tem "campo de tipo errado: a causa não é leitura de transcript" "$SAI" "não consegui ler os transcripts"
# A 1.2.0 gravava uma leitura só, em "manual": ela vira a 1ª leitura.
novo
u "$M" a 600 0 0 1000 0
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 3600)) --argjson e $((AGORA - 300)) \
  '{versao: 1, varrido_ate: $v, pontos: [], manual: {em: $e, pct: 50, x: 1000, y: 0}}' >"$CAL"
roda --sessao "$SID"
eq "manual da 1.2.0 vira leitura" 1 "$(jq '.leituras | length' "$CAL")"
eq "manual da 1.2.0: o campo velho sai" false "$(jq 'has("manual")' "$CAL")"
nao_tem "manual da 1.2.0: não é tratado como inválido" "$SAI" "invalido"

# --- duas execuções ao mesmo tempo não perdem leitura ------------------------------------
novo
u "$M" a 900 0 0 1000 0
roda --sessao "$SID"
bash "$LOC" --sessao "$SID" --calibrar 40 --em $((AGORA - 600)) >/dev/null 2>&1 &
p1=$!
bash "$LOC" --sessao "$SID" --calibrar 60 --em $((AGORA - 500)) >/dev/null 2>&1 &
p2=$!
wait "$p1" "$p2"
eq "duas leituras gravadas ao mesmo tempo: as duas ficam" 2 "$(jq '.leituras | length' "$CAL")"
if command -v flock >/dev/null 2>&1; then
  ( flock 9; sleep 2 ) 9>"$T/c/seiva/.trava" &
  p3=$!
  sleep 0.3
  t0=$(date +%s)
  roda --sessao "$SID"
  wait "$p3"
  eq "com a trava presa, espera em vez de seguir" 1 "$(( $(date +%s) - t0 >= 1 ))"
  eq "com a trava presa por 2 s: termina ok" 0 "$RC"
fi

# --- formato do transcript mudou: desligado, não 0% ------------------------------------
novo
jq -nc --arg ts "$(iso $((AGORA - 60)))" \
  '{type: "assistant", timestamp: $ts, message: {id: "m1", model: "claude-opus-teste", uso: {entrada: 1000}}}' >>"$M"
roda --sessao "$SID"
tem "transcript desta sessão sem registro de uso reconhecível: desligado" "$SAI" "ORCAMENTO desligado"
tem "formato mudou: diz o motivo" "$SAI" "formato do Claude Code pode ter mudado"
eq "formato mudou: código 0" 0 "$RC"
novo
jq -nc --arg ts "$(iso $((AGORA - 60)))" '{type: "user", timestamp: $ts, message: {role: "user", content: "oi"}}' >>"$M"
roda --sessao "$SID"
nao_tem "sessão que só tem a mensagem do usuário: não acusa formato" "$SAI" "formato"

# --- caminho com acento: a pasta do projeto é achada -----------------------------------
for loc in C.UTF-8 C; do
  novo
  mkdir -p "$T/wá"
  W=$T/tr/$(printf '%s' "$T/wá" | LC_ALL=$loc sed 's/[^A-Za-z0-9]/-/g')/$SID.jsonl
  u "$W" a 600 0 0 1000 50000
  SAI=$(cd "$T/wá" && bash "$LOC" 2>/dev/null)
  tem "caminho com acento, pasta nomeada em $loc: sessão deduzida" "$SAI" "sessão deduzida"
  eq "caminho com acento, pasta nomeada em $loc: contexto medido" 51000 "$(campo .contexto.tokens)"
done

# --- calibração inválida: o aviso sai também nas saídas curtas ------------------------
for modo in leituras descartar calibrar; do
  novo
  u "$M" a 60 0 0 1000 0
  mkdir -p "$T/c/seiva"
  printf '{versao: quebrado' >"$CAL"
  case $modo in
    leituras) roda --leituras ;;
    descartar) roda --descartar ultima ;;
    calibrar) roda --sessao "$SID" --calibrar 50 --em $((AGORA - 7200)) ;;
  esac
  tem "calibração inválida com --$modo: o aviso sai" "$SAI$ERR" "guardada em calibracao.json.invalido-"
done

# --- resposta de erro da API que não é de limite não acusa formato ----------------------
novo
jq -nc --arg ts "$(iso $((AGORA - 60)))" \
  '{type: "assistant", timestamp: $ts, isApiErrorMessage: true, apiErrorStatus: 529,
    message: {id: "erro", model: "<synthetic>", content: [{type: "text", text: "API Error: 529 Overloaded"}]}}' >>"$M"
roda --sessao "$SID"
nao_tem "sessão nova só com erro 529: não acusa formato" "$SAI" "formato do Claude Code"

# --- trava que não se abre: segue com aviso, sem a mensagem de espera ---------------------
if command -v flock >/dev/null 2>&1; then
  novo
  u "$M" a 60 0 0 1000 0
  mkdir -p "$T/c/seiva"
  : >"$T/c/seiva/.trava"
  chmod 000 "$T/c/seiva/.trava"
  roda --sessao "$SID"
  chmod 600 "$T/c/seiva/.trava"
  nao_tem "trava sem permissão: não diz que outra execução a segura" "$SAI" "há mais de 60 s"
  tem "trava sem permissão: avisa que seguiu sem trava" "$SAI" "sem trava nesta execução"
fi

# --- --tarefa marca a sessão na pasta da tarefa ------------------------------------------
novo
u "$M" a 60 100000 0 0 0
mkdir -p "$T/tarefa-marca"
roda --sessao "$SID" --tarefa "$T/tarefa-marca"
tem "--tarefa: marca a sessão" "$(cat "$T/tarefa-marca/sessoes" 2>/dev/null)" " $SID"
roda --sessao "$SID" --tarefa "$T/tarefa-marca"
eq "--tarefa: uma marca por execução" 2 "$(wc -l <"$T/tarefa-marca/sessoes")"
roda --sessao "$SID" --tarefa "$T/nao-existe"
eq "--tarefa que não existe: não cria a pasta" no "$([ -e "$T/nao-existe" ] && echo sim || echo no)"

# --- --leva: previsão pelo histórico do medir.sh, contra o que resta da janela ---------
novo
u "$M" a 60 100000 0 0 0
mkdir -p "$T/c/seiva"
{
  for p in 100000 200000 300000; do printf '{"v":1,"agente":"c%s","papel":"construtor","modelo":"opus","ponderado":%s,"quedas":0,"corridas":1}\n' "$p" "$p"; done
  printf '{"v":1,"agente":"cq","papel":"construtor","modelo":"opus","ponderado":900000,"quedas":1,"corridas":1}\n'
  printf '{"v":1,"agente":"cr","papel":"construtor","modelo":"opus","ponderado":900000,"quedas":0,"corridas":2}\n'
  for p in 1 2 3; do printf '{"v":1,"agente":"b%s","papel":"batedor","modelo":"haiku","ponderado":10000,"quedas":0,"corridas":1}\n' "$p"; done
  printf 'linha ilegível\n'
} >"$T/c/seiva/custos.jsonl"
roda --sessao "$SID" --leva "construtor:opus"
tem "--leva sem calibração: não sabe quanto resta" "$SAI" "resta ≈ ? (sem calibração)"
roda --sessao "$SID" --calibrar 50
roda --sessao "$SID" --leva "construtor:opus"
tem "--leva: mediana só das corridas limpas (sem queda, sem retomada)" "$SAI" "leva ≈ 200 mil (construtor:opus 200 mil, mediana das corridas limpas)"
tem "--leva: maior que o que resta (50% de 200 mil)" "$SAI" "resta ≈ 100 mil: NÃO CABE"
eq "--leva: o código continua o do orcamento.sh" 0 "$RC"
roda --sessao "$SID" --leva "batedor:haiku batedor:haiku"
tem "--leva: agentes iguais somam" "$SAI" "leva ≈ 20 mil (batedor:haiku 10 mil"
tem "--leva: cabe" "$SAI" "resta ≈ 100 mil: cabe"
roda --sessao "$SID" --leva "batedor:haiku lente:sonnet"
tem "--leva: item sem histórico fica fora da soma, com o nome" "$SAI" "sem contar lente:sonnet: menos de 3 corridas limpas no histórico"
tem "--leva: só a parte conhecida cabe" "$SAI" ": a parte conhecida cabe"
roda --sessao "$SID" --leva "advers:opus"
eq "--leva com papel desconhecido: uso errado" 2 "$RC"
roda --sessao "$SID" --leva "lente"
eq "--leva sem modelo: uso errado" 2 "$RC"
roda --sessao "$SID" --leva "lente:Opus"
eq "--leva com modelo fora do padrão: uso errado" 2 "$RC"
roda --sessao "$SID" --leva "   "
eq "--leva vazio: uso errado" 2 "$RC"
rm -f "$T/c/seiva/custos.jsonl"
roda --sessao "$SID" --leva "construtor:opus"
tem "--leva sem histórico nenhum: diz qual ficou fora" "$SAI" "leva ≈ 0 mil, sem contar construtor:opus"

# --- sem jq: desligado --------------------------------------------------------------
novo
mkdir -p "$T/bin"
for b in bash date mkdir sed ls head mktemp find awk env rm mv cat tail; do
  p=$(command -v "$b") && ln -sf "$p" "$T/bin/$b"
done
SAI=$(PATH="$T/bin" bash "$LOC" --sessao "$SID" 2>&1)
RC=$?
eq "sem jq: código 0" 0 "$RC"
tem "sem jq: desligado com o motivo" "$SAI" "jq não está instalado"

# --- o cache e a calibração de verdade não mudaram ----------------------------------
eq "~/.cache/seiva de verdade não mudou" "$antes_real" "$(stat -c %Y "$cache_real" 2>/dev/null || echo ausente)"
eq "calibracao.json de verdade não mudou (hash)" "$cal_real" "$(sha256sum "$cache_real/calibracao.json" 2>/dev/null | cut -c1-64)"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
