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
tem "D-7 · nota diz que é uma leitura do /usage" "$SAI" "leitura da janela: 1 leitura do /usage"
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
# D-7: a leitura digitada dentro da janela aberta manda sobre o limite batido de outra janela: o limite passa a ser o
# dela (200 mil, não os 100 mil do limite batido).
roda --sessao "$SID" --calibrar 25
tem "a leitura é a âncora" "$SAI" "5h 25%"
tem "D-7 · a nota diz a leitura que deu o limite" "$SAI" "leitura da janela: 1 leitura do /usage"
u "$M" depois 30 0 0 10000 0
roda --sessao "$SID"
tem "D-7 · gasto depois da âncora vai sobre o limite da leitura da janela: 25 + 5" "$SAI" "5h 30%"

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

# --- hora local e com deslocamento em --em e --descartar (OL1 a OL22) --------------------------
# Os fusos são TZ POSIX, sem depender de tzdata: BRT3 (UTC-3), UTC e IST-5:30. Onde o caso depende da hora do relógio local
# (virada do dia, hora adiante de agora), o teste calcula a TZ que põe o relógio local perto da hora alvo, qualquer que
# seja a hora real da execução. A hora vem de date +%s, nunca de date -d.
agora_novo() { AGORA=$(date +%s); }
# tz_perto <minuto do dia>: TZ de 3 letras e deslocamento em horas e minutos, com o sinal invertido (positivo é a oeste
# de UTC), que põe o relógio local perto desse minuto do dia agora (o segundo corrente é o mesmo de UTC)
tz_perto() {
  local u x
  u=$((($(date +%s) / 60) % 1440))
  x=$((($1 - u) % 1440))
  [ "$x" -lt 0 ] && x=$((x + 1440))
  [ "$x" -gt 720 ] && x=$((x - 1440))
  if [ "$x" -ge 0 ]; then printf 'LOC-%d:%02d' $((x / 60)) $((x % 60)); else printf 'LOC+%d:%02d' $((-x / 60)) $((-x % 60)); fi
}
# hora_em <epoch> <TZ> <formato>: o relógio de parede desse instante nesse fuso
hora_em() { TZ=$2 jq -nr --argjson e "$1" --arg f "$3" '$e | strflocaltime($f)' 2>/dev/null; }
# perto <descrição> <esperado> <obtido> <tolerância em segundos>
perto() {
  local d
  n=$((n + 1))
  case $3 in
    '' | *[!0-9]*) d=999999999 ;;
    *) d=$(($3 - $2)); d=${d#-} ;;
  esac
  if [ "$d" -gt "$4" ]; then
    erros=$((erros + 1))
    echo "FALHA: $1"
    printf '  | esperado: %s (±%s s)\n  | obtido:   %s\n' "$2" "$4" "$3"
  fi
}
# grava_em <texto de --em> [pct]: zera tudo, põe uma resposta há 50 minutos, grava a leitura com essa hora e deixa o
# epoch gravado em EM_GRAVADO (vazio se não gravou); SAI, ERR e RC são os da rodada
grava_em() {
  novo
  u "$M" a 3000 0 0 1000 0
  roda --sessao "$SID" --calibrar "${2:-50}" --em "$1"
  EM_GRAVADO=$(jq -r '.leituras[0].em // empty' "$CAL" 2>/dev/null)
}

# OL1: HH:MM já passado hoje, com o relógio local perto de 12:00
agora_novo
TZ1=$(tz_perto 720)
TZ=$TZ1 grava_em 11:55
eq "OL1 · HH:MM já passado hoje: código 0" 0 "$RC"
eq "OL1 · HH:MM já passado hoje: o relógio local da leitura é 11:55:00" 11:55:00 "$(hora_em "$EM_GRAVADO" "$TZ1" %H:%M:%S)"
perto "OL1 · HH:MM já passado hoje: 5 minutos atrás" $((AGORA - 300)) "$EM_GRAVADO" 120
tem "OL1 · HH:MM já passado hoje: o recibo diz a hora digitada" "$SAI" "leitura gravada: 50% às 11:55"

# OL2: ISO com deslocamento dá o mesmo epoch que o Z equivalente
agora_novo
E=$((AGORA - 300))
grava_em "$(iso $((E - 10800)) | sed 's/Z$/-03:00/')"
eq "OL2 · ISO com -03:00: epoch igual ao do Z" "$E" "$EM_GRAVADO"
grava_em "$(iso "$E")"
eq "OL2 · o Z equivalente" "$E" "$EM_GRAVADO"

# OL3: -0300, +05:30 e segundos opcionais
agora_novo
E0=$(((AGORA - 300) / 60 * 60))
grava_em "$(iso $((E0 - 10800)) | sed 's/Z$/-0300/')"
eq "OL3 · -0300 sem dois-pontos" "$E0" "$EM_GRAVADO"
grava_em "$(iso $((E0 + 19800)) | sed 's/Z$/+05:30/')"
eq "OL3 · +05:30" "$E0" "$EM_GRAVADO"
grava_em "$(iso "$E0" | sed 's/:00Z$/Z/')"
eq "OL3 · Z sem segundos" "$E0" "$EM_GRAVADO"
grava_em "$(iso $((E0 + 19800)) | sed 's/Z$/.250+0530/')"
eq "OL3 · fração de segundo e +0530" "$E0" "$EM_GRAVADO"

# OL4: as formas de antes continuam valendo
agora_novo
E=$((AGORA - 300))
grava_em "$E"
eq "OL4 · epoch" "$E" "$EM_GRAVADO"
grava_em "$(iso "$E")"
eq "OL4 · ISO com Z" "$E" "$EM_GRAVADO"
grava_em "$(iso "$E" | sed 's/Z$/.667Z/')"
eq "OL4 · ISO com fração e Z" "$E" "$EM_GRAVADO"

# OL5: ISO sem fuso é recusado, com a lista das formas aceitas
agora_novo
grava_em "$(iso $((AGORA - 300)) | sed 's/Z$//')"
eq "OL5 · ISO sem fuso: uso errado" 2 "$RC"
tem "OL5 · ISO sem fuso: a mensagem lista o epoch" "$ERR" "epoch"
tem "OL5 · ISO sem fuso: a mensagem lista o Z" "$ERR" "Z"
tem "OL5 · ISO sem fuso: a mensagem lista o deslocamento" "$ERR" "deslocamento"
tem "OL5 · ISO sem fuso: a mensagem lista o HH:MM" "$ERR" "HH:MM"
eq "OL5 · ISO sem fuso: nada gravado" nao "$([ -e "$CAL" ] && echo sim || echo nao)"

