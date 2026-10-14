#!/usr/bin/env bash
# Testa scripts/progresso.sh e a retomada barata: uma tarefa N2 cai no meio da leva de ataque ao plano, e a sessão nova
# retoma lendo só o contexto-tarefa.md, o progresso.md e a saída do conferir, sem refazer etapa feita.
# Tudo numa pasta temporária, fora de qualquer repositório.
# Uso: bash testes/scripts/teste-progresso.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
PRG="$RAIZ/scripts/progresso.sh"
NOVA="$RAIZ/scripts/nova-tarefa.sh"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

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
roda() {
  SAI=$(bash "$PRG" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}

# --- a tarefa nasce com progresso.md e contexto-tarefa.md ---------------------------
W=$T/trabalho
mkdir -p "$W"
P=$(cd "$T" && bash "$NOVA" "$W" queda-n2)
eq "nova-tarefa cria a pasta" 0 $?
eq "progresso.md criado" sim "$([ -f "$P/progresso.md" ] && echo sim)"
eq "contexto-tarefa.md criado" sim "$([ -f "$P/contexto-tarefa.md" ] && echo sim)"
nao_tem "registro sem a seção Estado (mudou para o progresso.md)" "$(cat "$P/registro.md")" "## Estado"
eq "dez etapas no progresso" 10 "$(grep -cE '^\| [0-9] ' "$P/progresso.md")"

# --- uso errado ---------------------------------------------------------------------
roda "$P" marcar 12 feita
eq "etapa 12: uso errado" 2 "$RC"
roda "$P" marcar 3 acabou
eq "status desconhecido: uso errado" 2 "$RC"
roda "$P" marcar 3 feita nao-existe.md
eq "artefato que não existe: recusa" 2 "$RC"
: >"$P/com espaco.md"
roda "$P" marcar 3 feita "com espaco.md"
eq "artefato com espaço: recusa" 2 "$RC"

# --- etapas 0 a 3 feitas, 4 em curso (a leva de ataque ao plano) --------------------
printf '# Perfil\nL1 regra\n' >"$W/perfil.md"
mkdir -p "$P/relatorios"
printf 'MAPA:\n- a.js:10 — rota\n' >"$P/relatorios/batedor-1.md"
printf '# Plano\nT1 mexe em a.js\n' >>"$P/plano.md"
roda "$P" marcar 0 feita "$W/perfil.md"
eq "marcar 0 feita" 0 "$RC"
roda "$P" marcar 1 feita registro.md
roda "$P" marcar 2 feita relatorios/batedor-1.md
roda "$P" marcar 3 "feita: plano aprovado pelo construtor" plano.md
roda "$P" marcar 4 "em-curso: rodada 1/2 · leva adversario, seguranca"
eq "marcar 4 em curso" 0 "$RC"
tem "a nota fica na linha" "$(grep -E '^\| 4 ' "$P/progresso.md")" "rodada 1/2"

cat >"$P/contexto-tarefa.md" <<'FIM'
# Contexto da tarefa queda-n2

- Objetivo: rota nova de listagem de coletas por rota municipal, com filtro de cliente de sempre.
- Nível: N2 — regra de negócio nova em 4 arquivos; usa o filtro de cliente existente sem mudá-lo.
- Etapa atual: 4 Atacar o plano · rodada 1 de 2
- Atualizado em: 2026-10-13 10:00 · sessão b8c5a4e6

## Próxima ação
Leva 4 disparada: adversário → relatorios/adversario-r1.md; lente de segurança → relatorios/seguranca-r1.md.
Na volta, redispare só quem não deixou relatório, com o pacote em relatorios/pacote-*.md. Depois, julgar-pre.sh e etapa 5.

## Decisões que esperam o usuário
- D-2 — a listagem mostra pontos desativados? (o plano supõe que não)

## Arquivos-chave
- plano.md — tarefas T1 a T4 e riscos R1 a R3
- relatorios/batedor-1.md — mapa com citações; fonte única de código para os revisores
- backend/routes/coletas.js — onde entra a rota
- backend/middleware/permissao.js — checagem de sempre, não muda

## Orçamento gasto
2 de 7 agentes · 61 mil tokens dos subagentes · sessão do orquestrador ≈ 420 mil (nota do orcamento-local.sh)
FIM

# --- a queda: a sessão nova só lê o contexto, o progresso e o conferir --------------
roda "$P" conferir
eq "conferir com tudo em ordem: código 0" 0 "$RC"
tem "a próxima é a etapa em curso" "$SAI" "PROXIMA 4 Atacar o plano"
tem "etapa feita confere" "$SAI" "3 Propor · feita: plano aprovado pelo construtor · plano.md confere"
tem "o conferir mostra a leva em curso" "$SAI" "leva adversario, seguranca"
nao_tem "etapa pendente não ocupa linha" "$SAI" "6 Construir"
tem "estima o contexto-tarefa.md" "$SAI" "contexto-tarefa.md ≈"
nao_tem "contexto dentro do alvo" "$SAI" "ACIMA do alvo"
lido=$(($(wc -c <"$P/contexto-tarefa.md") + $(wc -c <"$P/progresso.md") + ${#SAI}))
# 7.000 bytes ≈ 2.000 tokens a 3,5 bytes por token (estimativa; texto em português com acento)
eq "retomada lê no máximo 7.000 bytes (≈ 2.000 tokens)" sim "$([ "$lido" -le 7000 ] && echo sim || echo "não: $lido bytes")"

# --- artefato mexido ou apagado depois de feito -------------------------------------
printf 'mudança de outra sessão\n' >>"$P/plano.md"
roda "$P" conferir
eq "artefato mexido: código 1" 1 "$RC"
tem "artefato mexido: diz para olhar, não refazer" "$SAI" "plano.md MUDOU depois de feita (olhe o artefato; não refaça a etapa)"
tem "artefato mexido: a próxima continua a 4" "$SAI" "PROXIMA 4 Atacar o plano"
rm "$P/relatorios/batedor-1.md"
roda "$P" conferir
tem "artefato apagado: SUMIU" "$SAI" "relatorios/batedor-1.md SUMIU"

# --- contexto grande demais --------------------------------------------------------
head -c 9000 /dev/zero | tr '\0' 'x' >>"$P/contexto-tarefa.md"
roda "$P" conferir
tem "contexto acima do alvo é avisado" "$SAI" "ACIMA do alvo"

# --- tarefas por terminar ----------------------------------------------------------
roda "$W" pendentes
tem "pendentes lista a tarefa" "$SAI" "queda-n2 · 4 Atacar o plano"
roda "$P" marcar 9 feita
roda "$W" pendentes
tem "tarefa com a etapa 9 feita sai da lista" "$SAI" "nenhuma tarefa por terminar"
roda "$P" marcar 9 "pulada: tarefa cancelada pelo usuário"
roda "$W" pendentes
tem "tarefa com a etapa 9 pulada também sai da lista, como no conferir" "$SAI" "nenhuma tarefa por terminar"
roda "$P" marcar 9 feita

# --- tarefa de antes do progresso.md -----------------------------------------------
V=$W/tarefas/2026-01-01-velha
mkdir -p "$V"
roda "$V" conferir
eq "tarefa antiga sem progresso: conferir recusa" 2 "$RC"
tem "tarefa antiga: manda retomar pelo registro" "$ERR" "retome pelo registro.md"
roda "$V" marcar 2 em-curso
eq "tarefa antiga: marcar cria o progresso pelo molde" 10 "$(grep -cE '^\| [0-9] ' "$V/progresso.md")"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos · retomada do ensaio: $lido bytes ≈ $((lido * 10 / 35)) tokens"
