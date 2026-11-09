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
roda "$P" marcar 0 feita "$W/perfil.md" --allow-root "$W" --evidence "fixture: inspeção mecânica dos artefatos"
eq "marcar 0 feita" 0 "$RC"
roda "$P" marcar 1 feita registro.md --evidence "fixture: inspeção mecânica dos artefatos"
roda "$P" marcar 2 feita relatorios/batedor-1.md --evidence "fixture: inspeção mecânica dos artefatos"
roda "$P" marcar 3 "feita: plano aprovado pelo construtor" plano.md --evidence "fixture: inspeção mecânica dos artefatos"
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
tem "artefato mexido: revalidar somente a etapa afetada" "$SAI" "PROXIMA 3 Propor"
rm "$P/relatorios/batedor-1.md"
roda "$P" conferir
tem "artefato apagado: SUMIU" "$SAI" "relatorios/batedor-1.md SUMIU"

# --- contexto grande demais --------------------------------------------------------
head -c 9000 /dev/zero | tr '\0' 'x' >>"$P/contexto-tarefa.md"
roda "$P" conferir
tem "contexto acima do alvo é avisado" "$SAI" "ACIMA do alvo"

# --- tarefas por terminar ----------------------------------------------------------
roda "$W" pendentes
tem "pendentes lista etapa com artefato ausente para revalidação" "$SAI" "queda-n2 · 2 Reconhecer"
roda "$P" marcar 9 feita registro.md --evidence "fixture: entrega conferida"
roda "$W" pendentes
tem "tarefa com a etapa 9 feita sai da lista" "$SAI" "nenhuma tarefa por terminar"
roda "$P" marcar 9 "pulada: tarefa cancelada pelo usuário"
roda "$W" pendentes
tem "tarefa com a etapa 9 pulada também sai da lista, como no conferir" "$SAI" "nenhuma tarefa por terminar"
roda "$P" marcar 9 feita registro.md --evidence "fixture: entrega conferida"

# --- tarefa de antes do progresso.md -----------------------------------------------
V=$W/tarefas/2026-01-01-velha
mkdir -p "$V"
roda "$V" conferir
eq "tarefa antiga sem progresso: conferir recusa" 2 "$RC"
tem "tarefa antiga: manda retomar pelo registro" "$ERR" "retome pelo registro.md"
roda "$V" marcar 2 em-curso
eq "tarefa antiga: marcar cria o progresso pelo molde" 10 "$(grep -cE '^\| [0-9] ' "$V/progresso.md")"

