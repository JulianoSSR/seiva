#!/usr/bin/env bash
# Testa scripts/statusline-orcamento.sh (grava o orçamento) e scripts/orcamento.sh (lê o orçamento).
# Tudo roda com HOME, XDG_CACHE_HOME e TZ temporários: o ~/.cache/seiva de verdade não pode mudar (o último caso confere).
# Só valores falsos óbvios (ids de sessão de teste, caminhos em pasta temporária).
# Uso: bash testes/scripts/teste-orcamento.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
STL="$RAIZ/scripts/statusline-orcamento.sh"
LEI="$RAIZ/scripts/orcamento.sh"

# O ~/.cache/seiva de verdade, anotado antes de trocar o HOME (hoje ela não existe).
cache_real="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/seiva"
antes_real=$(stat -c %Y "$cache_real" 2>/dev/null || echo ausente)
# O ~/.claude de verdade também: só o hash do settings.json (nunca o conteúdo) e se a cópia da statusline existe.
claude_real="${HOME:-/nonexistent}/.claude"
settings_antes=$(sha256sum "$claude_real/settings.json" 2>/dev/null | cut -c1-64)
copia_antes=$([ -e "$claude_real/statusline-seiva.sh" ] && echo presente || echo ausente)

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CACHE_HOME="$T/cache" TZ=UTC
mkdir -p "$HOME" "$T/vazio"
CACHE="$XDG_CACHE_HOME/seiva"
ARQ="$CACHE/orcamento.json"

# Janelas fixas no futuro (ano 2100), para a hora sair igual em qualquer dia: R1 = 14:30 UTC, R2 = 19:30 UTC.
R1=4102497000
R2=$((R1 + 18000))
R7=4102800000
PASSADO=1000000000

n=0
erros=0
eq() { # eq <descrição> <esperado> <obtido>
  n=$((n + 1))
  if [ "$2" != "$3" ]; then
    erros=$((erros + 1))
    echo "FALHA: $1"
    printf '  | esperado: %s\n  | obtido:   %s\n' "$2" "$3"
  fi
}
tem() { # tem <descrição> <texto> <trecho que precisa aparecer>
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
nao_tem() { # nao_tem <descrição> <texto> <trecho que não pode aparecer>
  n=$((n + 1))
  case $2 in
    *"$3"*)
      erros=$((erros + 1))
      echo "FALHA: $1"
      printf '  | trecho proibido: %s\n  | texto: %s\n' "$3" "$2"
      ;;
  esac
}

limpa() { rm -rf "$CACHE"; }

# entrada <id> <usado 5h> <reinicia 5h> <usado 7d> <reinicia 7d> <contexto>: o JSON que o Claude Code manda à statusline
entrada() {
  jq -nc --arg id "$1" --argjson u5 "$2" --argjson r5 "$3" --argjson u7 "$4" --argjson r7 "$5" --argjson c "$6" \
    '{session_id:$id, rate_limits:{five_hour:{used_percentage:$u5,resets_at:$r5}, seven_day:{used_percentage:$u7,resets_at:$r7}}, context_window:{used_percentage:$c}}'
}