# OL6: formas inválidas
for f in 25:61 8h21 ontem 24:00 13:00pm 0:30am 8:21xm; do
  grava_em "$f"
  eq "OL6 · '$f': uso errado" 2 "$RC"
  tem "OL6 · '$f': a mensagem lista o HH:MM" "$ERR" "HH:MM"
  eq "OL6 · '$f': nada gravado" "" "$EM_GRAVADO"
done

# OL7: virada do dia: com o relógio local perto de 00:20, 23:50 é de ontem
agora_novo
TZ7=$(tz_perto 20)
TZ=$TZ7 grava_em 23:50
eq "OL7 · virada do dia: código 0" 0 "$RC"
eq "OL7 · virada do dia: o relógio local da leitura é 23:50:00" 23:50:00 "$(hora_em "$EM_GRAVADO" "$TZ7" %H:%M:%S)"
perto "OL7 · virada do dia: 30 minutos atrás" $((AGORA - 1800)) "$EM_GRAVADO" 120

# OL8: HH:MM adiante de agora vira ontem, fora da janela de 5 horas
agora_novo
TZ8=$(tz_perto 720)
TZ=$TZ8 grava_em 12:30
eq "OL8 · HH:MM adiante de agora: uso errado" 2 "$RC"
tem "OL8 · HH:MM adiante de agora: não cai na janela" "$ERR" "não cai na janela"
tem "OL8 · HH:MM adiante de agora: diz a hora lida" "$ERR" ", hora lida: 20"
LIDO=$(printf '%s' "$ERR" | sed -n 's/.*hora lida: \([0-9T:Z-]*\).*/\1/p')
EL=$(jq -nr --arg t "$LIDO" '$t | fromdateiso8601' 2>/dev/null)
eq "OL8 · HH:MM adiante de agora: a hora lida é 12:30:00 local" 12:30:00 "$(hora_em "$EL" "$TZ8" %H:%M:%S)"
perto "OL8 · HH:MM adiante de agora: a hora lida é a de ontem" $((AGORA - 84600)) "$EL" 180
grava_em $((AGORA - 7200))
nao_tem "OL8 · epoch fora da janela: sem hora lida" "$ERR" "hora lida"
tem "OL8 · epoch fora da janela: a mensagem de sempre" "$ERR" "não cai na janela"

# OL9: hora de um dígito é igual à de dois
agora_novo
TZ9=$(tz_perto 506)
TZ=$TZ9 grava_em 8:21
EM_A=$EM_GRAVADO
TZ=$TZ9 grava_em 08:21
eq "OL9 · hora de um dígito: o relógio local da leitura é 08:21:00" 08:21:00 "$(hora_em "$EM_A" "$TZ9" %H:%M:%S)"
eq "OL9 · hora de um dígito: igual a 08:21" "$EM_GRAVADO" "$EM_A"

# OL10: fuso UTC e fuso de meia hora
agora_novo
for tz in UTC IST-5:30; do
  TZ=$tz grava_em "$(hora_em $((AGORA - 300)) "$tz" %H:%M)"
  eq "OL10 · $tz: a leitura cai no minuto de 5 minutos atrás" $(((AGORA - 300) / 60 * 60)) "$EM_GRAVADO"
done

# OL11: --descartar HH:MM
agora_novo
E0=$(((AGORA - 300) / 60 * 60))
LAB=$(hora_em "$E0" BRT3 %H:%M)
TZ=BRT3 grava_em "$LAB"
eq "OL11 · leitura gravada com HH:MM" "$E0" "$EM_GRAVADO"
TZ=BRT3 roda --descartar "$LAB"
eq "OL11 · --descartar HH:MM: código 0" 0 "$RC"
tem "OL11 · --descartar HH:MM: diz qual saiu" "$SAI" "DESCARTADA a leitura de $(iso "$E0") (50%)"
eq "OL11 · --descartar HH:MM: sobra nenhuma" 0 "$(jq '.leituras | length' "$CAL")"

# OL12: --descartar HH:MM sem leitura nessa hora não é erro de formato
TZ=BRT3 roda --descartar "$LAB"
eq "OL12 · sem leitura nessa hora: uso errado" 2 "$RC"
tem "OL12 · sem leitura nessa hora: diz isso" "$ERR" "nenhuma leitura nessa hora"
TZ=BRT3 grava_em "$LAB"
TZ=BRT3 roda --descartar "$(hora_em $((E0 + 600)) BRT3 %H:%M)"
eq "OL12 · leitura em outro minuto: uso errado" 2 "$RC"
tem "OL12 · leitura em outro minuto: nenhuma leitura nessa hora" "$ERR" "nenhuma leitura nessa hora"
eq "OL12 · leitura em outro minuto: nada apagado" 1 "$(jq '.leituras | length' "$CAL")"

# OL13: --descartar com forma inválida
roda --descartar ontem
eq "OL13 · --descartar ontem: uso errado" 2 "$RC"
tem "OL13 · --descartar ontem: a mensagem lista o HH:MM" "$ERR" "HH:MM"
tem "OL13 · --descartar ontem: a mensagem lista o epoch" "$ERR" "epoch"
roda --descartar 25:61
eq "OL13 · --descartar 25:61: uso errado" 2 "$RC"
roda --descartar "$(iso "$E0" | sed 's/Z$//')"
eq "OL13 · --descartar ISO sem fuso: uso errado" 2 "$RC"
eq "OL13 · forma inválida: nada apagado" 1 "$(jq '.leituras | length' "$CAL")"

# OL14: --leituras: o começo da linha é o de sempre e o fim traz a hora local
agora_novo
E1=$((AGORA - 300))
E2=$((AGORA - 200))
novo
u "$M" a 900 0 0 1000 0
roda --sessao "$SID" --calibrar 50 --em "$E1"
roda --sessao "$SID" --calibrar 10 --em "$E2"
TZ=BRT3 roda --leituras
eq "OL14 · --leituras: código 0" 0 "$RC"
tem "OL14 · --leituras: o começo da linha não mudou" "$SAI" "$(iso "$E2") · 10% · limite que ela dá ≈"
tem "OL14 · --leituras: a hora local da 1ª leitura no fim" "$SAI" "tokens ponderados · local $(hora_em "$E1" BRT3 '%d/%m %H:%M')"
tem "OL14 · --leituras: a hora local da 2ª leitura no fim" "$SAI" "tokens ponderados · local $(hora_em "$E2" BRT3 '%d/%m %H:%M')"

