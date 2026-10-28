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
comeca() {
  n=$((n + 1))
  case $2 in
    "$3"*) ;;
    *)
      erros=$((erros + 1))
      echo "FALHA: $1"
      printf '  | devia começar por: %s\n  | texto: %s\n' "$3" "$2"
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

# Orquestrador sozinho, sem subagente: 600 às 8000 s atrás, 400 às 4000 e 200 às 500 (1.200 ao todo).
simples() {
  M=$T/tr/-proj/$S1.jsonl
  u "$M" r1 8000 600 0 0 0
  u "$M" r2 4000 400 0 0 0
  u "$M" r3 500 200 0 0 0
}
# marcar <segundos atrás>...: uma marca de S1 em <pasta>/sessoes para cada tempo dado
marcar() {
  local t
  for t in "$@"; do printf '%s %s\n' $((AGORA - t)) "$S1"; done >>"$P/sessoes"
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

# --- janela do orquestrador (MD1 a MD11) -----------------------------------------------
# MD1: uma marca só deixa a janela vazia: nada contado, e a saída diz isso em vez de "medido"
novo
simples
marcar 3000
roda --tarefa "$P"
eq "MD1 · uma marca só: código 0" 0 "$RC"
tem "MD1 · uma marca só: a 2ª linha diz que a janela é vazia" "$SAI" "orquestrador ≈ 0 mil (janela vazia em 1 de 1 sessão: ver aviso)"
nao_tem "MD1 · uma marca só: não diz medido" "$SAI" "(medido)"
tem "MD1 · uma marca só: o aviso cita --sessao" "$SAI" "--sessao $S1"
tem "MD1 · uma marca só: o aviso conta 1 marca" "$SAI" "1 marca(s) no mesmo segundo"
nao_tem "MD1 · uma marca só: não diz contado até a última marca" "$SAI" "contado até a última marca"
tem "MD1 · uma marca só: medicao.md soma 0" "$(md)" "Subagentes: 0 · orquestrador: 0 · total: 0"
tem "MD1 · uma marca só: medicao.md diz janela vazia" "$(md)" "janela vazia: 1 marca(s) no mesmo segundo"

# MD2: --sessao conta a sessão inteira mesmo com uma marca
novo
simples
marcar 3000
roda --tarefa "$P" --sessao "$S1"
tem "MD2 · --sessao com uma marca: a saída diz que a marca foi ignorada" "$SAI" "sessão contada inteira por --sessao, apesar da marca em "
tem "MD2 · --sessao com uma marca: a saída nomeia a sessão" "$SAI" "/sessoes: ${S1:0:8}"
tem "MD2 · --sessao com uma marca: orquestrador 1.200" "$(md)" "Subagentes: 0 · orquestrador: 1.200 · total: 1.200"
tem "MD2 · --sessao com uma marca: medicao.md diz marca ignorada" "$(md)" "sessão inteira (--sessao), marca ignorada"
nao_tem "MD2 · --sessao com uma marca: sem janela vazia" "$SAI" "janela vazia"
nao_tem "MD2 · --sessao com uma marca: não pede --fechar" "$SAI" "rode com --fechar"
nao_tem "MD2 · --sessao com uma marca: não diz que a sessão não tinha marca" "$SAI" "sessão sem marca contada inteira"
eq "MD2 · --sessao com uma marca: histórico com a linha orq-S" "orq-$S1" "$(jq -r '.agente | sub(":[0-9a-f]{12}$"; "")' "$H")"
eq "MD2 · --sessao com uma marca: histórico com 1 linha de 1.200" "1:1200" "$(wc -l <"$H" | tr -d ' '):$(jq -r '.ponderado' "$H")"

# MD3: --sessao com duas marcas conta 1.200 e não os 400 de dentro das marcas
novo
simples
marcar 6000 2000
roda --tarefa "$P" --sessao "$S1"
tem "MD3 · --sessao com duas marcas: orquestrador 1.200 e não 400" "$(md)" "Subagentes: 0 · orquestrador: 1.200 · total: 1.200"
tem "MD3 · --sessao com duas marcas: a saída diz que as marcas foram ignoradas" "$SAI" "contada inteira por --sessao, apesar da marca em "
nao_tem "MD3 · --sessao com duas marcas: não pede --fechar" "$SAI" "rode com --fechar"
novo
simples
marcar 6000 2000
mkdir -p "$T/w/tarefas/outra"
printf '%s %s\n' $((AGORA - 3000)) "$S1" >"$T/w/tarefas/outra/sessoes"
roda --tarefa "$P" --sessao "$S1"
tem "MD3 · --sessao e marca de outra tarefa na sessão: continua dividida" "$(md)" "600 (estimado: 50% de 1.200)"

# MD4: duas marcas sem --sessao: a janela das marcas
novo
simples
marcar 6000 2000
roda --tarefa "$P"
tem "MD4 · duas marcas: orquestrador 400" "$(md)" "Subagentes: 0 · orquestrador: 400 · total: 400"
tem "MD4 · duas marcas: pede --fechar" "$SAI" "rode com --fechar"
tem "MD4 · duas marcas: medido" "$SAI" "(medido)"
nao_tem "MD4 · duas marcas: sem janela vazia" "$SAI" "janela vazia"

# MD5: --sessao numa sessão que outra tarefa também marcou: continua estimado e dividido
novo
simples
mkdir -p "$T/w/tarefas/outra"
printf '%s %s\n' $((AGORA - 3000)) "$S1" >"$T/w/tarefas/outra/sessoes"
roda --tarefa "$P" --sessao "$S1"
tem "MD5 · outra tarefa marcou a sessão: estimado" "$SAI" "estimado em 1 de 1 sessão(ões) dividida(s)"
tem "MD5 · outra tarefa marcou a sessão: dividido ao meio" "$(md)" "600 (estimado: 50% de 1.200)"

# MD6: --sessao sem marca: o texto de sempre
novo
simples
roda --tarefa "$P" --sessao "$S1"
tem "MD6 · --sessao sem marca: sessão sem marca contada inteira" "$SAI" "sessão sem marca contada inteira: ${S1:0:8}"
tem "MD6 · --sessao sem marca: medicao.md" "$(md)" "sessão inteira, sem marca"
tem "MD6 · --sessao sem marca: orquestrador 1.200" "$(md)" "Subagentes: 0 · orquestrador: 1.200 · total: 1.200"
nao_tem "MD6 · --sessao sem marca: não fala de marca ignorada" "$SAI" "apesar da marca"

# MD7: medir de novo não duplica a linha do orquestrador nem muda a dos agentes
novo
base
marcar 6000 2000
roda --tarefa "$P" --sessao "$S1"
antes=$(jq -c 'del(.medido_em)' "$H" | sort)
roda --tarefa "$P" --sessao "$S1"
eq "MD7 · medir de novo: as mesmas linhas" "$antes" "$(jq -c 'del(.medido_em)' "$H" | sort)"
eq "MD7 · medir de novo: uma linha orq-S" 1 "$(jq -r 'select(.agente | startswith("orq-'"$S1"':")) | .agente' "$H" | wc -l | tr -d ' ')"
eq "MD7 · medir de novo: 3 linhas ao todo" 3 "$(wc -l <"$H" | tr -d ' ')"

# MD8: marca de abertura e --fechar: a janela vai da marca até agora, sem aviso de janela vazia
novo
simples
marcar 6000
CLAUDE_CODE_SESSION_ID=$S1 roda --tarefa "$P" --fechar
nao_tem "MD8 · marca e --fechar: sem janela vazia na saída" "$SAI" "janela vazia"
nao_tem "MD8 · marca e --fechar: sem janela vazia no md" "$(md)" "janela vazia"
tem "MD8 · marca e --fechar: orquestrador 600 (400 + 200)" "$(md)" "Subagentes: 0 · orquestrador: 600 · total: 600"
tem "MD8 · marca e --fechar: medido" "$SAI" "(medido)"
nao_tem "MD8 · marca e --fechar: não pede --fechar de novo" "$SAI" "rode com --fechar"

# MD9: o formato das linhas 1 e 2 não muda
novo
simples
marcar 6000 2000
roda --tarefa "$P" --sessao "$S1"
comeca "MD9 · --sessao: a linha 1 começa por MEDICAO" "$(printf '%s\n' "$SAI" | sed -n 1p)" "MEDICAO "
comeca "MD9 · --sessao: a linha 2 começa por subagentes ≈" "$(printf '%s\n' "$SAI" | sed -n 2p)" "subagentes ≈ "
tem "MD9 · --sessao: a linha 2 traz orquestrador ≈" "$(printf '%s\n' "$SAI" | sed -n 2p)" " · orquestrador ≈ "
tem "MD9 · --sessao: a linha 2 traz total ≈" "$(printf '%s\n' "$SAI" | sed -n 2p)" " · total ≈ "
roda --tarefa "$P"
comeca "MD9 · marcas: a linha 1 começa por MEDICAO" "$(printf '%s\n' "$SAI" | sed -n 1p)" "MEDICAO "
comeca "MD9 · marcas: a linha 2 começa por subagentes ≈" "$(printf '%s\n' "$SAI" | sed -n 2p)" "subagentes ≈ "
tem "MD9 · marcas: a linha 2 traz orquestrador ≈" "$(printf '%s\n' "$SAI" | sed -n 2p)" " · orquestrador ≈ "
tem "MD9 · marcas: a linha 2 traz total ≈" "$(printf '%s\n' "$SAI" | sed -n 2p)" " · total ≈ "

# MD10: duas sessões, uma com janela vazia: o número é o da que tem janela, e o aviso nomeia a vazia
SA=aaaaaaaa-0001
SB=bbbbbbbb-0002
novo
u "$T/tr/-proj/$SA.jsonl" a1 8000 600 0 0 0
u "$T/tr/-proj/$SA.jsonl" a2 4000 400 0 0 0
u "$T/tr/-proj/$SA.jsonl" a3 500 200 0 0 0
u "$T/tr/-proj/$SB.jsonl" b1 3000 150 0 0 0
u "$T/tr/-proj/$SB.jsonl" b2 500 50 0 0 0
printf '%s %s\n%s %s\n%s %s fechar\n' $((AGORA - 6000)) "$SA" $((AGORA - 2000)) "$SA" $((AGORA - 3000)) "$SB" >"$P/sessoes"
roda --tarefa "$P"
tem "MD10 · duas sessões, uma vazia: a 2ª linha" "$SAI" "orquestrador ≈ 0 mil (janela vazia em 1 de 2 sessões: ver aviso)"
comeca "MD10 · duas sessões, uma vazia: a linha 2 começa por subagentes ≈" "$(printf '%s\n' "$SAI" | sed -n 2p)" "subagentes ≈ "
tem "MD10 · duas sessões, uma vazia: o aviso nomeia a sessão vazia" "$SAI" "sessão ${SB:0:8}: janela vazia, 1 marca(s) no mesmo segundo"
nao_tem "MD10 · duas sessões, uma vazia: o aviso não nomeia a que tem janela" "$SAI" "sessão ${SA:0:8}: janela vazia"
tem "MD10 · duas sessões, uma vazia: o aviso dá o id inteiro para o --sessao" "$SAI" "--sessao $SB conta a sessão inteira"
tem "MD10 · duas sessões, uma vazia: o orquestrador é o da sessão com janela (400)" "$(md)" "Subagentes: 0 · orquestrador: 400 · total: 400"
tem "MD10 · duas sessões, uma vazia: medicao.md diz janela vazia" "$(md)" "janela vazia: 1 marca(s) no mesmo segundo"

mkdir -p "$T/w/tarefas/outra"
printf '%s %s\n' $((AGORA - 4500)) "$SA" >"$T/w/tarefas/outra/sessoes"
roda --tarefa "$P"
tem "MD10 · janela vazia e sessão estimada na mesma medição: os dois rótulos" "$SAI" "(janela vazia em 1 de 2 sessões: ver aviso; estimado em 1 de 2 sessão(ões) dividida(s) com outra tarefa; ver medicao.md)"
tem "MD10 · janela vazia e sessão estimada na mesma medição: a vazia não entra no estimado" "$(md)" "200 (estimado: 50% de 400)"

# MD11: três marcas no mesmo segundo (e uma resposta nesse segundo): janela vazia, nada contado
novo
simples
marcar 4000 4000 4000
roda --tarefa "$P"
tem "MD11 · marcas no mesmo segundo: a 2ª linha diz janela vazia" "$SAI" "orquestrador ≈ 0 mil (janela vazia em 1 de 1 sessão: ver aviso)"
tem "MD11 · marcas no mesmo segundo: o aviso conta 3 marcas" "$SAI" "3 marca(s) no mesmo segundo"
nao_tem "MD11 · marcas no mesmo segundo: não fala de uma marca só" "$SAI" "uma marca só"
tem "MD11 · marcas no mesmo segundo: nada contado, nem a resposta desse segundo" "$(md)" "Subagentes: 0 · orquestrador: 0 · total: 0"
tem "MD11 · marcas no mesmo segundo: medicao.md conta 3 marcas" "$(md)" "janela vazia: 3 marca(s) no mesmo segundo"

# --- defeitos antigos do medir.sh (M-a a M-h) ---------------------------------------------
# snap: o que há em $T/w (pasta de trabalho) e $T/c (cache) e o hash de cada arquivo; igual antes e depois = nada criado
# nem mexido
snap() { { find "$T/w" "$T/c" | sort; find "$T/w" "$T/c" -type f -exec sha256sum {} + 2>/dev/null | sort; }; }
# hash12 <nome>: os 12 primeiros do sha256 do nome da tarefa (o que a chave do orquestrador leva no histórico)
hash12() { printf '%s' "$1" | sha256sum | cut -c1-12; }
# notif <transcript principal> <forma> <id do agente>: aviso de encerramento do agente. Formas: user (mensagem), anexo
# (attachment/queued_command) e fila (queue-operation/enqueue)
notif() {
  local txt
  txt=$(printf '<task-notification>\n<task-id>%s</task-id>\n<tool-use-id>toolu_x</tool-use-id>\n<output-file>/tmp/x/%s.output</output-file>\n<status>completed</status>\n<summary>Agent "teste" completed</summary>\n</task-notification>' "$3" "$3")
  case $2 in
    user) jq -nc --arg t "$txt" '{type: "user", message: {role: "user", content: $t}}' ;;
    anexo) jq -nc --arg t "$txt" '{type: "attachment", attachment: {type: "queued_command", prompt: $t, commandMode: "task-notification"}}' ;;
    fila) jq -nc --arg t "$txt" '{type: "queue-operation", operation: "enqueue", content: $t, sessionId: "x"}' ;;
  esac >>"$1"
}
# tarefa_nova <nome>: pasta de tarefa só com registro.md, ao lado da $P
tarefa_nova() { mkdir -p "$T/w/tarefas/$1" && printf '# Tarefa\n- Nível: N2 — teste\n' >"$T/w/tarefas/$1/registro.md"; }
NX=2026-10-01-x
NX2=2026-10-01-x-2