# stl <json>: roda a statusline com o JSON no stdin; deixa SAI, RC e ERR
stl() {
  SAI=$(printf '%s' "$1" | bash "$STL" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}

# velhice: marca o visto_em das duas janelas como muito antigo, para ver quem o junta preserva
velhice() {
  jq '.cinco_horas.visto_em = 1000 | .sete_dias.visto_em = 1000' "$ARQ" > "$ARQ.x" && mv "$ARQ.x" "$ARQ"
}

campo() { jq -r "$1" "$ARQ"; }

# --- statusline: caso normal --------------------------------------------------
limpa
inicio=$(date +%s)
stl "$(entrada s-teste-0001 42 "$R1" 18 "$R7" 35)"
eq "statusline normal: linha" "5h 42% até 14:30 · 7d 18% · ctx 35%" "$SAI"
eq "statusline normal: sai com 0" 0 "$RC"
eq "statusline normal: nada no stderr" "" "$ERR"
eq "statusline normal: modo 600" 600 "$(stat -c %a "$ARQ")"
eq "statusline normal: harness" claude-code "$(campo .harness)"
eq "statusline normal: script é o próprio script" "$STL" "$(campo .script)"
eq "statusline normal: versao" 1 "$(campo .versao)"
eq "statusline normal: sessao" s-teste-0001 "$(campo .sessao)"
eq "statusline normal: cinco_horas" "42 $R1" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.reinicia)"')"
eq "statusline normal: sete_dias" "18 $R7" "$(campo '"\(.sete_dias.usado) \(.sete_dias.reinicia)"')"
eq "statusline normal: contexto" "35 s-teste-0001" "$(campo '"\(.contexto.usado) \(.contexto.sessao)"')"
eq "statusline normal: visto_em e gravado_em são de agora" 1 "$(campo "[.cinco_horas.visto_em, .gravado_em] | all(. >= $inicio) | if . then 1 else 0 end")"
eq "statusline normal: nenhum temporário sobra na pasta" 1 "$(ls -A "$CACHE" | wc -l | tr -d ' ')"

# --- statusline: junção por janela --------------------------------------------
# sessão sem rate_limits (ausente e null): a janela gravada fica, o contexto vem da entrada
limpa
stl "$(entrada s-teste-0001 60 "$R1" 20 "$R7" 35)"
velhice
stl '{"session_id":"s-teste-0002","context_window":{"used_percentage":10}}'
eq "sem rate_limits: linha usa o gravado" "5h 60% até 14:30 · 7d 20% · ctx 10%" "$SAI"
eq "sem rate_limits: 5h e reinicia ficam" "60 $R1 1000" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.reinicia) \(.cinco_horas.visto_em)"')"
eq "sem rate_limits: contexto e sessão vêm da entrada" "10 s-teste-0002 s-teste-0002" "$(campo '"\(.contexto.usado) \(.contexto.sessao) \(.sessao)"')"
stl '{"session_id":"s-teste-0003","rate_limits":null,"context_window":{"used_percentage":11}}'
eq "rate_limits null: janela continua" "60 $R1 1000" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.reinicia) \(.cinco_horas.visto_em)"')"
stl '{"session_id":"s-teste-0004","rate_limits":{"five_hour":null,"seven_day":{"used_percentage":25,"resets_at":'"$R7"'}},"context_window":{"used_percentage":12}}'
eq "só uma janela com dado: a outra fica" "60 1000 25" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.visto_em) \(.sete_dias.usado)"')"

# sessão atrasada na mesma janela: o maior uso fica
limpa
stl "$(entrada s-teste-0001 60 "$R1" 20 "$R7" 35)"
velhice
stl "$(entrada s-teste-0002 55 "$R1" 20 "$R7" 35)"
eq "atrasada na mesma janela: fica 60, com o visto_em de antes" "60 1000" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.visto_em)"')"
stl "$(entrada s-teste-0002 61 "$R1" 20 "$R7" 35)"
eq "mesma janela com uso maior: vale o novo e o visto_em é de agora" "61 1" "$(campo '"\(.cinco_horas.usado) \(if .cinco_horas.visto_em > 1000 then 1 else 0 end)"')"

# janela nova: o uso cai e o reinicia sobe
limpa
stl "$(entrada s-teste-0001 90 "$R1" 20 "$R7" 35)"
stl "$(entrada s-teste-0001 5 "$R2" 20 "$R7" 35)"
eq "janela nova: fica 5, com o reinicia novo" "5 $R2" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.reinicia)"')"
eq "janela nova: linha" "5h 5% até 19:30 · 7d 20% · ctx 35%" "$SAI"

