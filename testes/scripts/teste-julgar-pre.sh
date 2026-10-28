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

# --- severidade fora do molde, cabeçalho sem severidade e REFERÊNCIAS na mesma linha ------
Q=$T/q
mkdir -p "$Q/relatorios"
cat >"$Q/relatorios/r1.md" <<'FIM'
HIPÓTESES (pre-mortem):
1. a citação cai fora do repositório — não coberta → [A-1] ALTO, ver abaixo

[A-1] ALTO · segurança · confiança 8
Onde: a.sh:10
Defeito: primeiro defeito

[A-2] Crítico · dados · confiança 9
Onde: b.sh:20
Defeito: grafia fora do molde, que antes sumia

[A-3] médio · operação · confiança 7
Onde: c.sh:30
Defeito: tudo minúsculo

[A-4] Grave · operação · confiança 9
Onde: d.sh:40
Defeito: severidade que não existe

[A-5] BAIXO · contrato · confiança 7
Onde: e.sh:50
Defeito: cita o A-9999 de outra tarefa e um API_TOKEN=abcdef0123456789abcdef no texto

REFERÊNCIAS: A-7 → mitigado em c.sh:5
A-8 → aberto: falta teste
FIM
roda "$Q" codigo "$Q/relatorios/r1.md"
tem "severidade em outra caixa conta" "$SAI" "4 achados (1 CRÍTICO, 1 ALTO, 1 MÉDIO, 1 BAIXO)"
tem "Crítico com inicial maiúscula vira CRÍTICO, com o próprio lugar" "$SAI" "| CRÍTICO | dados | 9 | b.sh:20 |"
tem "o achado anterior fica com o lugar dele" "$SAI" "| ALTO | segurança | 8 | a.sh:10 |"
nao_tem "linha de hipótese que cita [A-1] no meio não vira achado" "$SAI" "não coberta"
tem "cabeçalho sem severidade é avisado" "$SAI" "SEM SEVERIDADE"
tem "o aviso diz onde está" "$SAI" "r1.md:16 [A-4]"
nao_tem "o Onde do cabeçalho sem severidade não cai em achado nenhum" "$SAI" "d.sh:40"
tem "REFERÊNCIAS: na mesma linha do título é lida" "$SAI" "- A-7 → mitigado em c.sh:5"
tem "referência sozinha na linha continua lida" "$SAI" "- A-8 → aberto: falta teste"
nao_tem "segredo no texto do revisor sai mascarado na saída" "$SAI" "abcdef0123456789"
nao_tem "segredo no texto do revisor sai mascarado no achados.md" "$(cat "$Q/achados.md")" "abcdef0123456789"
tem "achados.md guarda o aviso de cabeçalho sem severidade" "$(cat "$Q/achados.md")" "r1.md:16 [A-4] (sem severidade reconhecida)"
eq "achados.md novo nasce só para o dono" 600 "$(stat -c %a "$Q/achados.md")"
cat >"$Q/relatorios/r2.md" <<'FIM'
[A-1] ALTO · contrato · confiança 8
Onde: f.sh:1
Defeito: depois de um A-9999 citado num Defeito
FIM
roda "$Q" codigo "$Q/relatorios/r2.md"
tem "o A-9999 citado num Defeito não puxa a numeração" "$SAI" "| A-5 | ALTO | contrato |"

# --- cabeçalho com prefixo de lista ou de rótulo; Onde que não tem cabeçalho reconhecido ----
U=$T/u
mkdir -p "$U/relatorios"
cat >"$U/relatorios/r1.md" <<'FIM'
1) [A-1] ALTO · segurança · confiança 8
Onde: um.sh:1
Defeito: prefixo 1)

(2) [A-2] MÉDIO · dados · confiança 7
Onde: dois.sh:2
Defeito: prefixo (2)

**Achado [A-3]** BAIXO · contrato · confiança 7
Onde: tres.sh:3
Defeito: rótulo Achado em negrito

Achado [A-4] — ALTO · operação · confiança 9
Onde: quatro.sh:4
Defeito: rótulo com travessão

• `[A-5]` ALTO · segurança · confiança 8
Onde: cinco.sh:5
Defeito: marcador e crase