# OL15: --em só vale com --calibrar <pct>
agora_novo
novo
u "$M" a 3000 0 0 1000 0
roda --sessao "$SID" --calibrar auto --em $((AGORA - 300))
eq "OL15 · --em com --calibrar auto: uso errado" 2 "$RC"
tem "OL15 · --em com --calibrar auto: diz por quê" "$ERR" "--em só vale com --calibrar"
roda --sessao "$SID" --em 11:55
eq "OL15 · --em sem --calibrar: uso errado" 2 "$RC"

# OL16: o começo do recibo e o jeito de desfazer não mudam
agora_novo
E=$((AGORA - 300))
TZ=BRT3 grava_em "$E"
tem "OL16 · recibo: começo igual" "$SAI" "leitura gravada: 50% às $(hora_em "$E" BRT3 %H:%M)"
tem "OL16 · recibo: o jeito de desfazer" "$SAI" "para desfazer: orcamento-local.sh --descartar $(iso "$E")"

# OL17: horário de verão: a transição fica entre agora - 30 min e agora - 10 min. Uma passada só errava 3600 s no 1º.
# TZ POSIX AAA<padrão>BBB,<dia do ano>/<hora>,365/24, com a transição 20 min atrás e o relógio local perto de 12:00 depois dela.
agora_novo
U=$(((AGORA / 60) % 1440))
X=$((((660 - U) % 1440 + 1440) % 1440))
[ "$X" -gt 720 ] && X=$((X - 1440))
TL=$((AGORA - 1200 + X * 60))
DIA=$(jq -nr --argjson t "$TL" '$t | gmtime | .[7]')
HM=$(jq -nr --argjson t "$TL" '$t | gmtime | "\(.[3]):\(.[4] | tostring | if length < 2 then "0" + . else . end)"')
if [ "$X" -ge 0 ]; then PADRAO=$(printf -- '-%d:%02d' $((X / 60)) $((X % 60))); else PADRAO=$(printf -- '+%d:%02d' $((-X / 60)) $((-X % 60))); fi
TZV="AAA${PADRAO}BBB,${DIA}/${HM},365/24"
if [ "$DIA" -ge 363 ]; then
  echo "AVISO: OL17 pulado hoje, sem contar nos casos (a transição cai no fim do ano, dia $DIA, e a regra 365/24 não a comporta); roda nos outros dias"
else
  O1=$(TZ=$TZV jq -nr --argjson e $((AGORA - 1800)) '($e | localtime | mktime) - $e')
  O2=$(TZ=$TZV jq -nr --argjson e $((AGORA - 600)) '($e | localtime | mktime) - $e')
  eq "OL17 · a regra de verão vale: o deslocamento do fuso muda 3600 s entre os dois instantes" 3600 "$((O2 - O1))"
  TZ=$TZV grava_em "$(hora_em $((AGORA - 1800)) "$TZV" %H:%M:%S)"
  perto "OL17 · horário de verão: a hora de antes da transição" $((AGORA - 1800)) "$EM_GRAVADO" 60
  TZ=$TZV grava_em "$(hora_em $((AGORA - 600)) "$TZV" %H:%M:%S)"
  perto "OL17 · horário de verão: a hora de depois da transição" $((AGORA - 600)) "$EM_GRAVADO" 60
fi