# M-a: a pasta de trabalho no lugar da tarefa é recusada, mesmo com --fechar, e nada é criado
novo
W=$(cd "$T/w" && pwd -P)
antes=$(snap)
CLAUDE_CODE_SESSION_ID=$S1 roda --tarefa "$T/w" --fechar
eq "M-a · pasta de trabalho com --fechar: código 2" 2 "$RC"
tem "M-a · pasta de trabalho: diz que é pasta de trabalho" "$ERR" "medir.sh: $W é pasta de trabalho (tem tarefas/)"
tem "M-a · pasta de trabalho: aponta a pasta da tarefa" "$ERR" "--tarefa pede a pasta da tarefa, $W/tarefas/<tarefa>"
eq "M-a · pasta de trabalho: nada na saída padrão" "" "$SAI"
eq "M-a · pasta de trabalho: nada criado nem mexido" "$antes" "$(snap)"
eq "M-a · pasta de trabalho: sem sessoes" no "$([ -e "$T/w/sessoes" ] && echo sim || echo no)"
eq "M-a · pasta de trabalho: sem medicao.md" no "$([ -e "$T/w/medicao.md" ] && echo sim || echo no)"
eq "M-a · pasta de trabalho: sem histórico" no "$([ -e "$H" ] && echo sim || echo no)"
roda --tarefa "$T/w" --sessao "$S1"
eq "M-a · pasta de trabalho sem --fechar, com --sessao: código 2" 2 "$RC"
eq "M-a · pasta de trabalho sem --fechar: nada criado nem mexido" "$antes" "$(snap)"
novo
base
antes=$(snap)
roda --tarefa "$T/w" --sessao "$S1"
eq "M-a · pasta de trabalho com transcript da sessão: código 2" 2 "$RC"
eq "M-a · pasta de trabalho com transcript da sessão: sem histórico" no "$([ -e "$H" ] && echo sim || echo no)"
eq "M-a · pasta de trabalho com transcript da sessão: sem medicao.md" no "$([ -e "$T/w/medicao.md" ] && echo sim || echo no)"