Achado sete, grave, segurança
Onde: sete.sh:7
Defeito: cabeçalho que ninguém reconhece
FIM
roda "$U" codigo "$U/relatorios/r1.md"
tem "prefixos de lista e rótulo: os cinco contam" "$SAI" "5 achados (3 ALTO, 1 MÉDIO, 1 BAIXO)"
tem "1) [A-1] fica com o próprio lugar" "$SAI" "| ALTO | segurança | 8 | um.sh:1 |"
tem "(2) [A-2] conta" "$SAI" "| MÉDIO | dados | 7 | dois.sh:2 |"
tem "**Achado [A-3]** conta" "$SAI" "| BAIXO | contrato | 7 | tres.sh:3 |"
tem "Achado [A-4] — ALTO conta" "$SAI" "| ALTO | operação | 9 | quatro.sh:4 |"
tem "marcador e crase contam, com o próprio lugar" "$SAI" "| ALTO | segurança | 8 | cinco.sh:5 |"
nao_tem "o Onde sem cabeçalho não cai no achado anterior" "$SAI" "sete.sh:7"
tem "o Onde sem cabeçalho é avisado com a linha" "$SAI" "r1.md:22 (Onde sem cabeçalho [A-n] reconhecido)"

# --- máscara por campo: nome de segredo ou BEGIN no texto não apaga o resto ------------------
V=$T/v
mkdir -p "$V/relatorios"
cat >"$V/relatorios/r1.md" <<'FIM'
[A-1] ALTO · operação · confiança 8
Onde: a.sh:1
Defeito: a variável MINHA_KEY aparece no log

[A-2] ALTO · segurança · confiança 8
Onde: b.sh:2
Defeito: a linha -----BEGIN PRIVATE KEY----- fica sem o END no trecho

[A-3] MÉDIO · contrato · confiança 7
Onde: c.sh:3
Defeito: achado depois da chave

A-9 → mitigado em d.sh:4
FIM
roda "$V" codigo "$V/relatorios/r1.md"
tem "BEGIN no Defeito: os três contam" "$SAI" "3 achados (2 ALTO, 1 MÉDIO)"
eq "BEGIN no Defeito: o achados.md tem as três linhas" 3 "$(grep -c '^- A-[0-9]* · ' "$V/achados.md")"
tem "achado depois da chave continua no achados.md" "$(cat "$V/achados.md")" "achado depois da chave"
tem "referência depois da chave continua" "$(cat "$V/achados.md")" "A-9 → mitigado em d.sh:4"
tem "a origem fica na linha mesmo com nome terminado em _KEY" "$(grep 'a.sh:1' "$V/achados.md")" "origem relatorios/r1.md:"
tem "a linha de vereditos continua" "$(cat "$V/achados.md")" "Vereditos (uma linha por achado"

# --- achado fora do formato: o relatório que não fecha em [A-n] avisa, o válido sem achado não (1.4) ----
# Uma pasta de tarefa por caso: relatório lido fica registrado no achados.md da pasta.
nova_tarefa() { # nova_tarefa <nome> -> caminho da pasta
  local d=$T/jp-$1
  mkdir -p "$d/relatorios"
  printf '# Achados — %s\n' "$1" >"$d/achados.md"
  printf '%s\n' "$d"
}
primeira_linha() { printf '%s\n' "$1" | sed -n 1p; }