# --- pasta de tarefa e pasta de trabalho não se confundem (1.3 e D-9) -------------------
# pendentes pede a pasta de trabalho (a que tem tarefas/); marcar e conferir pedem a pasta da tarefa. Cada caso
# usa a sua pasta, para um erro de um não contaminar o seguinte.
pw() { (cd -- "$1" && pwd -P); }
roda_em() { # roda_em <pasta-onde-estar> <argumentos...>
  local onde=$1
  shift
  SAI=$(cd -- "$onde" && bash "$PRG" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}
# PG1 · pasta de trabalho com uma tarefa por terminar: lista, como sempre
G1=$T/pg1
mkdir -p "$G1"
(cd "$T" && bash "$NOVA" "$G1" pg-um >/dev/null)
roda "$G1" pendentes
eq "PG1 · pendentes na pasta de trabalho: código 0" 0 "$RC"
tem "PG1 · lista a tarefa por terminar" "$SAI" "pg-um · 0 Terreno"
eq "PG1 · nada em stderr" "" "$ERR"

# PG2 · pendentes na pasta da tarefa: recusa e nomeia a pasta de trabalho
G2=$T/pg2
mkdir -p "$G2"
P2=$(cd "$T" && bash "$NOVA" "$G2" pg-dois)
G2R=$(pw "$G2")
roda "$P2" pendentes
eq "PG2 · pendentes na pasta da tarefa: código 2" 2 "$RC"
eq "PG2 · stdout vazio" "" "$SAI"
tem "PG2 · diz que é pasta de tarefa" "$ERR" "pasta de tarefa"
eq "PG2 · a mensagem termina na pasta de trabalho" "$G2R" "${ERR##*tarefas/: }"

# PG3 · tarefa de antes da 1.2.0 (só registro.md): mesma recusa
G3=$T/pg3
mkdir -p "$G3/tarefas/2026-01-01-velha"
printf '# Registro\n' >"$G3/tarefas/2026-01-01-velha/registro.md"
G3R=$(pw "$G3")
roda "$G3/tarefas/2026-01-01-velha" pendentes
eq "PG3 · tarefa só com registro.md: código 2" 2 "$RC"
eq "PG3 · stdout vazio" "" "$SAI"
tem "PG3 · diz que é pasta de tarefa" "$ERR" "pasta de tarefa"
eq "PG3 · a mensagem termina na pasta de trabalho" "$G3R" "${ERR##*tarefas/: }"

# PG4 · caminho "." dentro da tarefa e caminho com barra final: a pasta de trabalho sai resolvida
roda_em "$P2" . pendentes
eq "PG4 · caminho '.': código 2" 2 "$RC"
eq "PG4 · caminho '.': stdout vazio" "" "$SAI"
eq "PG4 · caminho '.': pasta de trabalho em caminho absoluto" "$G2R" "${ERR##*tarefas/: }"
roda "$P2/" pendentes
eq "PG4 · barra final: código 2" 2 "$RC"
eq "PG4 · barra final: pasta de trabalho em caminho absoluto" "$G2R" "${ERR##*tarefas/: }"

# PG5 · pasta de trabalho de projeto novo, sem tarefas/: nada por terminar, como hoje
G5=$T/pg5
mkdir -p "$G5"
printf '# Perfil\n' >"$G5/perfil.md"
roda "$G5" pendentes
eq "PG5 · pasta de trabalho sem tarefas/: código 0" 0 "$RC"
tem "PG5 · nenhuma tarefa por terminar" "$SAI" "nenhuma tarefa por terminar"

# PG6 · pasta de tarefa fora de .../tarefas/<tarefa>: a mensagem diz o que procurar, sem inventar caminho
G6=$T/pg6
mkdir -p "$G6"
cp -R "$P2" "$G6/minha-tarefa"
roda "$G6/minha-tarefa" pendentes
eq "PG6 · tarefa fora de tarefas/: código 2" 2 "$RC"
eq "PG6 · stdout vazio" "" "$SAI"
tem "PG6 · diz que é pasta de tarefa" "$ERR" "pasta de tarefa"
tem "PG6 · diz o que procurar" "$ERR" "a que contém tarefas/"
sem_o_dado=${ERR//"$(pw "$G6/minha-tarefa")"/}
nao_tem "PG6 · não inventa caminho (só a própria tarefa aparece)" "$sem_o_dado" "$T"

# PG7 · marcar na pasta de trabalho (D-9): recusa, e não cria progresso.md na raiz
G7=$T/pg7
mkdir -p "$G7"
(cd "$T" && bash "$NOVA" "$G7" pg-sete >/dev/null)
roda "$G7" marcar 3 feita
eq "PG7 · marcar na pasta de trabalho: código 2" 2 "$RC"
eq "PG7 · stdout vazio" "" "$SAI"
tem "PG7 · diz que é pasta de trabalho" "$ERR" "pasta de trabalho"
tem "PG7 · pede a pasta da tarefa" "$ERR" "$G7/tarefas/<tarefa>"
nao_tem "PG7 · sem progresso.md solto, não fala de arquivo solto" "$ERR" "solto"
eq "PG7 · nenhum progresso.md criado na raiz" "nao" "$([ -e "$G7/progresso.md" ] && echo sim || echo nao)"

# PG8 · conferir na pasta de trabalho (D-9): a mesma recusa
G8=$T/pg8
mkdir -p "$G8"
(cd "$T" && bash "$NOVA" "$G8" pg-oito >/dev/null)
roda "$G8" conferir
eq "PG8 · conferir na pasta de trabalho: código 2" 2 "$RC"
eq "PG8 · stdout vazio" "" "$SAI"
tem "PG8 · diz que é pasta de trabalho" "$ERR" "pasta de trabalho"
tem "PG8 · pede a pasta da tarefa" "$ERR" "$G8/tarefas/<tarefa>"
eq "PG8 · nenhum progresso.md criado na raiz" "nao" "$([ -e "$G8/progresso.md" ] && echo sim || echo nao)"

# PG9 · precedência: tarefas/ e progresso.md solto na mesma pasta. A pasta é de trabalho.
G9=$T/pg9
mkdir -p "$G9"
(cd "$T" && bash "$NOVA" "$G9" pg-nove >/dev/null)
printf 'solto\n' >"$G9/progresso.md"
roda "$G9" pendentes
eq "PG9 · pendentes lista como pasta de trabalho: código 0" 0 "$RC"
tem "PG9 · pendentes lista a tarefa" "$SAI" "pg-nove"
roda "$G9" marcar 3 feita
eq "PG9 · marcar recusa: código 2" 2 "$RC"
eq "PG9 · marcar: stdout vazio" "" "$SAI"
tem "PG9 · marcar: cita o progresso.md solto" "$ERR" "progresso.md solto"
tem "PG9 · marcar: diz que veio de um marcar errado" "$ERR" "marcar errado"
roda "$G9" conferir
eq "PG9 · conferir recusa: código 2" 2 "$RC"
eq "PG9 · conferir: stdout vazio" "" "$SAI"
tem "PG9 · conferir: cita o progresso.md solto" "$ERR" "progresso.md solto"
eq "PG9 · o arquivo solto não foi apagado nem mexido" "solto" "$(cat "$G9/progresso.md" 2>/dev/null)"

# PG10 · pasta sem tarefas/ e tarefa nova seguem como hoje
G10=$T/pg10
mkdir -p "$G10/vazia" "$G10/velha"
printf '# Registro\n' >"$G10/velha/registro.md"
roda "$G10/vazia" marcar 2 em-curso
eq "PG10 · pasta sem progresso e sem tarefas/: marcar funciona" 0 "$RC"
eq "PG10 · cria o progresso pelo molde (10 etapas)" 10 "$(grep -cE '^\| [0-9] ' "$G10/vazia/progresso.md")"
roda "$G10/velha" marcar 2 em-curso
eq "PG10 · tarefa só com registro.md: marcar funciona" 0 "$RC"
eq "PG10 · cria o progresso pelo molde (10 etapas)" 10 "$(grep -cE '^\| [0-9] ' "$G10/velha/progresso.md")"
mkdir -p "$G10/velha2"
printf '# Registro\n' >"$G10/velha2/registro.md"
roda "$G10/velha2" conferir
eq "PG10 · tarefa só com registro.md: conferir recusa como hoje" 2 "$RC"
tem "PG10 · manda retomar pelo registro" "$ERR" "retome pelo registro.md"
G10N=$T/pg10n
mkdir -p "$G10N"
P10=$(cd "$T" && bash "$NOVA" "$G10N" pg-dez)
roda "$P10" marcar 0 em-curso
eq "PG10 · tarefa nova: marcar, código 0" 0 "$RC"
eq "PG10 · tarefa nova: marcar, saída de sempre" "etapa 0: em-curso" "$SAI"
roda "$P10" conferir
eq "PG10 · tarefa nova: conferir, código 0" 0 "$RC"
tem "PG10 · tarefa nova: conferir, a próxima é a etapa em curso" "$SAI" "PROXIMA 0 Terreno"

# --- a pasta tarefas/ é um terceiro tipo de pasta (G-a a G-d) ---------------------------
# pendentes pede a pasta que contém tarefas/; marcar e conferir pedem uma tarefa. Nenhum dos três cria nada na tarefas/.
GW=$T/g-trabalho
mkdir -p "$GW"
GT=$(cd "$T" && bash "$NOVA" "$GW" g-um)
GWR=$(pw "$GW")
GTS=$GWR/tarefas

# G-c · o caminho certo segue como hoje (controle)
roda "$GW" pendentes
eq "G-c · pendentes na pasta de trabalho: código 0" 0 "$RC"
tem "G-c · pendentes lista a tarefa" "$SAI" "g-um · 0 Terreno"
roda "$GT" marcar 0 em-curso
eq "G-c · marcar na pasta da tarefa: código 0" 0 "$RC"
eq "G-c · marcar na pasta da tarefa: saída de sempre" "etapa 0: em-curso" "$SAI"
roda "$GT" conferir
eq "G-c · conferir na pasta da tarefa: código 0" 0 "$RC"

# G-a · pendentes na tarefas/: recusa e nomeia o pai
roda "$GW/tarefas" pendentes
eq "G-a · pendentes na tarefas/: código 2" 2 "$RC"
eq "G-a · stdout vazio" "" "$SAI"
tem "G-a · diz que é a pasta tarefas/" "$ERR" "é a pasta tarefas/"
tem "G-a · diz o que pede" "$ERR" "pendentes pede a pasta que a contém, "
eq "G-a · a mensagem termina no pai, em caminho absoluto" "$GWR" "${ERR##*a contém, }"
roda_em "$GW/tarefas" . pendentes
eq "G-a · caminho '.': código 2" 2 "$RC"
eq "G-a · caminho '.': o pai sai resolvido" "$GWR" "${ERR##*a contém, }"
roda "$GW/tarefas/" pendentes
eq "G-a · barra final: código 2" 2 "$RC"

# G-b · marcar e conferir na tarefas/: recusa, sem progresso.md criado
roda "$GW/tarefas" marcar 3 feita
eq "G-b · marcar na tarefas/: código 2" 2 "$RC"
eq "G-b · stdout vazio" "" "$SAI"
tem "G-b · diz que é a pasta tarefas/" "$ERR" "$GTS é a pasta tarefas/"
tem "G-b · pede uma tarefa dentro dela" "$ERR" "marcar pede uma tarefa dentro dela, $GTS/<tarefa>"
eq "G-b · nenhum progresso.md criado na tarefas/" nao "$([ -e "$GW/tarefas/progresso.md" ] && echo sim || echo nao)"
roda "$GW/tarefas" conferir
eq "G-b · conferir na tarefas/: código 2" 2 "$RC"
eq "G-b · conferir: stdout vazio" "" "$SAI"
tem "G-b · conferir: pede uma tarefa dentro dela" "$ERR" "conferir pede uma tarefa dentro dela, $GTS/<tarefa>"
eq "G-b · conferir: nenhum progresso.md criado na tarefas/" nao "$([ -e "$GW/tarefas/progresso.md" ] && echo sim || echo nao)"

# G-d · progresso.md solto na raiz da tarefas/: continua sendo a pasta tarefas (não vira pasta de tarefa)
GW2=$T/g-trabalho-2
mkdir -p "$GW2"
(cd "$T" && bash "$NOVA" "$GW2" g-dois >/dev/null)
GW2R=$(pw "$GW2")
printf 'solto\n' >"$GW2/tarefas/progresso.md"
roda "$GW2/tarefas" pendentes
eq "G-d · pendentes com progresso.md solto: código 2" 2 "$RC"
tem "G-d · pendentes: ainda é a pasta tarefas/" "$ERR" "é a pasta tarefas/"
eq "G-d · pendentes: o pai sai nomeado" "$GW2R" "${ERR##*a contém, }"
roda "$GW2/tarefas" marcar 3 feita
eq "G-d · marcar com progresso.md solto: código 2" 2 "$RC"
tem "G-d · marcar: ainda é a pasta tarefas/" "$ERR" "é a pasta tarefas/"
roda "$GW2/tarefas" conferir
eq "G-d · conferir com progresso.md solto: código 2" 2 "$RC"
tem "G-d · conferir: ainda é a pasta tarefas/" "$ERR" "é a pasta tarefas/"
eq "G-d · o arquivo solto não foi mexido" "solto" "$(cat "$GW2/tarefas/progresso.md" 2>/dev/null)"

# G-b · a pasta tarefas/ por link simbólico com outro nome também é recusada
ln -s "$GW2/tarefas" "$T/g-atalho"
roda "$T/g-atalho" marcar 3 feita
eq "G-b · tarefas/ por link simbólico: código 2" 2 "$RC"
tem "G-b · tarefas/ por link simbólico: diz que é a pasta tarefas/" "$ERR" "é a pasta tarefas/"
eq "G-b · tarefas/ por link simbólico: o arquivo solto não foi mexido" "solto" "$(cat "$GW2/tarefas/progresso.md" 2>/dev/null)"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos · retomada do ensaio: $lido bytes ≈ $((lido * 10 / 35)) tokens"