# M-b: a pasta tarefas/ no lugar da tarefa é recusada, e nada é criado
novo
antes=$(snap)
CLAUDE_CODE_SESSION_ID=$S1 roda --tarefa "$T/w/tarefas" --fechar
eq "M-b · pasta tarefas/ com --fechar: código 2" 2 "$RC"
tem "M-b · pasta tarefas/: diz que é a pasta tarefas/" "$ERR" "medir.sh: $W/tarefas é a pasta tarefas/; --tarefa pede uma tarefa dentro dela, $W/tarefas/<tarefa>"
eq "M-b · pasta tarefas/: nada na saída padrão" "" "$SAI"
eq "M-b · pasta tarefas/: nada criado nem mexido" "$antes" "$(snap)"
eq "M-b · pasta tarefas/: sem sessoes" no "$([ -e "$T/w/tarefas/sessoes" ] && echo sim || echo no)"
roda --tarefa "$T/w/tarefas"
eq "M-b · pasta tarefas/ sem --fechar: código 2" 2 "$RC"
eq "M-b · pasta tarefas/ sem --fechar: nada criado nem mexido" "$antes" "$(snap)"
rm -rf "$T/w/tarefas/$NOME"
mkdir -p "$T/w/tarefas/so-progresso"
printf '# Progresso\n' >"$T/w/tarefas/so-progresso/progresso.md"
roda --tarefa "$T/w/tarefas"
eq "M-b · pasta tarefas/ cuja subpasta só tem progresso.md: código 2" 2 "$RC"