# OL18: 12 horas com am e pm
for par in '8:21am|08:21|00' '8:21 AM|08:21|00' '12:05am|00:05|00' '12:05pm|12:05|00' '1:30pm|13:30|00' '8:21:07 Pm|20:21|07'; do
  AP=${par%%|*}
  RESTO=${par#*|}
  H24=${RESTO%%|*}
  SEG=${RESTO##*|}
  EQUIV=$H24
  [ "$SEG" = 00 ] || EQUIV=$H24:$SEG
  agora_novo
  TZ18=$(tz_perto $((10#${H24%%:*} * 60 + 10#${H24##*:} + 10)))
  TZ=$TZ18 grava_em "$AP"
  EM_A=$EM_GRAVADO
  TZ=$TZ18 grava_em "$EQUIV"
  eq "OL18 · '$AP': o relógio local da leitura" "$H24:$SEG" "$(hora_em "$EM_A" "$TZ18" %H:%M:%S)"
  eq "OL18 · '$AP': mesmo epoch que $EQUIV" "$EM_GRAVADO" "$EM_A"
done

# OL19: o recibo mostra o fuso do sistema e a hora em UTC
agora_novo
E0=$(((AGORA - 300) / 60 * 60))
for tz in BRT3 IST-5:30; do
  TZ=$tz grava_em "$(hora_em "$E0" "$tz" %H:%M)"
  case $tz in BRT3) off=UTC-03:00 ;; *) off=UTC+05:30 ;; esac
  tem "OL19 · $tz: o recibo traz o deslocamento" "$SAI" "$off"
  tem "OL19 · $tz: o recibo traz a hora em UTC" "$SAI" "$(hora_em "$E0" UTC %H:%M) UTC"
  tem "OL19 · $tz: o começo do recibo é a hora digitada" "$SAI" "leitura gravada: 50% às $(hora_em "$E0" "$tz" %H:%M)"
done

# OL20: --descartar HH:MM acha a leitura do minuto mesmo com segundos diferentes de zero
agora_novo
E37=$(((AGORA / 60) * 60 - 360 + 37))
TZ=BRT3 grava_em "$E37"
TZ=BRT3 roda --descartar "$(hora_em "$E37" BRT3 %H:%M)"
eq "OL20 · leitura com segundos 37: código 0" 0 "$RC"
tem "OL20 · leitura com segundos 37: diz qual saiu" "$SAI" "DESCARTADA a leitura de $(iso "$E37") (50%)"
TZ=BRT3 grava_em "$E37"
TZ=BRT3 roda --descartar "$E37"
tem "OL20 · epoch com segundos: casa por igualdade" "$SAI" "DESCARTADA a leitura de $(iso "$E37") (50%)"
TZ=BRT3 grava_em "$E37"
roda --descartar $((E37 + 1))
eq "OL20 · epoch com segundos de outra leitura: nenhuma leitura nessa hora" 2 "$RC"
eq "OL20 · epoch com segundos de outra leitura: nada apagado" 1 "$(jq '.leituras | length' "$CAL")"

# OL21: duas leituras no mesmo minuto: recusa, nada apagado
agora_novo
E05=$(((AGORA / 60) * 60 - 360 + 5))
E40=$(((AGORA / 60) * 60 - 360 + 40))
novo
u "$M" a 3000 0 0 1000 0
roda --sessao "$SID" --calibrar 50 --em "$E05"
roda --sessao "$SID" --calibrar 40 --em "$E40"
TZ=BRT3 roda --descartar "$(hora_em "$E05" BRT3 %H:%M)"
eq "OL21 · duas leituras no mesmo minuto: uso errado" 2 "$RC"
tem "OL21 · duas leituras no mesmo minuto: pede a hora com segundos" "$ERR" "com segundos"
tem "OL21 · duas leituras no mesmo minuto: aponta o --leituras" "$ERR" "--leituras"
eq "OL21 · duas leituras no mesmo minuto: nada apagado" 2 "$(jq '.leituras | length' "$CAL")"
roda --descartar "$E40"
tem "OL21 · a hora com segundos desfaz a certa" "$SAI" "DESCARTADA a leitura de $(iso "$E40") (40%)"

# OL22: entrada hostil nunca vira programa nem comando
agora_novo
mkdir -p "$T/w22"
grava_em $((AGORA - 300))
HASH22=$(sha256sum "$CAL" | cut -c1-64)
for hostil in '1" | halt_error' '$(touch x)' '`touch x`' '; touch x' '2026-10-21T08:21:00Z" | halt_error'; do
  SAI=$(cd "$T/w22" && bash "$LOC" --sessao "$SID" --calibrar 50 --em "$hostil" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
  eq "OL22 · --em '$hostil': uso errado" 2 "$RC"
  tem "OL22 · --em '$hostil': lista as formas" "$ERR" "epoch"
  SAI=$(cd "$T/w22" && bash "$LOC" --descartar "$hostil" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
  eq "OL22 · --descartar '$hostil': uso errado" 2 "$RC"
  tem "OL22 · --descartar '$hostil': lista as formas" "$ERR" "epoch"
done
eq "OL22 · nenhum arquivo criado" "" "$(ls -A "$T/w22")"
eq "OL22 · calibração igual" "$HASH22" "$(sha256sum "$CAL" | cut -c1-64)"

# --- o /usage do transcript vira leitura (O-a a O-p) -------------------------------------------------
# Forma real do registro (medida em 2026-10-27 nos transcripts do próprio projeto): type system, subtype local_command,
# commandRun.command "usage", usageReport.rate_limits.limits com os itens session e weekly_all, e resets_at com fração
# de segundo e +00:00. Estes ajudantes escrevem essa forma e as que o script deve recusar.
# rs <epoch>: o resets_at como o /usage grava
rs() { iso "$1" | sed 's/Z$/.276355+00:00/'; }
# ur <arquivo> <segundos atrás> <pct> <resets_at da sessão> [pct da semana] [resets_at da semana]
ur() {
  mkdir -p "$(dirname "$1")"
  jq -nc --arg ts "$(iso $((AGORA - $2)))" --argjson p "$3" --arg fim "$4" --arg sem "${5:-}" --arg semfim "${6:-}" \
    '{type: "system", subtype: "local_command", timestamp: $ts, commandRun: {command: "usage", args: ""},
      content: "<local-command-stdout>You are currently using your subscription to power your Claude Code usage\n\nCurrent session: \($p)% used · resets Oct 20, 4:50pm (America/Sao_Paulo)\nCurrent week (all models): \($sem)% used</local-command-stdout>",
      usageReport: {rate_limits: {limits: ([{kind: "session", group: "session", percent: $p, resets_at: $fim, scope: null, severity: "normal", is_active: true}]
        + (if $sem == "" then [] else [{kind: "weekly_all", group: "weekly", percent: ($sem | tonumber), resets_at: $semfim, scope: null, severity: "normal", is_active: false}] end)),
        extra_usage: {is_enabled: false, monthly_limit: null}}}}' >>"$1"
}
# ut <arquivo> <segundos atrás> <texto>: /usage sem usageReport, só o texto
ut() {
  jq -nc --arg ts "$(iso $((AGORA - $2)))" --arg c "$3" \
    '{type: "system", subtype: "local_command", timestamp: $ts, commandRun: {command: "usage", args: ""}, content: $c}' >>"$1"
}
# ux <arquivo> <segundos atrás> <variante>: usageReport que não dá para usar (semsessao, percentualtexto, limitesnaolista)
ux() {
  jq -nc --arg ts "$(iso $((AGORA - $2)))" --arg v "$3" \
    '{type: "system", subtype: "local_command", timestamp: $ts, commandRun: {command: "usage", args: ""},
      content: "<local-command-stdout>formato novo, sem o texto de sempre</local-command-stdout>",
      usageReport: {rate_limits: (if $v == "semsessao" then {limits: [{kind: "weekly_all", percent: 12, resets_at: "2026-11-02T05:00:00+00:00"}]}
        elif $v == "percentualtexto" then {limits: [{kind: "session", percent: "46", resets_at: "2026-11-02T05:00:00+00:00"}]}
        else {limits: {kind: "session", percent: 46}} end)}}' >>"$1"
}
# calibração gravada há uma hora, sem leitura nem ponto: o aviso de formato só vale para o que veio depois dela
varrido_antigo() { mkdir -p "$T/c/seiva"; jq -nc --argjson v $((AGORA - 3600)) '{versao: 1, varrido_ate: $v, pontos: [], leituras: []}' >"$CAL"; }
# limite batido há 10 horas, com a janela inteira nos transcripts: dá um ponto de 100.000 tokens ponderados
ponto_antigo() {
  R=$((((AGORA - 36000) / 600) * 600))
  u "$O" p1 $((AGORA - (R - 18000) - 60)) 0 0 40000 0
  u "$O" p2 $((AGORA - (R - 3600))) 0 0 60000 0
  h "$O" $((AGORA - (R - 3000))) "$R"
}
LEI_GRAVADA='.leituras | length'

agora_novo
FIM=$(((AGORA + 7200) / 60 * 60))
HUSO=UTC

# O-a: usageReport de 46% na janela aberta: leitura gravada com f transcript e fim; a janela de 5 horas acaba no fim do /usage
novo
u "$M" a 3000 0 0 1000 0
u "$M" b 1500 0 0 500 0
ur "$M" 600 46 "$(rs "$FIM")"
u "$M" c 300 0 0 250 0
roda --sessao "$SID"
eq "O-a · código 0" 0 "$RC"
eq "O-a · uma leitura gravada" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-a · f é transcript" transcript "$(jq -r '.leituras[0].f' "$CAL")"
eq "O-a · fim é o resets_at da sessão, sem a fração" "$FIM" "$(jq -r '.leituras[0].fim' "$CAL")"
eq "O-a · em é a hora do registro" $((AGORA - 600)) "$(jq -r '.leituras[0].em' "$CAL")"
eq "O-a · pct" 46 "$(jq -r '.leituras[0].pct' "$CAL")"
eq "O-a · x: o gasto da janela até a leitura" 1500 "$(jq -r '.leituras[0].x' "$CAL")"
eq "O-a · a janela de 5 horas acaba no fim que o /usage deu" "$FIM" "$(campo .cinco_horas.reinicia)"
tem "O-a · a nota diz a âncora" "$SAI" "âncora: /usage das $(hora_em $((AGORA - 600)) $HUSO %H:%M) com 46%"
tem "O-a · 46% lidos mais 250 tokens sobre o limite que a leitura dá" "$SAI" "5h 53.6%"
tem "O-a · rótulo no singular" "$SAI" "leitura da janela: 1 leitura do /usage, a última às $(hora_em $((AGORA - 600)) $HUSO %H:%M)"
nao_tem "O-a · nenhum texto de conversa no estado" "$(cat "$JS" "$CAL")" "conversa que não pode sair"

# O-b: só o texto "Current session: 51% used" na janela aberta: leitura sem fim; fora da janela aberta, nada
novo
u "$M" a 3000 0 0 1000 0
u "$M" b 1500 0 0 500 0
ut "$M" 600 "$(printf '<local-command-stdout>You are currently using your subscription to power your Claude Code usage\n\nCurrent session: 51%% used · resets Oct 20, 4:50pm (America/Sao_Paulo)\nCurrent week (all models): 48%% used</local-command-stdout>')"
roda --sessao "$SID"
eq "O-b · uma leitura gravada" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-b · pct vem do texto" 51 "$(jq -r '.leituras[0].pct' "$CAL")"
eq "O-b · f é transcript" transcript "$(jq -r '.leituras[0].f' "$CAL")"
eq "O-b · o texto não traz o fim da janela" null "$(jq -c '.leituras[0].fim' "$CAL")"
eq "O-b · x: o gasto da janela aberta até a leitura" 1500 "$(jq -r '.leituras[0].x' "$CAL")"
tem "O-b · a nota diz a âncora" "$SAI" "âncora: /usage das $(hora_em $((AGORA - 600)) $HUSO %H:%M) com 51%"
novo
u "$M" a 3000 0 0 1000 0
ut "$M" 9000 "<local-command-stdout>Current session: 51% used · resets Oct 20, 4:50pm (America/Sao_Paulo)</local-command-stdout>"
roda --sessao "$SID"
eq "O-b · texto de antes da janela aberta: não vira leitura" 0 "$(jq "$LEI_GRAVADA" "$CAL")"

# O-c: usageReport sem session utilizável, depois do varrido_ate: aviso de formato, nada gravado, e só uma vez
agora_novo
for v in semsessao percentualtexto limitesnaolista; do
  novo
  u "$M" a 3000 0 0 1000 0
  varrido_antigo
  ux "$M" 600 "$v"
  ux "$M" 300 "$v"
  roda --sessao "$SID"
  eq "O-c · $v: código 0" 0 "$RC"
  tem "O-c · $v: aviso com a hora do mais recente" "$SAI" " · /usage das $(hora_em $((AGORA - 300)) $HUSO %H:%M) num formato que não reconheço: leitura ignorada"
  nao_tem "O-c · $v: a hora do mais antigo não aparece" "$SAI" "/usage das $(hora_em $((AGORA - 600)) $HUSO %H:%M)"
  eq "O-c · $v: nada gravado" 0 "$(jq "$LEI_GRAVADA" "$CAL")"
  roda --sessao "$SID"
  nao_tem "O-c · $v: na rodada seguinte o aviso não repete" "$SAI" "formato que não reconheço"
done
novo
u "$M" a 3000 0 0 1000 0
varrido_antigo
ut "$M" 300 "<local-command-stdout>Uso: 46 % da sessão</local-command-stdout>"
roda --sessao "$SID"
tem "O-c · texto com % que não casa: o aviso sai" "$SAI" "formato que não reconheço: leitura ignorada"
eq "O-c · texto com % que não casa: nada gravado" 0 "$(jq "$LEI_GRAVADA" "$CAL")"
# registro anterior ao varrido_ate já foi visto: sem aviso
novo
u "$M" a 3000 0 0 1000 0
ux "$M" 1200 semsessao
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 600)) '{versao: 1, varrido_ate: $v, pontos: [], leituras: []}' >"$CAL"
roda --sessao "$SID"
nao_tem "O-c · registro de antes do varrido_ate: sem aviso" "$SAI" "formato que não reconheço"

# O-c2: /usage sem número nenhum: nada gravado, sem aviso
novo
u "$M" a 3000 0 0 1000 0
varrido_antigo
ut "$M" 300 "<local-command-stdout>Não deu para ler o uso agora</local-command-stdout>"
jq -nc --arg ts "$(iso $((AGORA - 200)))" \
  '{type: "system", subtype: "local_command", timestamp: $ts, commandRun: {command: "usage", args: ""}, content: "", usageReport: null}' >>"$M"
roda --sessao "$SID"
eq "O-c2 · código 0" 0 "$RC"
nao_tem "O-c2 · sem aviso de formato" "$SAI" "formato que não reconheço"
eq "O-c2 · nada gravado" 0 "$(jq "$LEI_GRAVADA" "$CAL")"

# O-d: o transcript (46%) e a manual (46%) a menos de 15 minutos uma da outra são a mesma leitura: fica a do transcript,
# com o x e o y da manual, que passou na guarda
novo
u "$M" a 3000 0 0 1000 0
u "$M" b 800 0 0 500 0
EMM=$((AGORA - 753))
roda --sessao "$SID" --calibrar 46 --em "$EMM"
eq "O-d · a manual sozinha: uma leitura, x de 1500" 1500 "$(jq -r '.leituras[0].x' "$CAL")"
ur "$M" 900 46 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-d · transcript e manual: uma leitura só" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-d · a que fica é a do transcript" transcript "$(jq -r '.leituras[0].f' "$CAL")"
eq "O-d · com a hora do transcript" $((AGORA - 900)) "$(jq -r '.leituras[0].em' "$CAL")"
eq "O-d · com o x da que passou na guarda (a manual, 1500 e não 1000)" 1500 "$(jq -r '.leituras[0].x' "$CAL")"
eq "O-d · com o fim do /usage" "$FIM" "$(jq -r '.leituras[0].fim' "$CAL")"
# pct diferente ou mais de 15 minutos de distância: duas leituras
novo
u "$M" a 3000 0 0 1000 0
roda --sessao "$SID" --calibrar 45 --em $((AGORA - 753))
ur "$M" 900 46 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-d · pct diferente: duas leituras" 2 "$(jq "$LEI_GRAVADA" "$CAL")"
novo
u "$M" a 3000 0 0 1000 0
roda --sessao "$SID" --calibrar 46 --em $((AGORA - 2000))
ur "$M" 900 46 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-d · 1.100 s de distância: duas leituras" 2 "$(jq "$LEI_GRAVADA" "$CAL")"

# na mesma execução: a manual digitada e o /usage que o transcript já trazia
novo
u "$M" a 3000 0 0 1000 0
ur "$M" 900 46 "$(rs "$FIM")"
roda --sessao "$SID" --calibrar 46 --em $((AGORA - 753))
eq "O-d · mesma execução: uma leitura só" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-d · mesma execução: a do transcript" $((AGORA - 900)) "$(jq -r '.leituras[0].em' "$CAL")"
nao_tem "O-d · mesma execução: o recibo não manda desfazer (leitura do transcript não se descarta)" "$SAI" "para desfazer"
tem "O-d · mesma execução: o recibo diz que o transcript já trazia a leitura" "$SAI" "já trazia essa leitura no transcript"

# O-d2: a manual de HH:MM redondo (--em 23:30) e o transcript 32 segundos depois são a mesma leitura
novo
u "$M" a 3000 0 0 1000 0
EMR=$((((AGORA - 900) / 60) * 60))
roda --sessao "$SID" --calibrar 46 --em "$EMR"
ur "$M" $((AGORA - EMR - 32)) 46 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-d2 · manual 32 s antes do transcript: uma leitura só" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-d2 · com a hora do transcript" $((EMR + 32)) "$(jq -r '.leituras[0].em' "$CAL")"
eq "O-d2 · f é transcript" transcript "$(jq -r '.leituras[0].f' "$CAL")"

# O-e: leitura de 0% é âncora e não é gravada; o --leituras não quebra
novo
u "$M" a 3000 0 0 1000 0
roda --sessao "$SID" --calibrar 50 --em $((AGORA - 2500))
u "$M" c 1500 0 0 500 0
ur "$M" 1000 0 "$(rs "$FIM")"
u "$M" d 400 0 0 400 0
roda --sessao "$SID"
eq "O-e · código 0" 0 "$RC"
tem "O-e · a nota diz a âncora de 0%" "$SAI" "âncora: /usage das $(hora_em $((AGORA - 1000)) $HUSO %H:%M) com 0%"
tem "O-e · 0% mais 400 tokens sobre o limite da leitura manual (2.000)" "$SAI" "5h 20%"
eq "O-e · nada de 0% gravado" 0 "$(jq '[.leituras[] | select(.pct < 10)] | length' "$CAL")"
eq "O-e · só a manual continua gravada" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
roda --leituras
eq "O-e · --leituras: código 0" 0 "$RC"
tem "O-e · --leituras: conta uma" "$SAI" "LEITURAS 1"
nao_tem "O-e · --leituras: nenhum 0%" "$SAI" " · 0% · "
# arquivo com leitura de 0%: o --leituras pula a linha em vez de dividir por zero
novo
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 3600)) --argjson e $((AGORA - 600)) \
  '{versao: 1, varrido_ate: $v, pontos: [], leituras: [{em: $e, pct: 0, x: 100, y: 0}, {em: ($e + 60), pct: 50, x: 100, y: 0, f: "transcript"}]}' >"$CAL"
