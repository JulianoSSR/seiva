#!/usr/bin/env bash
# Testa scripts/julgar-pre.sh com relatórios de revisor falsos numa pasta temporária.
# Uso: bash testes/scripts/teste-julgar-pre.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
JP="$RAIZ/scripts/julgar-pre.sh"

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
  SAI=$(bash "$JP" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}

P=$T/tarefa
mkdir -p "$P/relatorios"
printf '# Achados — tarefa\n' >"$P/achados.md"

cat >"$P/relatorios/seguranca-r1.md" <<'FIM'
STATUS: concluído
ACHADOS:
[A-1] ALTO · segurança · confiança 8
Onde: backend/routes/x.js:40
Defeito: rota lista registros sem conferir o dono do objeto
Cenário: usuário de outro cliente lê a lista
Prova: x.js:40 chama db.query sem filtro
Correção sugerida: usar o filtro de sempre

**[A-2] MEDIO · segurança · confiança 6**
Onde: backend/routes/x.js:90
Defeito: erro devolve a mensagem interna
FIM
cat >"$P/relatorios/dados-r1.md" <<'FIM'
[A-1] CRÍTICO · dados · confiança 9
Onde: backend/routes/x.js:42
Defeito: consulta sem o prefixo do schema mistura clientes

[A-2] BAIXO · dados · confiança 7
Onde: plano §Tarefas T3
Defeito: nome do campo diverge do vizinho
FIM
cat >"$P/relatorios/adversario-r1.md" <<'FIM'
HIPÓTESES:
1. premissa errada — coberta em plano §Premissas
ACHADOS:
[A-1] ALTO · adversario · confiança 7
Onde: plano §tarefas   T3
Defeito: a tarefa T3 não diz o que fazer com o registro apagado
FIM

# --- uso errado ---------------------------------------------------------------------
roda "$P" plano
eq "sem relatório: uso errado" 2 "$RC"
roda "$P" meio "$P/relatorios/dados-r1.md"
eq "portão desconhecido: uso errado" 2 "$RC"
roda "$P" plano "$P/relatorios/nao-tem.md"
eq "relatório que não existe: uso errado" 2 "$RC"

# --- rodada 1 do portão do plano ----------------------------------------------------
roda "$P" plano "$P/relatorios/seguranca-r1.md" "$P/relatorios/dados-r1.md" "$P/relatorios/adversario-r1.md"
eq "rodada 1: código 0" 0 "$RC"
tem "cabeçalho com a contagem" "$SAI" "JULGAR rodada 1 · plano · 5 achados (1 CRÍTICO, 2 ALTO, 1 MÉDIO, 1 BAIXO; 1 suspeita (confiança abaixo de 7))"
tem "dois grupos: x.js:40 com x.js:42, e o plano §T3" "$SAI" "· 2 grupos ·"
primeira=$(printf '%s\n' "$SAI" | sed -n 4p)
tem "a 1ª linha da tabela é o CRÍTICO" "$primeira" "| CRÍTICO | dados | 9 | backend/routes/x.js:42 |"
tem "linhas próximas no mesmo arquivo no mesmo grupo" "$(printf '%s\n' "$SAI" | grep 'x.js:40')" "| G-1 |"
tem "o CRÍTICO no mesmo grupo" "$primeira" "| G-1 |"
tem "mesma seção do plano no mesmo grupo (espaço e caixa não contam)" "$(printf '%s\n' "$SAI" | grep 'T3' | grep ALTO)" "| G-2 |"
tem "MEDIO sem acento vira MÉDIO" "$SAI" "| MÉDIO | segurança | 6 |"
eq "uma linha por achado na tabela" 5 "$(printf '%s\n' "$SAI" | grep -c '^| A-')"
nao_tem "a conversa não leva o cenário nem a prova" "$SAI" "usuário de outro cliente"
A=$(cat "$P/achados.md")
tem "achados.md ganha a seção da rodada" "$A" "## Rodada 1 · plano ·"
tem "achados.md guarda a origem com linha e ID local" "$A" "origem relatorios/seguranca-r1.md:3 [A-1]"
tem "achados.md anota os relatórios lidos com hash" "$A" "relatorios/dados-r1.md@"
tem "achados.md deixa o lugar dos vereditos" "$A" "Vereditos (uma linha por achado"
eq "IDs da tarefa de A-1 a A-5" "A-1 A-2 A-3 A-4 A-5" "$(grep -oE '^- A-[0-9]+' "$P/achados.md" | sed 's/^- //' | sort -t- -k2,2n | paste -sd' ' -)"

# --- o mesmo relatório não é lido duas vezes ----------------------------------------
roda "$P" plano "$P/relatorios/dados-r1.md"
tem "relatório já lido: nada novo" "$SAI" "JULGAR nada novo"
eq "relatório já lido: achados.md igual" 1 "$(grep -c '^## Rodada' "$P/achados.md")"

# --- portão do código: IDs continuam e referência por ID vira verificação ------------
cat >"$P/relatorios/adversario-codigo-r1.md" <<'FIM'
ACHADOS:
[A-1] ALTO · adversario · confiança 8
Onde: backend/routes/x.js:120
Defeito: a paginação ignora o limite
REFERÊNCIAS:
- A-3 → mitigado em backend/routes/x.js:44
- A-1 → aberto: o filtro de dono não entrou
FIM
roda "$P" codigo "$P/relatorios/adversario-codigo-r1.md"
tem "código: rodada 1 do portão código" "$SAI" "JULGAR rodada 1 · codigo · 1 achado (1 ALTO)"
tem "código: o ID continua do maior já usado" "$SAI" "| A-6 | ALTO |"
tem "código: referência mitigada vira uma linha" "$SAI" "A-3 → mitigado em backend/routes/x.js:44"
tem "código: referência aberta vira uma linha" "$SAI" "A-1 → aberto: o filtro de dono não entrou"
eq "código: referência não vira achado novo" 1 "$(printf '%s\n' "$SAI" | grep -c '^| A-')"
cat >"$P/relatorios/adversario-codigo-r2.md" <<'FIM'
Nenhum achado. Zero achados é resultado válido.
FIM
roda "$P" codigo "$P/relatorios/adversario-codigo-r2.md"
tem "rodada 2 conta sozinha" "$SAI" "JULGAR rodada 2 · codigo · 0 achados (nenhum)"
roda "$P" codigo --rodada 7 "$P/relatorios/seguranca-r1.md"
tem "--rodada não relê relatório lido" "$SAI" "JULGAR nada novo"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