# JP1 · cabeçalho ### L-1 (ALTO) com Arquivo: e Problema:
D1=$(nova_tarefa jp1)
cat >"$D1/relatorios/fora.md" <<'FIM'
### L-1 (ALTO) a soma duplica quando o pedido volta
Arquivo: a.sh:3
Problema: a soma do pedido duplica o item
FIM
roda "$D1" plano --rodada 1 "$D1/relatorios/fora.md"
eq "JP1 · achado fora do formato: código 0" 0 "$RC"
tem "JP1 · não conta como achado" "$SAI" "0 achados (nenhum)"
tem "JP1 · a lista de não contados cita relatório:linha e a quantidade" "$SAI" "- relatorios/fora.md:1 (achado fora do formato: 3 linha(s) de cabeçalho ou campo sem [A-n] reconhecido; formato em referencias/contratos.md)"
tem "JP1 · o achados.md guarda o aviso" "$(cat "$D1/achados.md")" "- relatorios/fora.md:1 (achado fora do formato: 3 linha(s)"
tem "JP1 · o achados.md diz a classe nova no cabeçalho da lista" "$(cat "$D1/achados.md")" "achado fora do formato (abra o relatório e julgue à mão)"
nao_tem "JP1 · nenhum texto do relatório entra no aviso" "$SAI" "a soma do pedido"
# E-c com número de lista e negrito, e E-a com marcador e negrito
D1B=$(nova_tarefa jp1b)
cat >"$D1B/relatorios/formas.md" <<'FIM'
1. **F-10** MÉDIO · dados · confiança 8
- **Local:** b.sh:9
FIM
roda "$D1B" plano --rodada 1 "$D1B/relatorios/formas.md"
tem "JP1 · número de lista e negrito: o cabeçalho candidato é lido" "$SAI" "relatorios/formas.md:1 (achado fora do formato: 2 linha(s)"

# JP2 · [L-1] ALTO · lente · confiança 8 com Onde: e Defeito: (caso do ciclo-arboris)
D2=$(nova_tarefa jp2)
cat >"$D2/relatorios/lbracket.md" <<'FIM'
[L-1] ALTO · lente · confiança 8
Onde: a.sh:3
Defeito: a soma duplica
FIM
roda "$D2" plano --rodada 1 "$D2/relatorios/lbracket.md"
tem "JP2 · a lista cita a linha do cabeçalho candidato" "$SAI" "- relatorios/lbracket.md:1 (achado fora do formato: 2 linha(s)"
tem "JP2 · o aviso de Onde sem cabeçalho continua" "$SAI" "- relatorios/lbracket.md:2 (Onde sem cabeçalho [A-n] reconhecido)"
tem "JP2 · não conta como achado" "$SAI" "0 achados (nenhum)"
D2B=$(nova_tarefa jp2b)
printf 'Defeito: a soma duplica\n' >"$D2B/relatorios/solto.md"
roda "$D2B" plano --rodada 1 "$D2B/relatorios/solto.md"
tem "JP2 · Defeito: solto, sem cabeçalho reconhecido aberto, avisa (hoje some)" "$SAI" "- relatorios/solto.md:1 (achado fora do formato: 1 linha(s)"
D2C=$(nova_tarefa jp2c)
cat >"$D2C/relatorios/bloco.md" <<'FIM'
[A-1] ALTO · segurança · confiança 8
Onde: a.sh:1
Defeito: um
Defeito: o segundo Defeito do mesmo bloco é ignorado, como hoje
Cenário: alguém vê o que não devia
Prova: a.sh:1
Correção sugerida: filtrar
FIM
roda "$D2C" plano --rodada 1 "$D2C/relatorios/bloco.md"
nao_tem "JP2 · Defeito: (inclusive o segundo) dentro de bloco reconhecido não avisa" "$SAI" "(achado fora do formato:"

# JP3 · relatório válido sem achado, no molde do adversário
D3=$(nova_tarefa jp3)
cat >"$D3/relatorios/adv.md" <<'FIM'
HIPÓTESES (pre-mortem):
1. a premissa não vale — coberta em plano §Premissas
2. o arquivo some no meio — não dá para saber → pergunta
ACHADOS: nenhum
SUSPEITAS: nenhuma
REFERÊNCIAS: nenhuma
PERGUNTAS: nenhuma
FIM
roda "$D3" plano --rodada 1 "$D3/relatorios/adv.md"
tem "JP3 · válido sem achado: 0 achados" "$SAI" "0 achados (nenhum)"
nao_tem "JP3 · sem aviso de achado fora do formato" "$SAI" "(achado fora do formato:"
nao_tem "JP3 · sem lista de não contados" "$SAI" "SEM SEVERIDADE"