roda --leituras
eq "O-e · leitura de 0% no arquivo: código 0" 0 "$RC"
tem "O-e · leitura de 0% no arquivo: lista a outra" "$SAI" "LEITURAS 1"
tem "O-e · leitura de 0% no arquivo: a fonte da outra" "$SAI" "fonte transcript"

# O-f: leitura de 5% é âncora; não é ponto, não entra no rótulo e não é gravada; o limite segue a regra de hoje
novo
ponto_antigo
u "$M" hoje 600 0 0 50000 0
ur "$M" 300 5 "$(rs "$FIM")"
u "$M" depois 100 0 0 10000 0
roda --sessao "$SID"
eq "O-f · código 0" 0 "$RC"
tem "O-f · a nota diz a âncora de 5%" "$SAI" "âncora: /usage das $(hora_em $((AGORA - 300)) $HUSO %H:%M) com 5%"
tem "O-f · 5% mais 10.000 tokens sobre o limite batido (100.000)" "$SAI" "5h 15%"
tem "O-f · rótulo de hoje: só o limite batido" "$SAI" "menor de 1 ponto: 1 limite batido e 0 leituras do /usage"
nao_tem "O-f · não é leitura da janela" "$SAI" "leitura da janela"
eq "O-f · nenhuma leitura gravada" 0 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-f · o limite é o do ponto batido" 100000 "$(campo .estimativa.limite)"

