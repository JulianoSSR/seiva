#!/usr/bin/env bash
# Testa scripts/medir.sh (e a 1ª marca de sessão do nova-tarefa.sh) com transcripts falsos numa pasta temporária.
# HOME, XDG_CACHE_HOME e SEIVA_TRANSCRIPTS apontam para a pasta temporária: o ~/.cache/seiva e o ~/.claude de verdade
# não podem mudar (o último caso confere). Só valores falsos óbvios.
# Uso: bash testes/scripts/teste-medir.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
MED="$RAIZ/scripts/medir.sh"

cache_real="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/seiva"
custos_real=$(sha256sum "$cache_real/custos.jsonl" 2>/dev/null | cut -c1-64)

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" TZ=UTC
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID PESO_CACHE_LEITURA
AGORA=$(date +%s)
NOME=2026-10-01-tarefa-teste
S1=sessao-teste-0001

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

# Cada caso começa do zero: transcripts, cache e pasta de trabalho novos.
novo() {
  rm -rf "$T/c" "$T/tr" "$T/w" "$HOME"
  mkdir -p "$T/c" "$T/tr/-proj" "$T/w/tarefas/$NOME" "$HOME"
  export XDG_CACHE_HOME="$T/c" SEIVA_TRANSCRIPTS="$T/tr"
  P=$T/w/tarefas/$NOME
  H=$T/c/seiva/custos.jsonl
  printf '# Tarefa teste\n- Nível: N2 — teste\n' >"$P/registro.md"
}
iso() { jq -nr --argjson t "$1" '$t | todate'; }
# u <arquivo> <id> <segundos atrás> <in> <out> <escrita cache> <leitura cache> [modelo]
u() {
  mkdir -p "$(dirname "$1")"
  jq -nc --arg id "$2" --arg ts "$(iso $((AGORA - $3)))" --argjson i "$4" --argjson o "$5" --argjson cw "$6" --argjson cr "$7" \
    --arg m "${8:-claude-opus-teste}" \
    '{type: "assistant", timestamp: $ts, requestId: ("req_" + $id), sessionId: "x",
      message: {id: ("msg_" + $id), model: $m, content: [{type: "text", text: "conversa que não pode sair"}],
                usage: {input_tokens: $i, output_tokens: $o, cache_creation_input_tokens: $cw, cache_read_input_tokens: $cr}}}' >>"$1"
}
# e <arquivo> <segundos atrás>: resposta de erro da API (limite de uso)
e() {
  jq -nc --arg ts "$(iso $((AGORA - $2)))" \
    '{type: "assistant", timestamp: $ts, isApiErrorMessage: true, apiErrorStatus: 429,
      message: {id: "erro", model: "<synthetic>", content: [{type: "text", text: "limite"}],
                usage: {input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}}}' >>"$1"
}
# msg <arquivo> <texto> [meta]: mensagem que o agente recebe
msg() { mkdir -p "$(dirname "$1")"; jq -nc --arg t "$2" --argjson m "${3:-false}" '{type: "user", isMeta: $m, message: {role: "user", content: $t}}' >>"$1"; }
# res <arquivo>: resultado de ferramenta (não é corrida)
res() { jq -nc '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "x", content: "saída"}]}}' >>"$1"; }
# chamada <arquivo principal> <agente> <descrição>: a chamada do Agent no transcript principal
chamada() { jq -nc --arg a "$2" --arg d "$3" '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "y", content: "ok"}]}, toolUseResult: {agentId: $a, description: $d, status: "completed"}}' >>"$1"; }
meta() { mkdir -p "$(dirname "$1")"; jq -nc --arg d "$2" '{agentType: "general-purpose", description: $d, model: "x"}' >"$1"; }
velho() { touch -d "@$((AGORA - 600))" "$@"; }
roda() {
  SAI=$(cd "$T/w" && bash "$MED" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}
md() { cat "$P/medicao.md" 2>/dev/null; }

# Cenário base: sessão S1 com orquestrador, dois agentes desta tarefa e um de outra.
#   orquestrador: 1000 ponderados (um 600 às 5000 s atrás, um 400 às 1000 s atrás)
#   agente a1 (construtor, opus): 1100 + 500 = 1600, uma queda, uma retomada; a mesma resposta repetida conta uma vez
#   agente a2 (lente, sonnet, descrição só no transcript principal): 300
#   agente a3 (outra tarefa, haiku): 600
base() {
  M=$T/tr/-proj/$S1.jsonl
  D=$T/tr/-proj/$S1/subagents
  u "$M" o1 5000 600 0 0 0
  u "$M" o2 1000 400 0 0 0
  chamada "$M" a2 "Lente segurança do plano"
  msg "$D/agent-a1.jsonl" "PAPEL: construtor. Leia .claude/seiva/tarefas/$NOME/relatorios/pacote-construtor-r1.md"
  msg "$D/agent-a1.jsonl" "<system-reminder>lembrete</system-reminder>" true
  u "$D/agent-a1.jsonl" a1x 4000 1000 0 0 10000
  u "$D/agent-a1.jsonl" a1x 4000 1000 0 0 10000
  res "$D/agent-a1.jsonl"
  e "$D/agent-a1.jsonl" 3900
  msg "$D/agent-a1.jsonl" "The coordinator sent a message while you were working: continue" true
  u "$D/agent-a1.jsonl" a1y 3000 500 0 0 0
  meta "$D/agent-a1.meta.json" "Construtor: plano da tarefa"
  msg "$D/agent-a2.jsonl" "PAPEL: lente. Pasta $NOME"
  u "$D/agent-a2.jsonl" a2x 2000 300 0 0 0 claude-sonnet-teste
  msg "$D/agent-a3.jsonl" "PAPEL: batedor de outra coisa"
  u "$D/agent-a3.jsonl" a3x 2000 600 0 0 0 claude-haiku-teste
  meta "$D/agent-a3.meta.json" "Batedor: outra tarefa"
  velho "$D"/agent-*.jsonl
}

# --- uso errado -------------------------------------------------------------------
novo
roda
eq "sem --tarefa: uso errado" 2 "$RC"
roda --tarefa "$T/nao-existe"
eq "--tarefa que não é pasta: uso errado" 2 "$RC"
roda --tarefa "$P" --sessao 'a b'
eq "--sessao com espaço: uso errado" 2 "$RC"
roda --tarefa "$P" --xyz
eq "opção desconhecida: uso errado" 2 "$RC"
PESO_CACHE_LEITURA=x roda --tarefa "$P" --sessao "$S1"
eq "PESO_CACHE_LEITURA inválido: uso errado" 2 "$RC"

# --- sem sessão: diz o motivo e lista as candidatas do projeto ----------------------
novo
base
mkdir -p "$T/tr/$(printf '%s' "$T/w" | sed 's/[^A-Za-z0-9]/-/g')"
cp "$T/tr/-proj/$S1.jsonl" "$T/tr/$(printf '%s' "$T/w" | sed 's/[^A-Za-z0-9]/-/g')/candidata-0001.jsonl"
msg "$T/tr/$(printf '%s' "$T/w" | sed 's/[^A-Za-z0-9]/-/g')/candidata-0001.jsonl" "cita $NOME"
roda --tarefa "$P"
eq "sem sessão: código 0" 0 "$RC"
tem "sem sessão: estado sem-sessao" "$SAI" "MEDICAO $NOME sem-sessao"
tem "sem sessão: lista a candidata" "$SAI" "candidata-0001"
eq "sem sessão: não grava medicao.md" "" "$(md)"
eq "sem sessão: não grava histórico" no "$([ -e "$H" ] && echo sim || echo no)"

# --- tarefa antiga (--sessao, sem marca): sessão inteira, dividida com outra tarefa -----
novo
base
roda --tarefa "$P" --sessao "$S1"
eq "--sessao: código 0" 0 "$RC"
tem "--sessao: 2 agentes da tarefa" "$SAI" "2 agente(s) da tarefa"
tem "--sessao: sessão inteira avisada" "$SAI" "sessão sem marca contada inteira"
tem "--sessao: agente de outra tarefa fora da conta" "$SAI" "1 subagente(s) das mesmas sessões cujo pacote não cita a pasta"
tem "--sessao: orquestrador estimado (sessão dividida)" "$SAI" "estimado em 1 de 1 sessão(ões) dividida(s)"
tem "--sessao: quedas" "$SAI" "quedas: 1 em 1 agente(s)"
tem "md: construtor com 1.600 (resposta repetida conta uma vez; leitura de cache a 1%)" "$(md)" "| construtor | opus-teste |"
tem "md: ponderado do construtor" "$(md)" "| 2 | 1 | 2 | 1.600 | Construtor: plano da tarefa |"
tem "md: lente pela descrição do transcript principal" "$(md)" "| lente | sonnet-teste |"
tem "md: ponderado da lente" "$(md)" "| 1 | 0 | 1 | 300 | Lente segurança do plano |"
tem "md: orquestrador 76% de 1.000 (1.900 de 2.500 nos subagentes)" "$(md)" "760 (estimado: 76% de 1.000)"
tem "md: total" "$(md)" "Subagentes: 1.900 · orquestrador: 760 (estimado em parte) · total: 2.660"
nao_tem "md: agente de outra tarefa fora" "$(md)" "Batedor: outra tarefa"
nao_tem "saída sem texto de conversa" "$SAI" "conversa que não pode sair"
nao_tem "md sem texto do pacote" "$(md)" "PAPEL:"
eq "histórico: 2 agentes + orquestrador" 3 "$(wc -l <"$H")"
eq "histórico: modo 600" 600 "$(stat -c %a "$H")"
eq "histórico: construtor" '{"papel":"construtor","modelo":"opus","nivel":"N2","ponderado":1600,"quedas":1,"corridas":2}' \
  "$(jq -c 'select(.agente == "a1") | {papel, modelo, nivel, ponderado, quedas, corridas}' "$H")"
eq "histórico: orquestrador estimado" '{"papel":"orquestrador","ponderado":760,"estimado":true}' \
  "$(jq -c 'select(.papel == "orquestrador") | {papel, ponderado, estimado}' "$H")"
nao_tem "histórico sem descrição" "$(cat "$H")" "plano da tarefa"
nao_tem "histórico sem nome da tarefa" "$(cat "$H")" "$NOME"
nao_tem "histórico sem caminho" "$(cat "$H")" "$T"
roda --tarefa "$P" --sessao "$S1"
eq "medir de novo não duplica o histórico" 3 "$(wc -l <"$H")"
PESO_CACHE_LEITURA=0 roda --tarefa "$P" --sessao "$S1"
tem "PESO_CACHE_LEITURA=0: construtor sem a leitura de cache" "$(md)" "| 1.500 |"

# --- marcas: só o orquestrador entre a 1ª e a última; sem outra tarefa, medido --------
novo
base
rm -f "$T/tr/-proj/$S1/subagents/agent-a3."*
printf '%s %s\n' $((AGORA - 4500)) "$S1" $((AGORA - 500)) "$S1" >"$P/sessoes"
roda --tarefa "$P"
eq "marcas: código 0" 0 "$RC"
tem "marcas: orquestrador medido" "$SAI" "(medido)"
nao_tem "marcas: não diz sessão inteira" "$SAI" "contada inteira"
tem "marcas: só a resposta de dentro da janela (400)" "$(md)" "| 1 | 400 | entre a 1ª e a última marca |"
tem "marcas: avisa que a janela não foi fechada" "$SAI" "rode com --fechar"

# --- --fechar: marca a sessão atual e a janela vai até agora ---------------------------
CLAUDE_CODE_SESSION_ID=$S1 roda --tarefa "$P" --fechar
tem "--fechar: grava a marca com fechar" "$(tail -n 1 "$P/sessoes")" " $S1 fechar"
nao_tem "--fechar: não avisa mais" "$SAI" "rode com --fechar"
roda --tarefa "$P" --fechar
tem "--fechar sem id da sessão: avisa" "$SAI" "--fechar sem CLAUDE_CODE_SESSION_ID"

# --- agente de outra tarefa dentro da janela das marcas: estimado pela proporção -------
novo
base
printf '%s %s\n' $((AGORA - 4500)) "$S1" $((AGORA - 500)) "$S1" >"$P/sessoes"
roda --tarefa "$P"
tem "agente de outra tarefa na janela: 76% de 400" "$(md)" "304 (estimado: 76% de 400)"

# --- outra tarefa marcou a mesma sessão, sem subagente: estimado em partes iguais -------
novo
base
rm -f "$T/tr/-proj/$S1/subagents/agent-a3."*
printf '%s %s\n' $((AGORA - 4500)) "$S1" $((AGORA - 500)) "$S1" >"$P/sessoes"
mkdir -p "$T/w/tarefas/outra"
printf '%s %s\n' $((AGORA - 3000)) "$S1" >"$T/w/tarefas/outra/sessoes"
roda --tarefa "$P"
tem "outra tarefa na janela: estimado" "$SAI" "estimado em 1 de 1"
tem "outra tarefa sem subagente: metade" "$(md)" "200 (estimado: 50% de 400)"

# --- agente rodando: medido, fora do histórico ---------------------------------------
novo
base
touch "$T/tr/-proj/$S1/subagents/agent-a2.jsonl"
roda --tarefa "$P" --sessao "$S1"
tem "rodando: avisado" "$SAI" "1 agente(s) rodando"
tem "rodando: marcado no md" "$(md)" "300 (rodando)"
eq "rodando: fora do histórico" "" "$(jq -r 'select(.agente == "a2") | .agente' "$H")"

# --- histórico com linha ilegível: guardado inteiro antes de ser refeito ---------------
novo
base
mkdir -p "$T/c/seiva"
printf '{"agente":"velho","papel":"batedor","modelo":"haiku","ponderado":5,"quedas":0,"corridas":1}\nlixo\n' >"$H"
roda --tarefa "$P" --sessao "$S1"
tem "histórico ilegível: avisado" "$SAI" "1 linha(s) ilegível(is) no histórico"
eq "histórico ilegível: cópia guardada" 1 "$(ls "$T/c/seiva"/custos.jsonl.invalido-* 2>/dev/null | wc -l)"
eq "histórico ilegível: a linha boa ficou" velho "$(jq -r 'select(.agente == "velho") | .agente' "$H")"

# --- nível: dois níveis diferentes no registro ficam sem nível -----------------------
novo
base
printf -- '- Nível A: N2\n- Nível B: N3\n' >"$P/registro.md"
roda --tarefa "$P" --sessao "$S1"
eq "dois níveis: nível nulo" null "$(jq -c 'select(.agente == "a1") | .nivel' "$H")"

# --- sessão sem transcript ------------------------------------------------------------
novo
roda --tarefa "$P" --sessao sessao-apagada
tem "sessão sem transcript: avisada" "$SAI" "sem transcript"

# --- nova-tarefa.sh: 1ª marca com o id da sessão; sem ele, nenhuma ------------------
novo
(cd "$T/w" && CLAUDE_CODE_SESSION_ID=$S1 bash "$RAIZ/scripts/nova-tarefa.sh" "$T/w" com-id >/dev/null 2>&1)
tem "nova-tarefa: marca a sessão" "$(cat "$T/w/tarefas/"*-com-id/sessoes 2>/dev/null)" " $S1"
(cd "$T/w" && bash "$RAIZ/scripts/nova-tarefa.sh" "$T/w" sem-id >/dev/null 2>&1)
eq "nova-tarefa sem id: sem marca" no "$([ -e "$(echo "$T/w/tarefas/"*-sem-id)/sessoes" ] && echo sim || echo no)"

# --- o histórico de verdade não mudou ---------------------------------------------------
eq "custos.jsonl de verdade não mudou (hash)" "$custos_real" "$(sha256sum "$cache_real/custos.jsonl" 2>/dev/null | cut -c1-64)"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