# M-c: tarefa velha, só com registro.md, mede como sempre; pasta chamada tarefas sem subpasta de tarefa também é tarefa
novo
base
eq "M-c · a tarefa velha só tem o registro.md" "registro.md" "$(ls "$P")"
roda --tarefa "$P" --sessao "$S1"
eq "M-c · tarefa velha: código 0" 0 "$RC"
tem "M-c · tarefa velha: mede os 2 agentes" "$SAI" "2 agente(s) da tarefa"
tem "M-c · tarefa velha: grava o medicao.md" "$(md)" "Subagentes: 1.900"
eq "M-c · tarefa velha: grava o histórico" 3 "$(wc -l <"$H" | tr -d ' ')"
novo
mkdir -p "$T/x/tarefas"
roda --tarefa "$T/x/tarefas"
eq "M-c · pasta chamada tarefas sem subpasta de tarefa: código 0" 0 "$RC"
tem "M-c · pasta chamada tarefas sem subpasta de tarefa: mede (sem sessão)" "$SAI" "sem-sessao"

# M-d: duas tarefas na mesma sessão, uma com o nome começando pelo da outra: o agente que cita a x-2 não é da x
novo
tarefa_nova "$NX"
tarefa_nova "$NX2"
M=$T/tr/-proj/$S1.jsonl
D=$T/tr/-proj/$S1/subagents
u "$M" o1 3000 100 0 0 0
msg "$D/agent-d1.jsonl" "PAPEL: construtor. Leia .claude/seiva/tarefas/$NX2/plano.md"
u "$D/agent-d1.jsonl" d1x 2000 500 0 0 0
velho "$D"/agent-*.jsonl
roda --tarefa "$T/w/tarefas/$NX" --sessao "$S1"
tem "M-d · x: o agente que cita a x-2 não conta" "$SAI" "0 agente(s) da tarefa"
tem "M-d · x: o agente da x-2 sai como de outra tarefa" "$SAI" "1 subagente(s) das mesmas sessões cujo pacote não cita a pasta"
nao_tem "M-d · x: o agente não está no medicao.md" "$(cat "$T/w/tarefas/$NX/medicao.md")" "| construtor |"
roda --tarefa "$T/w/tarefas/$NX2" --sessao "$S1"
tem "M-d · x-2: conta o agente" "$SAI" "1 agente(s) da tarefa"
tem "M-d · x-2: o agente está no medicao.md com 500" "$(cat "$T/w/tarefas/$NX2/medicao.md")" "| 500 |"
# o nome com letra ou sublinhado colado dos dois lados não é o nome inteiro
novo
tarefa_nova "$NX"
M=$T/tr/-proj/$S1.jsonl
D=$T/tr/-proj/$S1/subagents
u "$M" o1 3000 100 0 0 0
msg "$D/agent-d2.jsonl" "PAPEL: construtor. Leia pre$NX/plano.md"
u "$D/agent-d2.jsonl" d2x 2000 500 0 0 0
msg "$D/agent-d3.jsonl" "PAPEL: construtor. Leia ${NX}_v2/plano.md"
u "$D/agent-d3.jsonl" d3x 2000 500 0 0 0
velho "$D"/agent-*.jsonl
roda --tarefa "$T/w/tarefas/$NX" --sessao "$S1"
tem "M-d · nome colado em letra à esquerda ou sublinhado à direita não conta" "$SAI" "0 agente(s) da tarefa"