# JP4 · hipótese que cita risco do plano, antes da declaração de zero; Prova: solto
D4=$(nova_tarefa jp4)
cat >"$D4/relatorios/risco.md" <<'FIM'
HIPÓTESES:
1. R-2 (ALTO) do plano: coberta em T3
Prova: x
Nenhum achado. Zero achados é resultado válido.
FIM
roda "$D4" plano --rodada 1 "$D4/relatorios/risco.md"
tem "JP4 · risco do plano antes da declaração estrita: 0 achados" "$SAI" "0 achados (nenhum)"
nao_tem "JP4 · sem aviso (E-c antes da declaração não conta, Prova: não é evidência)" "$SAI" "(achado fora do formato:"
D4B=$(nova_tarefa jp4b)
i=0
for decl in 'ACHADOS: nenhum' 'ACHADOS: Nenhuma' '**ACHADOS:** zero' 'ACHADOS: 0' '- Nenhum achado.' '1. zero achados;' 'Sem achados!' '**Sem achados**'; do
  i=$((i + 1))
  printf '1. R-2 (ALTO) do plano: coberta em T3\n%s\n' "$decl" >"$D4B/relatorios/decl$i.md"
done
roda "$D4B" plano --rodada 1 "$D4B"/relatorios/decl?.md
nao_tem "JP4 · as oito formas de declarar zero suprimem o que vem antes" "$SAI" "(achado fora do formato:"

# JP5 · declara zero, mas traz campos de achado
D5=$(nova_tarefa jp5)
cat >"$D5/relatorios/contradiz.md" <<'FIM'
ACHADOS: nenhum
Arquivo: a.sh:3
Problema: a soma duplica
FIM
roda "$D5" plano --rodada 1 "$D5/relatorios/contradiz.md"
tem "JP5 · campo de achado depois de ACHADOS: nenhum avisa" "$SAI" "- relatorios/contradiz.md:2 (achado fora do formato: 2 linha(s)"
D5B=$(nova_tarefa jp5b)
cat >"$D5B/relatorios/antes.md" <<'FIM'
Arquivo: a.sh:3
ACHADOS: nenhum
FIM
roda "$D5B" plano --rodada 1 "$D5B/relatorios/antes.md"
tem "JP5 · campo de achado antes da declaração também avisa (E-a nunca é suprimida)" "$SAI" "- relatorios/antes.md:1 (achado fora do formato: 1 linha(s)"

# JP6 · relatório misto: um [A-1] completo e um bloco ### L-2
D6=$(nova_tarefa jp6)
cat >"$D6/relatorios/misto.md" <<'FIM'
[A-1] ALTO · segurança · confiança 8
Onde: a.sh:1
Defeito: um

### L-2 (ALTO) outro
Arquivo: b.sh:2
FIM
roda "$D6" plano --rodada 1 "$D6/relatorios/misto.md"
tem "JP6 · conta o achado reconhecido" "$SAI" "1 achado (1 ALTO)"
tem "JP6 · avisa o outro, com a linha dele" "$SAI" "- relatorios/misto.md:5 (achado fora do formato: 2 linha(s)"
nao_tem "JP6 · o aviso não vai para o achado reconhecido" "$SAI" "misto.md:1 (achado fora"

# JP7 · referência a achado antigo sem colchetes
D7=$(nova_tarefa jp7)
cat >"$D7/relatorios/antigo.md" <<'FIM'
[A-1] ALTO · segurança · confiança 8
Onde: a.sh:1
Defeito: um
A-3 · ALTO · segurança · confiança 8 já foi julgado no portão do plano
FIM
roda "$D7" codigo --rodada 1 "$D7/relatorios/antigo.md"
tem "JP7 · conta só o achado reconhecido" "$SAI" "1 achado (1 ALTO)"
nao_tem "JP7 · A-n sem colchetes não é cabeçalho candidato" "$SAI" "(achado fora do formato:"

# JP8 · prosa pura: limitação conhecida (D-4), fixada aqui
D8=$(nova_tarefa jp8)
printf 'Achei dois problemas. O primeiro: a soma duplica em a.sh linha 3, grave.\n' >"$D8/relatorios/prosa.md"
roda "$D8" plano --rodada 1 "$D8/relatorios/prosa.md"
tem "JP8 · prosa pura: 0 achados" "$SAI" "0 achados (nenhum)"
nao_tem "JP8 · prosa pura segue sem aviso (limitação conhecida: sem rótulo nem ID, o script não vê)" "$SAI" "(achado fora do formato:"

