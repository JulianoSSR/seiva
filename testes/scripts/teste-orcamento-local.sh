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
tem "nota diz manual" "$SAI" "manual de"
roda --sessao "$SID"
tem "calibração manual vale na rodada seguinte" "$SAI" "5h 50%"
PESO_CACHE_LEITURA=0.1 roda --sessao "$SID"
eq "PESO_CACHE_LEITURA=0.1 muda o total" 2150 "$(campo .estimativa.tokens)"
roda --sessao "$SID" --calibrar 75
eq "75%: restrito, código 10" 10 "$RC"
tem "75%: restrito" "$SAI" "ORCAMENTO restrito"
roda --sessao "$SID" --calibrar 90
eq "90%: parar, código 20" 20 "$RC"
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
tem "auto: a nota diz auto" "$SAI" "auto, 1 limite batido"
eq "auto: um ponto gravado" 1 "$(jq '.pontos | length' "$CAL")"
# Manual mais nova que o último limite vale mais; o próximo limite batido volta a mandar.
roda --sessao "$SID" --calibrar 25
tem "manual mais nova que o limite manda" "$SAI" "5h 25%"

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