# M-e: o nome inteiro conta com ponto, aspas, parênteses, crase, barra, vírgula, início e fim do texto
novo
tarefa_nova "$NX"
M=$T/tr/-proj/$S1.jsonl
D=$T/tr/-proj/$S1/subagents
u "$M" o1 3000 100 0 0 0
i=0
for frase in "Leia a tarefa $NX." "Leia \"$NX\" agora" "$NX é a tarefa" "A tarefa é $NX" "Leia tarefas/$NX/plano.md" "Leia ($NX), por favor" "Leia \`$NX\`" "Leia $NX, depois pare"; do
  i=$((i + 1))
  msg "$D/agent-e$i.jsonl" "$frase"
  u "$D/agent-e$i.jsonl" "e${i}x" 2000 100 0 0 0
done
velho "$D"/agent-*.jsonl
roda --tarefa "$T/w/tarefas/$NX" --sessao "$S1"
tem "M-e · o nome inteiro conta nas $i formas de citar" "$SAI" "$i agente(s) da tarefa"

# M-f: duas tarefas na mesma sessão, --fechar em cada: uma linha de orquestrador por tarefa, sem o nome
novo
simples
FA=2026-10-01-fa
FB=2026-10-01-fb
tarefa_nova "$FA"
tarefa_nova "$FB"
printf '%s %s\n' $((AGORA - 6000)) "$S1" >"$T/w/tarefas/$FA/sessoes"
printf '%s %s\n' $((AGORA - 3000)) "$S1" >"$T/w/tarefas/$FB/sessoes"
CLAUDE_CODE_SESSION_ID=$S1 roda --tarefa "$T/w/tarefas/$FA" --fechar
CLAUDE_CODE_SESSION_ID=$S1 roda --tarefa "$T/w/tarefas/$FB" --fechar
eq "M-f · duas linhas de orquestrador no histórico" 2 "$(jq -r 'select(.papel == "orquestrador") | .agente' "$H" | wc -l | tr -d ' ')"
eq "M-f · cada chave leva a sessão e o hash do nome da tarefa" "$(printf 'orq-%s:%s\norq-%s:%s\n' "$S1" "$(hash12 "$FA")" "$S1" "$(hash12 "$FB")" | sort)" \
  "$(jq -r 'select(.papel == "orquestrador") | .agente' "$H" | sort)"