# JP9 · segredo falso numa linha de evidência
D9=$(nova_tarefa jp9)
cat >"$D9/relatorios/segredo.md" <<'FIM'
### L-1 (ALTO) API_TOKEN=abcdef0123456789abcdef
Arquivo: a.sh:3
FIM
roda "$D9" plano --rodada 1 "$D9/relatorios/segredo.md"
tem "JP9 · o aviso existe e cita relatório:linha" "$SAI" "- relatorios/segredo.md:1 (achado fora do formato: 2 linha(s)"
nao_tem "JP9 · o valor não aparece na saída" "$SAI" "abcdef0123456789"
nao_tem "JP9 · o valor não aparece no achados.md" "$(cat "$D9/achados.md")" "abcdef0123456789"
nao_tem "JP9 · o valor não aparece no stderr" "$ERR" "abcdef0123456789"

# JP10 · o mesmo relatório lido de novo
roda "$D1" plano --rodada 2 "$D1/relatorios/fora.md"
tem "JP10 · segunda corrida: nada novo" "$SAI" "JULGAR nada novo"
tem "JP10 · o achados.md guarda o aviso da 1ª leitura" "$(cat "$D1/achados.md")" "- relatorios/fora.md:1 (achado fora do formato: 3 linha(s)"
eq "JP10 · o achados.md não ganha seção na 2ª corrida" 1 "$(grep -c '^## Rodada' "$D1/achados.md")"

# JP11 · contrato de saída (a saída de JP1)
D11=$(nova_tarefa jp11)
cp "$D1/relatorios/fora.md" "$D11/relatorios/fora.md"
roda "$D11" plano --rodada 3 "$D11/relatorios/fora.md"
eq "JP11 · código 0" 0 "$RC"
tem "JP11 · a 1ª linha começa por JULGAR rodada" "$(primeira_linha "$SAI")" "JULGAR rodada 3 · plano · 0 achados (nenhum) · 0 grupos · detalhe em "
nao_tem "JP11 · tabela vazia" "$SAI" "| ID |"

# JP12 · suspeita com colchetes em relatório válido
D12=$(nova_tarefa jp12)
cat >"$D12/relatorios/susp.md" <<'FIM'
[A-1] ALTO · segurança · confiança 8
Onde: a.sh:1
Defeito: um

SUSPEITAS:
[S-1] BAIXO · dados · confiança 5 — a ordem das colunas pode mudar no export
FIM
roda "$D12" plano --rodada 1 "$D12/relatorios/susp.md"
tem "JP12 · conta só o achado" "$SAI" "1 achado (1 ALTO)"
nao_tem "JP12 · [S-n] é suspeita, não cabeçalho candidato" "$SAI" "(achado fora do formato:"

# JP13 · suspeita sem colchetes, sem achado
D13=$(nova_tarefa jp13)
cat >"$D13/relatorios/susp2.md" <<'FIM'
ACHADOS: nenhum
SUSPEITAS:
S-1 MÉDIO · contrato · confiança 5: o nome do campo pode divergir do vizinho
FIM
roda "$D13" plano --rodada 1 "$D13/relatorios/susp2.md"
tem "JP13 · 0 achados" "$SAI" "0 achados (nenhum)"
nao_tem "JP13 · S-n sem colchetes não avisa" "$SAI" "(achado fora do formato:"
D13B=$(nova_tarefa jp13b)
cat >"$D13B/relatorios/susp3.md" <<'FIM'
ACHADOS: nenhum
SUSPEITAS:
1. **[S-1]** ALTO · dados — sem número de confiança
S-2 MÉDIO · contrato
FIM
roda "$D13B" plano --rodada 1 "$D13B/relatorios/susp3.md"
nao_tem "JP13 · S-n não avisa nem sem o número de confiança que o seguraria" "$SAI" "(achado fora do formato:"