# sessão da janela anterior: o reinicia menor perde, mesmo com uso maior
limpa
stl "$(entrada s-teste-0001 40 "$R2" 20 "$R7" 35)"
stl "$(entrada s-teste-0002 80 "$R1" 20 "$R7" 35)"
eq "sessão de janela anterior: fica 40 com o reinicia maior" "40 $R2" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.reinicia)"')"

# arquivo anterior inválido ou de outra versão conta como ausente
limpa
mkdir -p "$CACHE"
printf '{x' > "$ARQ"
stl "$(entrada s-teste-0001 30 "$R1" 10 "$R7" 5)"
eq "arquivo anterior inválido: vale a entrada" "30 $R1" "$(campo '"\(.cinco_horas.usado) \(.cinco_horas.reinicia)"')"
printf '{"versao":2,"cinco_horas":{"usado":99,"reinicia":%s,"visto_em":1000}}' "$((R1 + 100))" > "$ARQ"
stl "$(entrada s-teste-0001 30 "$R1" 10 "$R7" 5)"
eq "arquivo anterior de outra versão: vale a entrada" "1 30" "$(campo '"\(.versao) \(.cinco_horas.usado)"')"

# --- statusline: entrada inválida e sem jq ------------------------------------
limpa
stl "$(entrada s-teste-0001 40 "$R1" 20 "$R7" 35)"
antes=$(sha256sum "$ARQ" | cut -c1-64)
stl '{x'
eq "entrada inválida: linha de reserva" "seiva: orçamento sem dado" "$SAI"
eq "entrada inválida: sai com 0 e sem stderr" "0|" "$RC|$ERR"
eq "entrada inválida: arquivo intacto" "$antes" "$(sha256sum "$ARQ" | cut -c1-64)"
stl ''
eq "entrada vazia: linha de reserva" "seiva: orçamento sem dado" "$SAI"
eq "entrada vazia: arquivo intacto" "$antes" "$(sha256sum "$ARQ" | cut -c1-64)"
stl '[1,2]'
eq "entrada que não é objeto: linha de reserva" "seiva: orçamento sem dado" "$SAI"
eq "entrada que não é objeto: arquivo intacto" "$antes" "$(sha256sum "$ARQ" | cut -c1-64)"
SAI=$(entrada s-teste-0001 40 "$R1" 20 "$R7" 35 | PATH="$T/vazio" "$BASH" "$STL" 2>"$T/err")
RC=$?
eq "sem jq: linha de reserva, sai com 0, sem stderr" "seiva: sem jq|0|" "$SAI|$RC|$(cat "$T/err")"
eq "sem jq: arquivo intacto" "$antes" "$(sha256sum "$ARQ" | cut -c1-64)"
limpa
stl '{x'
eq "entrada inválida sem arquivo: não cria o arquivo" "ausente" "$([ -e "$ARQ" ] && echo presente || echo ausente)"