nao_tem "M-f · nenhuma linha leva o nome da tarefa" "$(cat "$H")" "$FA"
nao_tem "M-f · nenhuma linha leva o nome da outra tarefa" "$(cat "$H")" "$FB"
CLAUDE_CODE_SESSION_ID=$S1 roda --tarefa "$T/w/tarefas/$FA" --fechar
eq "M-f · medir de novo a mesma tarefa não duplica" 2 "$(jq -r 'select(.papel == "orquestrador") | .agente' "$H" | wc -l | tr -d ' ')"

# M-g: agente mexido agora, com o aviso de encerramento como mensagem (type: user): entra no histórico, sem "(rodando)"
novo
base
touch "$T/tr/-proj/$S1/subagents/agent-a2.jsonl"
notif "$M" user a2
roda --tarefa "$P" --sessao "$S1"
nao_tem "M-g · aviso como mensagem: não diz agente rodando" "$SAI" "agente(s) rodando"
nao_tem "M-g · aviso como mensagem: sem (rodando) no md" "$(md)" "(rodando)"
tem "M-g · aviso como mensagem: o ponderado da lente está no md" "$(md)" "| 300 |"
eq "M-g · aviso como mensagem: o agente entra no histórico" a2 "$(jq -r 'select(.agente == "a2") | .agente' "$H")"