# O-g: duas leituras de pct >= 10 na janela aberta mandam sobre limites batidos menores: o limite é a mediana delas
novo
ponto_antigo
u "$M" hoje 3000 0 0 50000 0
ur "$M" 2000 25 "$(rs "$FIM")"
u "$M" e 1500 0 0 30000 0
ur "$M" 1200 20 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-g · duas leituras gravadas" 2 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-g · limite: a mediana das duas (200.000 e 400.000), não o limite batido de 100.000" 200000 "$(campo .estimativa.limite)"
tem "O-g · rótulo" "$SAI" "leitura da janela: 2 leituras do /usage, a última às $(hora_em $((AGORA - 1200)) $HUSO %H:%M)"
eq "O-g · o ponto batido continua gravado" 1 "$(jq '.pontos | length' "$CAL")"
# três leituras: a do meio
u "$M" f 1000 0 0 10000 0
ur "$M" 900 30 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-g · três leituras: limite é a do meio (300.000)" 300000 "$(campo .estimativa.limite)"
tem "O-g · três leituras: rótulo" "$SAI" "leitura da janela: 3 leituras do /usage, a última às $(hora_em $((AGORA - 900)) $HUSO %H:%M)"
# D-7: a leitura digitada na janela aberta também é leitura da janela; manual e transcript juntas entram na mediana
novo
ponto_antigo
u "$M" hoje 3000 0 0 50000 0
roda --sessao "$SID" --calibrar 25 --em $((AGORA - 2000))
tem "O-g · manual na janela: é leitura da janela" "$SAI" "leitura da janela: 1 leitura do /usage, a última às $(hora_em $((AGORA - 2000)) $HUSO %H:%M)"
nao_tem "O-g · manual na janela: não é o rótulo dos pontos" "$SAI" "menor de"
eq "O-g · manual na janela: limite é o dela (200.000), não o do limite batido" 200000 "$(campo .estimativa.limite)"
u "$M" e 1500 0 0 30000 0
ur "$M" 1200 20 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-g · manual e transcript na janela: mediana das duas (200.000 e 400.000)" 200000 "$(campo .estimativa.limite)"
tem "O-g · manual e transcript na janela: duas leituras" "$SAI" "leitura da janela: 2 leituras do /usage, a última às $(hora_em $((AGORA - 1200)) $HUSO %H:%M)"