# --- statusline: 70% ou mais --------------------------------------------------
limpa
stl "$(entrada s-teste-0001 69.9 "$R1" 18 "$R7" 35)"
eq "69.9%: sem dica" "5h 69.9% até 14:30 · 7d 18% · ctx 35%" "$SAI"
stl "$(entrada s-teste-0001 72 "$R1" 18 "$R7" 35)"
eq "72% sem arquivo retomar" "5h 72% até 14:30 · 7d 18% · ctx 35% · estourou? sessão nova + retome pelo registro.md" "$SAI"
printf '%s\n' "/algum/lugar/2026-09-29-minha-tarefa/registro.md" > "$CACHE/retomar"
stl "$(entrada s-teste-0001 72 "$R1" 18 "$R7" 35)"
eq "72% com arquivo retomar" "5h 72% até 14:30 · 7d 18% · ctx 35% · estourou? sessão nova + retome 2026-09-29-minha-tarefa" "$SAI"
stl "$(entrada s-teste-0001 70 "$R1" 18 "$R7" 35)"
tem "70% já mostra a dica" "$SAI" "estourou? sessão nova + retome 2026-09-29-minha-tarefa"
touch -d "@$(( $(date +%s) - 25200 ))" "$CACHE/retomar"
stl "$(entrada s-teste-0001 72 "$R1" 18 "$R7" 35)"
eq "retomar com mais de 6 h: a tarefa velha não aparece" "5h 72% até 14:30 · 7d 18% · ctx 35% · estourou? sessão nova + retome pelo registro.md" "$SAI"
printf '%s\n' '/x/a b;$(rm -rf y)/registro.md' > "$CACHE/retomar"
stl "$(entrada s-teste-0001 72 "$R1" 18 "$R7" 35)"
eq "nome da tarefa hostil: só [A-Za-z0-9._-] passa" "5h 72% até 14:30 · 7d 18% · ctx 35% · estourou? sessão nova + retome abrm-rfy" "$SAI"
printf '%s\n' "/x/$(printf 'n%.0s' $(seq 1 60))/registro.md" > "$CACHE/retomar"
stl "$(entrada s-teste-0001 72 "$R1" 18 "$R7" 35)"
eq "nome da tarefa passa de 40: corta em 40" "$(printf 'n%.0s' $(seq 1 40))" "${SAI##* retome }"
: > "$CACHE/retomar"
stl "$(entrada s-teste-0001 72 "$R1" 18 "$R7" 35)"
tem "arquivo retomar vazio: cai no texto genérico" "$SAI" "retome pelo registro.md"
limpa
stl "$(entrada s-teste-0001 10 "$R1" 18 "$R7" 35)"
nao_tem "abaixo de 70%: sem dica" "$SAI" "estourou"

# janela de 5h já reiniciada no gravado: sem percentual velho na barra
limpa
stl "$(entrada s-teste-0001 80 "$PASSADO" 18 "$R7" 35)"
eq "janela de 5h já reiniciada: traço, sem dica" "5h -- · 7d 18% · ctx 35%" "$SAI"

# --- statusline: rodando da cópia e com prazo ---------------------------------
limpa
mkdir -p "$T/x"
install -m 0755 "$STL" "$T/x/statusline-orcamento.sh"
SAI=$(entrada s-teste-0001 42 "$R1" 18 "$R7" 35 | timeout 1 bash "$T/x/statusline-orcamento.sh" 2>"$T/err")
RC=$?
eq "da cópia e com timeout 1: mesma linha e sai com 0" "5h 42% até 14:30 · 7d 18% · ctx 35%|0|" "$SAI|$RC|$(cat "$T/err")"
eq "da cópia: script aponta para a cópia" "$T/x/statusline-orcamento.sh" "$(campo .script)"