# JP14 · cabeçalho candidato com confiança abaixo de 7 (depois da declaração, para só a confiança segurar o aviso)
D14=$(nova_tarefa jp14)
cat >"$D14/relatorios/incerto.md" <<'FIM'
ACHADOS: nenhum
### D-1 (ALTO) algo incerto · confiança 4
FIM
roda "$D14" plano --rodada 1 "$D14/relatorios/incerto.md"
nao_tem "JP14 · confiança 4 é suspeita pelo contrato: sem aviso" "$SAI" "(achado fora do formato:"
D14B=$(nova_tarefa jp14b)
cat >"$D14B/relatorios/seguro.md" <<'FIM'
ACHADOS: nenhum
### D-1 (ALTO) algo certo · confiança 7
FIM
roda "$D14B" plano --rodada 1 "$D14B/relatorios/seguro.md"
tem "JP14 · confiança 7 já é achado: avisa" "$SAI" "- relatorios/seguro.md:2 (achado fora do formato: 1 linha(s)"

# JP15 · "sem achados" no meio da linha não é declaração; cabeçalho fora do formato noutra linha
D15=$(nova_tarefa jp15)
cat >"$D15/relatorios/meio.md" <<'FIM'
1. segurança — sem achados nesta lente
2. dados — achei um problema
### D-1 (ALTO) a soma duplica
a soma do pedido duplica quando o item volta
FIM
roda "$D15" plano --rodada 1 "$D15/relatorios/meio.md"
tem "JP15 · avisa o cabeçalho fora do formato" "$SAI" "- relatorios/meio.md:3 (achado fora do formato: 1 linha(s)"
D15B=$(nova_tarefa jp15b)
cat >"$D15B/relatorios/complemento.md" <<'FIM'
Sem achados nesta lente.
### D-1 (ALTO) a soma duplica
FIM
roda "$D15B" plano --rodada 1 "$D15B/relatorios/complemento.md"
tem "JP15 · 'Sem achados nesta lente.' no começo da linha também não é declaração" "$SAI" "- relatorios/complemento.md:2 (achado fora do formato: 1 linha(s)"

D15C=$(nova_tarefa jp15c)
cat >"$D15C/relatorios/antes-da-frase.md" <<'FIM'
### D-1 (ALTO) a soma duplica
Sem achados nesta lente.
FIM
roda "$D15C" plano --rodada 1 "$D15C/relatorios/antes-da-frase.md"
tem "JP15 · frase com complemento depois do cabeçalho não suprime nada" "$SAI" "- relatorios/antes-da-frase.md:1 (achado fora do formato: 1 linha(s)"

# JP16 · declaração de zero e cabeçalho depois dela
D16=$(nova_tarefa jp16)
cat >"$D16/relatorios/depois.md" <<'FIM'
ACHADOS: nenhum
### D-1 (ALTO) a soma duplica
FIM
roda "$D16" plano --rodada 1 "$D16/relatorios/depois.md"
tem "JP16 · cabeçalho depois da declaração conta" "$SAI" "- relatorios/depois.md:2 (achado fora do formato: 1 linha(s)"

# JP17 · Cenário: solto em hipótese de pre-mortem
D17=$(nova_tarefa jp17)
cat >"$D17/relatorios/cenario.md" <<'FIM'
HIPÓTESES (pre-mortem):
1. Cenário: usuário cola o texto com caracteres estranhos — coberta em T2
Cenário: x
Correção sugerida: nenhuma
ACHADOS: nenhum
FIM
roda "$D17" plano --rodada 1 "$D17/relatorios/cenario.md"
nao_tem "JP17 · Cenário:, Prova: e Correção sugerida: soltos não são evidência" "$SAI" "(achado fora do formato:"

# JP18 · a 1ª linha traz a contagem de não contados (classe nova mais a antiga)
D18=$(nova_tarefa jp18)
cp "$D1/relatorios/fora.md" "$D18/relatorios/fora.md"
printf 'Onde: z.sh:1\n' >"$D18/relatorios/onde.md"
roda "$D18" plano --rodada 1 "$D18/relatorios/fora.md" "$D18/relatorios/onde.md"
eq "JP18 · a 1ª linha termina com a contagem, e o começo é o de hoje" "JULGAR rodada 1 · plano · 0 achados (nenhum) · 0 grupos · detalhe em $D18/achados.md · 2 não contado(s): ver a lista abaixo" "$(primeira_linha "$SAI")"
tem "JP18 · a classe antiga continua na lista" "$SAI" "- relatorios/onde.md:1 (Onde sem cabeçalho [A-n] reconhecido)"