# M-g2: o mesmo aviso como attachment/queued_command e como queue-operation
for forma in anexo fila; do
  novo
  base
  touch "$T/tr/-proj/$S1/subagents/agent-a2.jsonl"
  notif "$M" "$forma" a2
  roda --tarefa "$P" --sessao "$S1"
  nao_tem "M-g2 · aviso em $forma: não diz agente rodando" "$SAI" "agente(s) rodando"
  nao_tem "M-g2 · aviso em $forma: sem (rodando) no md" "$(md)" "(rodando)"
  eq "M-g2 · aviso em $forma: o agente entra no histórico" a2 "$(jq -r 'select(.agente == "a2") | .agente' "$H")"
done

# M-h: agente mexido agora, sem aviso do id dele: continua rodando e fora do histórico. Aviso de outro id, id que só
# contém o dele e menção em resultado de ferramenta não valem
novo
base
touch "$T/tr/-proj/$S1/subagents/agent-a2.jsonl"
roda --tarefa "$P" --sessao "$S1"
tem "M-h · sem aviso: diz agente rodando" "$SAI" "1 agente(s) rodando"
tem "M-h · sem aviso: (rodando) no md" "$(md)" "300 (rodando)"
eq "M-h · sem aviso: fora do histórico" "" "$(jq -r 'select(.agente == "a2") | .agente' "$H")"
notif "$M" user a1
notif "$M" anexo a20
notif "$M" fila xa2
jq -nc '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "z", content: "<task-notification>\n<task-id>a2</task-id>\n<status>completed</status>"}]}}' >>"$M"
roda --tarefa "$P" --sessao "$S1"
tem "M-h · aviso de outro id, id parecido ou citação em resultado de ferramenta: continua rodando" "$SAI" "1 agente(s) rodando"
tem "M-h · idem: (rodando) no md" "$(md)" "300 (rodando)"
eq "M-h · idem: fora do histórico" "" "$(jq -r 'select(.agente == "a2") | .agente' "$H")"

# --- o histórico de verdade não mudou ---------------------------------------------------
eq "custos.jsonl de verdade não mudou (hash)" "$custos_real" "$(sha256sum "$cache_real/custos.jsonl" 2>/dev/null | cut -c1-64)"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