# --- leitor: fixtures feitas à mão --------------------------------------------
# grava_orc <usado 5h> <reinicia 5h> <visto_em> [script]: escreve $ARQ como a statusline escreveria
grava_orc() {
  mkdir -p "$CACHE"
  jq -n --argjson u "$1" --argjson r "$2" --argjson v "$3" --arg s "${4:-$STL}" --argjson r7 "$R7" \
    '{versao:1,harness:"claude-code",script:$s,gravado_em:$v,sessao:"sessao-de-teste-0001",
      cinco_horas:{usado:$u,reinicia:$r,visto_em:$v},sete_dias:{usado:18,reinicia:$r7,visto_em:$v},
      contexto:{usado:35,sessao:"sessao-de-teste-0001"}}' > "$ARQ"
}
# lei [args...]: roda o leitor; deixa SAI, RC e ERR
lei() {
  SAI=$(bash "$LEI" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}
estado() { printf '%s' "$SAI" | sed -E 's/^ORCAMENTO ([^ ]+) .*/\1/'; }

agora=$(date +%s)

# nos limites
limpa
grava_orc 69.9 "$R1" "$agora"
lei
eq "69.9: ok e código 0" "ok 0" "$(estado) $RC"
grava_orc 70.0 "$R1" "$agora"
lei
eq "70.0: restrito e código 10" "restrito 10" "$(estado) $RC"
grava_orc 85.0 "$R1" "$agora"
lei
eq "85.0: parar e código 20" "parar 20" "$(estado) $RC"

# uso comum, com a linha inteira
grava_orc 42 "$R1" "$agora"
lei
eq "42: linha inteira" "ORCAMENTO ok — 5h 42% até 14:30 · 7d 18% · ctx 35% (sessão sessao-d) · dado de 0 min" "$SAI"
eq "42: nada no stderr" "" "$ERR"
grava_orc 72 "$R1" "$agora"
lei
eq "72: restrito e 10" "restrito 10" "$(estado) $RC"
grava_orc 88 "$R1" "$agora"
lei
eq "88: parar e 20" "parar 20" "$(estado) $RC"

# sem dado: arquivo ausente, JSON inválido, versao 2, usado nulo, sem jq
limpa
lei
eq "sem arquivo: desligado e 0" "desligado 0" "$(estado) $RC"
mkdir -p "$CACHE"
printf '{x' > "$ARQ"
lei
eq "JSON inválido: desligado e 0" "desligado 0" "$(estado) $RC"
printf '{"versao":2,"cinco_horas":{"usado":50,"reinicia":%s,"visto_em":%s}}' "$R1" "$agora" > "$ARQ"
lei
eq "versao 2: desligado e 0" "desligado 0" "$(estado) $RC"
jq -n --argjson r "$R1" --arg s "$STL" '{versao:1,harness:"claude-code",script:$s,gravado_em:1,sessao:"x",cinco_horas:{usado:null,reinicia:null,visto_em:null},sete_dias:{usado:null,reinicia:null,visto_em:null},contexto:{usado:null,sessao:"x"}}' > "$ARQ"
lei
eq "usado nulo: desligado e 0" "desligado 0" "$(estado) $RC"
printf '[1,2]' > "$ARQ"
lei
eq "JSON que não é objeto: desligado e 0" "desligado 0" "$(estado) $RC"
grava_orc 72 "$R1" "$agora"
SAI=$(PATH="$T/vazio" "$BASH" "$LEI" 2>"$T/err")
RC=$?
eq "sem jq: desligado, 0 e sem stderr" "desligado 0 " "$(estado) $RC $(cat "$T/err")"

# janela reiniciada: o percentual velho não vale
grava_orc 90 "$PASSADO" "$((PASSADO - 60))"
lei
eq "reinicia no passado: sem-dado e 0" "sem-dado 0" "$(estado) $RC"
nao_tem "sem-dado não repete o percentual velho como ordem" "$SAI" "parar"

# dado velho da mesma janela vale como piso
grava_orc 72 "$R1" "$((agora - 7200))"
lei
eq "72 visto há 2 h: restrito e 10" "restrito 10" "$(estado) $RC"
tem "72 visto há 2 h: a idade aparece" "$SAI" "dado de 120 min"

# statusline desatualizada e não conferida
cp "$STL" "$T/x/statusline-orcamento.sh"
grava_orc 42 "$R1" "$agora" "$T/x/statusline-orcamento.sh"
lei
nao_tem "cópia igual à do repositório: sem aviso de desatualizada" "$SAI" "desatualizada"
nao_tem "cópia igual à do repositório: sem aviso de não conferida" "$SAI" "não conferida"
printf '\n# alterada no teste\n' >> "$T/x/statusline-orcamento.sh"
lei
tem "cópia diferente: aviso de desatualizada" "$SAI" "statusline desatualizada: rode a linha de atualização do harness.md"
eq "cópia diferente: o estado continua o do percentual" "ok 0" "$(estado) $RC"
grava_orc 42 "$R1" "$agora" "$T/nao-existe/statusline-orcamento.sh"
lei
tem "script ilegível: versão não conferida" "$SAI" "versão da statusline não conferida"

# --- leitor: --tarefa ----------------------------------------------------------
limpa
grava_orc 42 "$R1" "$agora"
mkdir -p "$T/tarefas/t-um"
printf '# registro\n' > "$T/tarefas/t-um/registro.md"
lei --tarefa "$T/tarefas/t-um"
eq "--tarefa com pasta e registro: grava o caminho absoluto" "$(cd "$T/tarefas/t-um" && pwd -P)/registro.md" "$(cat "$CACHE/retomar" 2>/dev/null)"
eq "--tarefa: retomar em modo 600" 600 "$(stat -c %a "$CACHE/retomar" 2>/dev/null)"
eq "--tarefa: o estado não muda" "ok 0" "$(estado) $RC"
rm -f "$CACHE/retomar"
SAI=$(cd "$T" && bash "$LEI" --tarefa tarefas/t-um "$ARQ" 2>"$T/err")
eq "--tarefa relativa e arquivo explícito: grava o caminho absoluto" "$(cd "$T/tarefas/t-um" && pwd -P)/registro.md" "$(cat "$CACHE/retomar" 2>/dev/null)"
rm -f "$CACHE/retomar"
mkdir -p "$T/tarefas/t-dois"
lei --tarefa "$T/tarefas/t-dois"
eq "--tarefa sem registro.md: não grava" "ausente" "$([ -e "$CACHE/retomar" ] && echo presente || echo ausente)"
tem "--tarefa sem registro.md: diz por quê" "$SAI" "retomar não gravado"
lei --tarefa "$T/tarefas/nao-existe"
eq "--tarefa com pasta inexistente: não grava" "ausente" "$([ -e "$CACHE/retomar" ] && echo presente || echo ausente)"
tem "--tarefa com pasta inexistente: diz por quê" "$SAI" "retomar não gravado"
SAI=$(bash "$LEI" --tarefa "$T/tarefas/t-um" "$T/sem-pasta-do-orcamento/orcamento.json" 2>"$T/err")
eq "--tarefa sem a pasta do orçamento: não cria a pasta" "ausente" "$([ -e "$T/sem-pasta-do-orcamento" ] && echo presente || echo ausente)"
tem "--tarefa sem a pasta do orçamento: diz por quê" "$SAI" "retomar não gravado"

# --- leitor: uso errado ---------------------------------------------------------
lei --tarefa
eq "--tarefa sem valor: sai com 2" 2 "$RC"
lei --nao-existe
eq "opção desconhecida: sai com 2" 2 "$RC"
lei "$ARQ" "$ARQ"
eq "dois arquivos: sai com 2" 2 "$RC"

# --- blocos do harness.md: instalação, atualização e volta da statusline ---------
# Os blocos saem do próprio harness.md (o texto que o usuário vai rodar) e rodam com HOME temporário.
bloco() { # bloco <trecho>: imprime o bloco de código da seção "Orçamento vivo" do harness.md que contém o trecho
  awk -v pat="$1" '
    /^## / { em = ($0 ~ /^## Orçamento vivo/) }
    em && /^```/ {
      if (dentro) { if (index(corpo, pat)) { printf "%s", corpo; exit } dentro = 0; corpo = "" }
      else { dentro = 1; corpo = "" }
      next
    }
    em && dentro { corpo = corpo $0 "\n" }
  ' "$RAIZ/referencias/harness.md"
}
BL_A=$(bloco 'statusLine = {')
BL_UP=$(bloco "install -m 0755 '<caminho absoluto da skill carregada>")
BL_VOLTA=$(bloco 'del(.statusLine)')
eq "os três blocos estão no harness.md" "1 1 1" "$([ -n "$BL_A" ] && echo 1 || echo 0) $([ -n "$BL_UP" ] && echo 1 || echo 0) $([ -n "$BL_VOLTA" ] && echo 1 || echo 0)"

prepara() { # prepara <nome> <bloco> <skill>: grava $T/<nome>.sh com o caminho da skill preenchido
  printf '%s\n' "$2" | sed -e "s|^  SKILL='<.*>' &&\$|  SKILL='$3' \&\&|" -e "s|<caminho absoluto da skill carregada>|$3|" > "$T/$1.sh"
}
roda_bloco() { SAI=$(bash "$T/$1.sh" 2>&1); RC=$?; }
CL="$HOME/.claude"
zera_home() { rm -rf "$CL" "$CACHE"; mkdir -p "$CL"; }
ha() { [ -e "$1" ] && echo presente || echo ausente; }

# bloco (a) com settings que tem hooks; o settings começa em modo 644
zera_home
printf '{"hooks":{},"theme":"dark"}\n' > "$CL/settings.json"
chmod 644 "$CL/settings.json"
prepara bl-a "$BL_A" "$RAIZ"
roda_bloco bl-a
tem "bloco (a): diz OK às <epoch>" "$SAI" "OK às "
eq "bloco (a): statusLine.command" "bash ~/.claude/statusline-seiva.sh" "$(jq -r .statusLine.command "$CL/settings.json")"
eq "bloco (a): o resto do settings fica igual" '{"hooks":{},"theme":"dark"}' "$(jq -c 'del(.statusLine)' "$CL/settings.json")"
eq "bloco (a): settings passa a modo 600" 600 "$(stat -c %a "$CL/settings.json")"
eq "bloco (a): um .bak criado" 1 "$(ls "$CL" | grep -c '^settings\.json\.bak-')"
eq "bloco (a): o .bak é o settings de antes" '{"hooks":{},"theme":"dark"}' "$(cat "$CL"/settings.json.bak-* | jq -c .)"
eq "bloco (a): cópia em modo 755" 755 "$(stat -c %a "$CL/statusline-seiva.sh")"
eq "bloco (a): cópia igual à do repositório" 0 "$(cmp -s "$CL/statusline-seiva.sh" "$STL"; echo $?)"
eq "bloco (a): nenhum .novo sobra" 0 "$(ls "$CL" | grep -c '\.novo$')"

# a statusline instalada roda pelo comando do settings, como o Claude Code a chama, e o leitor a reconhece
SAI=$(entrada s-teste-0001 42 "$R1" 18 "$R7" 35 | bash -c "$(jq -r .statusLine.command "$CL/settings.json")" 2>/dev/null)
eq "instalada: a linha sai pelo comando do settings" "5h 42% até 14:30 · 7d 18% · ctx 35%" "$SAI"
eq "instalada: o script gravado é o caminho absoluto da cópia" "$CL/statusline-seiva.sh" "$(campo .script)"
lei
eq "instalada: o leitor não acusa aviso nenhum" "ORCAMENTO ok — 5h 42% até 14:30 · 7d 18% · ctx 35% (sessão s-teste-) · dado de 0 min" "$SAI"

# atualização: a cópia mudou, o leitor avisa, a linha de atualização resolve
printf '\n# alterada no teste\n' >> "$CL/statusline-seiva.sh"
lei
tem "cópia alterada: o leitor avisa" "$SAI" "statusline desatualizada"
prepara bl-up "$BL_UP" "$RAIZ"
roda_bloco bl-up
eq "linha de atualização: a cópia volta a ser igual" 0 "$(cmp -s "$CL/statusline-seiva.sh" "$STL"; echo $?)"
lei
nao_tem "depois da atualização: sem aviso" "$SAI" "desatualizada"

# volta-a: tira a statusLine e só depois apaga a cópia e o cache
antes_v=$(jq -S 'del(.statusLine)' "$CL/settings.json")
prepara bl-volta "$BL_VOLTA" "$RAIZ"
roda_bloco bl-volta
tem "volta-a: diz OK" "$SAI" "OK: statusline removida"
eq "volta-a: statusLine sai do settings" false "$(jq 'has("statusLine")' "$CL/settings.json")"
eq "volta-a: o resto do settings fica igual" "$antes_v" "$(jq -S . "$CL/settings.json")"
eq "volta-a: settings continua em modo 600" 600 "$(stat -c %a "$CL/settings.json")"
eq "volta-a: cópia apagada" ausente "$(ha "$CL/statusline-seiva.sh")"
eq "volta-a: cache apagado, pasta incluída" ausente "$(ha "$CACHE")"
eq "volta-a: o .bak fica" 1 "$(ls "$CL" | grep -c '^settings\.json\.bak-')"

# bloco (a) com settings {} e com settings ausente
zera_home
printf '{}\n' > "$CL/settings.json"
roda_bloco bl-a
eq "bloco (a) com {}: statusLine.command" "bash ~/.claude/statusline-seiva.sh" "$(jq -r .statusLine.command "$CL/settings.json")"
eq "bloco (a) com {}: diz OK" 1 "$(printf '%s' "$SAI" | grep -c '^OK às ')"
zera_home
roda_bloco bl-a
tem "bloco (a) sem settings: diz OK" "$SAI" "OK às "
eq "bloco (a) sem settings: cria o settings só com a statusLine" "statusLine" "$(jq -r 'keys | join(",")' "$CL/settings.json")"
eq "bloco (a) sem settings: modo 600" 600 "$(stat -c %a "$CL/settings.json")"
eq "bloco (a) sem settings: .bak criado" 1 "$(ls "$CL" | grep -c '^settings\.json\.bak-')"

# bloco (a) com statusLine que já existe: recusa, e o settings não muda
zera_home
printf '{"statusLine":{"type":"command","command":"echo x"}}\n' > "$CL/settings.json"
antes=$(sha256sum "$CL/settings.json" | cut -c1-64)
roda_bloco bl-a
tem "bloco (a) com statusLine existente: PAROU AQUI" "$SAI" "PAROU AQUI"
eq "bloco (a) com statusLine existente: settings igual" "$antes" "$(sha256sum "$CL/settings.json" | cut -c1-64)"
eq "bloco (a) com statusLine existente: não copiou o script" ausente "$(ha "$CL/statusline-seiva.sh")"
eq "bloco (a) com statusLine existente: não criou .bak" 0 "$(ls "$CL" | grep -c 'bak-')"

# bloco (a) com SKILL errado: recusa, e nada é criado
zera_home
prepara bl-errado "$BL_A" "$T/nao-tem-skill"
roda_bloco bl-errado
tem "bloco (a) com SKILL errado: PAROU AQUI" "$SAI" "PAROU AQUI"
eq "bloco (a) com SKILL errado: nada foi criado" 0 "$(ls -A "$CL" | wc -l | tr -d ' ')"

# volta-a com outra statusLine: recusa, e o settings não muda
zera_home
printf '{"statusLine":{"type":"command","command":"echo x"}}\n' > "$CL/settings.json"
antes=$(sha256sum "$CL/settings.json" | cut -c1-64)
roda_bloco bl-volta
tem "volta-a com statusLine de outro: PAROU AQUI" "$SAI" "PAROU AQUI"
eq "volta-a com statusLine de outro: settings igual" "$antes" "$(sha256sum "$CL/settings.json" | cut -c1-64)"

# --- o cache e o ~/.claude de verdade não mudaram ----------------------------------
depois_real=$(stat -c %Y "$cache_real" 2>/dev/null || echo ausente)
eq "~/.cache/seiva de verdade não mudou" "$antes_real" "$depois_real"
eq "~/.claude/settings.json de verdade não mudou (hash)" "$settings_antes" "$(sha256sum "$claude_real/settings.json" 2>/dev/null | cut -c1-64)"
eq "~/.claude/statusline-seiva.sh de verdade não apareceu nem sumiu" "$copia_antes" "$([ -e "$claude_real/statusline-seiva.sh" ] && echo presente || echo ausente)"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