# JP19 · a 1ª linha sem lista é a de hoje
D19=$(nova_tarefa jp19)
cp "$D3/relatorios/adv.md" "$D19/relatorios/adv.md"
roda "$D19" plano --rodada 1 "$D19/relatorios/adv.md"
eq "JP19 · sem lista, a 1ª linha é a de hoje" "JULGAR rodada 1 · plano · 0 achados (nenhum) · 0 grupos · detalhe em $D19/achados.md" "$(primeira_linha "$SAI")"

# J-a e J-b · a pasta errada (a de trabalho, ou a tarefas/) recusa com 2 antes de gravar o achados.md
JW=$T/jp-trabalho
mkdir -p "$JW/tarefas/2026-01-01-uma/relatorios"
printf '# Registro\n' >"$JW/tarefas/2026-01-01-uma/registro.md"
printf '[A-1] ALTO · segurança · confiança 8\nOnde: x.js:1\nDefeito: falta checar o dono\n' >"$JW/rel.md"
JWR=$(cd -- "$JW" && pwd -P)
roda "$JW" plano --rodada 1 "$JW/rel.md"
eq "J-a · pasta de trabalho: código 2" 2 "$RC"
eq "J-a · pasta de trabalho: stdout vazio" "" "$SAI"
eq "J-a · pasta de trabalho: a mensagem da trava" "julgar-pre.sh: $JWR é pasta de trabalho (tem tarefas/); <pasta-da-tarefa> pede a pasta da tarefa, $JWR/tarefas/<tarefa>" "$ERR"
eq "J-a · pasta de trabalho: sem achados.md" nao "$([ -e "$JW/achados.md" ] && echo sim || echo nao)"
roda "$JW/" plano --rodada 1 "$JW/rel.md"
eq "J-a · pasta de trabalho com barra final: código 2" 2 "$RC"
eq "J-a · pasta de trabalho com barra final: sem achados.md" nao "$([ -e "$JW/achados.md" ] && echo sim || echo nao)"
roda "$JW/tarefas/." plano --rodada 1 "$JW/rel.md"
eq "J-b · tarefas/ por caminho com '.': código 2" 2 "$RC"
eq "J-b · tarefas/ por caminho com '.': stdout vazio" "" "$SAI"
eq "J-b · tarefas/ por caminho com '.': mensagem com o caminho resolvido" "julgar-pre.sh: $JWR/tarefas é a pasta tarefas/; <pasta-da-tarefa> pede uma tarefa dentro dela, $JWR/tarefas/<tarefa>" "$ERR"
eq "J-b · tarefas/ por caminho com '.': sem achados.md" nao "$([ -e "$JW/tarefas/achados.md" ] && echo sim || echo nao)"
roda "$JW/tarefas/2026-01-01-uma/../../tarefas" plano --rodada 1 "$JW/rel.md"
eq "J-b · tarefas/ por caminho com '..': código 2" 2 "$RC"
ln -s "$JW/tarefas" "$T/atalho-tarefas"
roda "$T/atalho-tarefas" plano --rodada 1 "$JW/rel.md"
eq "J-b · tarefas/ por link simbólico com outro nome: código 2" 2 "$RC"
eq "J-b · tarefas/ por link simbólico: sem achados.md" nao "$([ -e "$JW/tarefas/achados.md" ] && echo sim || echo nao)"
roda "$JW/tarefas/2026-01-01-uma" plano --rodada 1 "$JW/rel.md"
eq "J-a · controle: a pasta da tarefa dentro de tarefas/ segue como hoje" 0 "$RC"
tem "J-a · controle: o achado entra no achados.md da tarefa" "$(cat "$JW/tarefas/2026-01-01-uma/achados.md")" "A-1"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