# O-h: sem leitura do transcript na janela aberta, vale a regra de hoje, com o mesmo rótulo
novo
ponto_antigo
FIMV=$(((AGORA - 3600) / 60 * 60))
u "$M" ant 12000 0 0 30000 0
ur "$M" 9000 40 "$(rs "$FIMV")"
u "$M" hoje 600 0 0 50000 0
roda --sessao "$SID"
eq "O-h · a leitura da janela anterior fica gravada" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
tem "O-h · rótulo de hoje" "$SAI" "menor de 2 pontos: 1 limite batido e 1 leitura do /usage"
nao_tem "O-h · não é leitura da janela" "$SAI" "leitura da janela"
eq "O-h · o limite é o menor dos pontos (a leitura dá 75.000)" 75000 "$(campo .estimativa.limite)"

# O-i: weekly_all de 12% lido na janela aberta, sem statusline: 7d 12%
novo
u "$M" a 3000 0 0 1000 0
SEMFIM=$((AGORA + 259200))
ur "$M" 600 46 "$(rs "$FIM")" 12 "$(rs "$SEMFIM")"
roda --sessao "$SID"
tem "O-i · 7d 12%" "$SAI" "7d 12%"
eq "O-i · sete_dias.usado" 12 "$(campo .sete_dias.usado)"
eq "O-i · sete_dias.reinicia é o resets_at da semana" "$SEMFIM" "$(campo .sete_dias.reinicia)"
eq "O-i · sete_dias.visto_em é a hora da leitura" $((AGORA - 600)) "$(campo .sete_dias.visto_em)"

# O-i2: weekly_all lido há dois dias não vale: 7d --
novo
FIMO=$((((AGORA - 172800 + 3600)) / 60 * 60))
u "$M" velho 173000 0 0 1000 0
ur "$M" 172800 46 "$(rs "$FIMO")" 12 "$(rs "$SEMFIM")"
u "$M" a 600 0 0 500 0
roda --sessao "$SID"
tem "O-i2 · 7d --" "$SAI" "7d --"
eq "O-i2 · sete_dias.usado nulo" null "$(campo .sete_dias.usado)"

# O-j: resets_at com deslocamento dá o mesmo epoch que o Z equivalente
for fimtxt in "$(iso "$FIM")" "$(rs "$FIM")" "$(iso $((FIM - 10800)) | sed 's/Z$/-03:00/')" "$(iso $((FIM + 19800)) | sed 's/Z$/+05:30/')" "$(iso $((FIM - 10800)) | sed 's/Z$/.5-0300/')"; do
  novo
  u "$M" a 3000 0 0 1000 0
  ur "$M" 600 46 "$fimtxt"
  roda --sessao "$SID"
  eq "O-j · resets_at '$fimtxt': mesmo epoch do Z" "$FIM" "$(jq -r '.leituras[0].fim' "$CAL" 2>/dev/null)"
done

# O-k: calibracao.json velho (leituras sem f): lido sem aviso; o --leituras diz manual
novo
u "$M" a 600 0 0 1000 0
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 3600)) --argjson e $((AGORA - 300)) '{versao: 1, varrido_ate: $v, pontos: [], leituras: [{em: $e, pct: 50, x: 1000, y: 0}]}' >"$CAL"
roda --sessao "$SID"
nao_tem "O-k · arquivo velho: sem aviso de calibração ilegível" "$SAI" "guardada em calibracao.json.invalido-"
eq "O-k · arquivo velho: nada guardado à parte" 0 "$(ls "$T/c/seiva" | grep -c '^calibracao\.json\.invalido-')"
eq "O-k · arquivo velho: a leitura continua" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
roda --leituras
tem "O-k · --leituras: leitura sem f é manual" "$SAI" "fonte manual"
nao_tem "O-k · --leituras: não é transcript" "$SAI" "fonte transcript"
ur "$M" 200 70 "$(rs "$FIM")"
roda --sessao "$SID"
roda --leituras
tem "O-k · --leituras: a do transcript diz transcript" "$SAI" "fonte transcript"
tem "O-k · --leituras: a manual continua manual" "$SAI" "fonte manual"

# O-l: leitura gravada cuja janela começou antes da varredura, com um subagente dela fora da varredura: x e y gravados ficam
agora_novo
FIM=$(((AGORA + 7200) / 60 * 60))
novo
FIMO=$((((AGORA - 72000)) / 60 * 60))
EMO=$((FIMO - 1000))
mkdir -p "$T/c/seiva" "$T/tr/-proj/$SID/subagents"
u "$T/tr/-proj/$SID/subagents/agent-9.jsonl" sub 73000 0 0 4000 0 claude-haiku-teste true
touch -d "@$((AGORA - 259200))" "$T/tr/-proj/$SID/subagents/agent-9.jsonl"
u "$M" velho 73500 0 0 100 0
ur "$M" $((AGORA - EMO)) 46 "$(rs "$FIMO")"
u "$M" a 3000 0 0 1000 0
ur "$M" 600 46 "$(rs "$FIM")"
jq -nc --argjson v $((AGORA - 3600)) --argjson e "$EMO" --argjson fim "$FIMO" \
  '{versao: 1, varrido_ate: $v, pontos: [], leituras: [{em: $e, pct: 46, x: 4100, y: 0, f: "transcript", fim: $fim}]}' >"$CAL"
roda --sessao "$SID"
eq "O-l · a leitura nova entra e a velha fica" 2 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-l · janela antes da varredura: x gravado fica (4.100, não os 100 que a varredura vê)" 4100 "$(jq -r --argjson e "$EMO" '.leituras[] | select(.em == $e) | .x' "$CAL")"
eq "O-l · a leitura nova tem o x da sua janela" 1000 "$(jq -r --argjson e $((AGORA - 600)) '.leituras[] | select(.em == $e) | .x' "$CAL")"
# janela dentro da varredura: leitura já gravada com o mesmo em mantém o x e o y gravados
novo
u "$M" a 3000 0 0 1000 0
ur "$M" 600 46 "$(rs "$FIM")"
mkdir -p "$T/c/seiva"
jq -nc --argjson v $((AGORA - 3600)) --argjson e $((AGORA - 600)) --argjson fim "$FIM" \
  '{versao: 1, varrido_ate: $v, pontos: [], leituras: [{em: $e, pct: 46, x: 5000, y: 0, f: "transcript", fim: $fim}]}' >"$CAL"
roda --sessao "$SID"
eq "O-l · mesmo em: uma leitura só" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-l · mesmo em: o x gravado fica (5.000, não os 1.000 recalculados)" 5000 "$(jq -r '.leituras[0].x' "$CAL")"

# O-m: leitura numa janela já fechada: nenhum ponto novo e nenhum "bateu no limite"
novo
FIMC=$(((AGORA - 3600) / 60 * 60))
u "$M" a 20000 0 0 1000 0
ur "$M" 4000 46 "$(rs "$FIMC")"
u "$M" agora 300 0 0 100 0
roda --sessao "$SID"
eq "O-m · a leitura da janela fechada fica gravada" 1 "$(jq "$LEI_GRAVADA" "$CAL")"
eq "O-m · nenhum ponto de limite novo" 0 "$(jq '.pontos | length' "$CAL")"
nao_tem "O-m · nenhum bateu no limite" "$SAI" "a conta bateu no limite de 5 horas"
eq "O-m · a janela aberta não é a do /usage fechado" false "$([ "$(campo .cinco_horas.reinicia)" = "$FIMC" ] && echo true || echo false)"

# O-n: --tarefa com a pasta de trabalho ou com a pasta tarefas: código 2, sem sessoes e sem nada criado
novo
u "$M" a 60 100000 0 0 0
mkdir -p "$T/trabalho/tarefas/t1" "$T/trabalho/outra/tarefas"
: >"$T/trabalho/tarefas/t1/registro.md"
TR=$(cd "$T/trabalho" && pwd -P)
roda --sessao "$SID" --tarefa "$T/trabalho"
eq "O-n · pasta de trabalho: código 2" 2 "$RC"
tem "O-n · pasta de trabalho: a mensagem" "$ERR" "orcamento-local.sh: $TR é pasta de trabalho (tem tarefas/); --tarefa pede a pasta da tarefa, $TR/tarefas/<tarefa>"
eq "O-n · pasta de trabalho: sem sessoes" no "$([ -e "$T/trabalho/sessoes" ] && echo sim || echo no)"
eq "O-n · pasta de trabalho: nada criado no cache" no "$([ -e "$T/c/seiva" ] && echo sim || echo no)"
ln -s "$T/trabalho" "$T/atalho"
roda --sessao "$SID" --tarefa "$T/atalho"
eq "O-n · atalho para a pasta de trabalho: código 2" 2 "$RC"
tem "O-n · atalho: a mensagem traz o caminho resolvido" "$ERR" "orcamento-local.sh: $TR é pasta de trabalho"
roda --sessao "$SID" --tarefa "$T/trabalho/tarefas"
eq "O-n · pasta tarefas: código 2" 2 "$RC"
tem "O-n · pasta tarefas: a mensagem" "$ERR" "orcamento-local.sh: $TR/tarefas é a pasta tarefas/; --tarefa pede uma tarefa dentro dela, $TR/tarefas/<tarefa>"
eq "O-n · pasta tarefas: sem sessoes" no "$([ -e "$T/trabalho/tarefas/sessoes" ] && echo sim || echo no)"
eq "O-n · pasta tarefas: nada criado no cache" no "$([ -e "$T/c/seiva" ] && echo sim || echo no)"
roda --sessao "$SID" --tarefa "$T/trabalho/tarefas/t1"
eq "O-n · a tarefa dentro dela vale: código 0" 0 "$RC"
tem "O-n · a tarefa vale: a sessão é marcada" "$(cat "$T/trabalho/tarefas/t1/sessoes" 2>/dev/null)" " $SID"
roda --sessao "$SID" --tarefa "$T/trabalho/outra/tarefas"
eq "O-n · pasta chamada tarefas sem registro nas subpastas é pasta de tarefa: código 0" 0 "$RC"

# O-p: a mesma execução duas vezes seguidas: mesmo estado, sem leitura duplicada
novo
ponto_antigo
u "$M" a 3000 0 0 1000 0
ur "$M" 600 46 "$(rs "$FIM")" 12 "$(rs "$SEMFIM")"
ut "$M" 500 "<local-command-stdout>Current session: 12% used · resets Oct 20, 4:50pm (America/Sao_Paulo)</local-command-stdout>"
roda --sessao "$SID"
jq -S 'del(.varrido_ate)' "$CAL" >"$T/cal1"
jq -S 'del(.gravado_em) | del(.cinco_horas.visto_em) | del(.sete_dias.visto_em)' "$JS" >"$T/js1"
roda --sessao "$SID"
eq "O-p · calibração igual na 2ª vez" "$(cat "$T/cal1")" "$(jq -S 'del(.varrido_ate)' "$CAL")"
eq "O-p · estado igual na 2ª vez" "$(cat "$T/js1")" "$(jq -S 'del(.gravado_em) | del(.cinco_horas.visto_em) | del(.sete_dias.visto_em)' "$JS")"
eq "O-p · sem leitura duplicada" 2 "$(jq "$LEI_GRAVADA" "$CAL")"

# O-q: --descartar de leitura do transcript é recusado (código 2), sem apagar nada; a manual continua descartável
agora_novo
FIM=$(((AGORA + 7200) / 60 * 60))
novo
u "$M" a 3000 0 0 1000 0
roda --sessao "$SID" --calibrar 50 --em $((AGORA - 2000))
ur "$M" 600 46 "$(rs "$FIM")"
roda --sessao "$SID"
eq "O-q · uma manual e uma do transcript" 2 "$(jq "$LEI_GRAVADA" "$CAL")"
HASHQ=$(sha256sum "$CAL" | cut -c1-64)
roda --descartar ultima
eq "O-q · ultima é do transcript: código 2" 2 "$RC"
tem "O-q · diz que a leitura vem do transcript" "$ERR" "vem do transcript"
tem "O-q · diz que volta na varredura seguinte" "$ERR" "volta na varredura seguinte"
tem "O-q · diz que nada foi apagado" "$ERR" "nada apagado"
roda --descartar $((AGORA - 600))
eq "O-q · por epoch exato: código 2" 2 "$RC"
roda --descartar "$(iso $((AGORA - 600)))"
eq "O-q · por ISO com segundos: código 2" 2 "$RC"
tem "O-q · por ISO: a mensagem" "$ERR" "vem do transcript"
eq "O-q · nada apagado: calibração igual" "$HASHQ" "$(sha256sum "$CAL" | cut -c1-64)"
roda --descartar $((AGORA - 2000))
eq "O-q · a manual se descarta: código 0" 0 "$RC"
tem "O-q · a manual: diz qual saiu" "$SAI" "DESCARTADA a leitura de $(iso $((AGORA - 2000))) (50%)"
eq "O-q · sobra a do transcript" transcript "$(jq -r '.leituras[0].f' "$CAL")"
eq "O-q · sobra só uma" 1 "$(jq "$LEI_GRAVADA" "$CAL")"

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
