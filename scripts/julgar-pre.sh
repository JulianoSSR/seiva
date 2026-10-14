#!/usr/bin/env bash
# Pré-julgamento mecânico dos achados de uma rodada, antes de o orquestrador julgar.
#
# Uso: julgar-pre.sh <pasta-da-tarefa> <plano|codigo> [--rodada <n>] <relatorio...>
#   Lê os achados no formato de referencias/contratos.md ([A-n] SEVERIDADE · lente · confiança c / Onde: / Defeito:),
#   com tolerância: severidade em qualquer caixa, prefixo antes do [A-n] ("1)", "Achado", negrito, crase). O que não
#   fecha (cabeçalho sem severidade, bloco sem Onde nem Defeito, Onde sem cabeçalho) não conta e sai listado, com a linha.
#   dá a cada um um ID da tarefa (continua do maior A-n de achados.md, para o ID ficar estável entre rodadas e portões),
#   agrupa os que apontam o mesmo arquivo a até 3 linhas de distância, ou a mesma seção do plano, e acrescenta em
#   achados.md uma seção "Rodada <n> · <portão>" com uma linha por achado e a origem (relatório:linha e ID local).
#   Linhas "A-<n> → mitigado em <arquivo:linha>" ou "A-<n> → aberto: <motivo>" no relatório são referências a achado
#   já julgado: não viram achado novo, entram como verificação de uma linha.
#   --rodada  número da rodada; sem ele, uma a mais que as seções do mesmo portão em achados.md.
#
# Saída: só a tabela, uma linha por achado, da severidade maior para a menor, com os grupos e as referências. O detalhe
# fica no relatório e em achados.md. Relatório já lido (mesmo caminho e mesmo hash) é pulado, e isso é dito.
# Não julga: agrupar por causa e dar veredito continua sendo do orquestrador. Uso errado sai com 2.
set -uo pipefail
export LC_ALL=C
umask 077

# Máscara de segredo na saída e no achados.md, quando o segredos.sh e o sed GNU estão aqui; sem eles, a linha diz.
mascara=0
case $0 in */*) aqui=${0%/*} ;; *) aqui=. ;; esac
if [ -r "$aqui/segredos.sh" ]; then
  # shellcheck disable=SC1091
  . "$aqui/segredos.sh"
  [ "$(printf 'x\n' | mascarar 2>/dev/null)" = x ] && mascara=1
fi

uso() { echo "uso: julgar-pre.sh <pasta-da-tarefa> <plano|codigo> [--rodada <n>] <relatorio...>" >&2; exit 2; }
[ "$#" -ge 3 ] || uso
pasta=${1%/}
portao=$2
shift 2
case $portao in plano | codigo) ;; *) uso ;; esac
rodada=""
if [ "${1:-}" = --rodada ]; then
  [ "$#" -ge 3 ] || uso
  rodada=$2
  shift 2
  case $rodada in '' | *[!0-9]*) uso ;; esac
fi
[ "$#" -ge 1 ] || uso
[ -d "$pasta" ] || { echo "a pasta não existe: $pasta" >&2; exit 2; }
ach=$pasta/achados.md
[ -f "$ach" ] || printf '# Achados — %s\n' "${pasta##*/}" >"$ach"

hash12() { (sha256sum <"$1" 2>/dev/null || shasum -a 256 <"$1") | cut -c1-12; }
rel() { case $1 in "$pasta"/*) printf '%s\n' "${1#"$pasta"/}" ;; *) printf '%s\n' "$1" ;; esac; }

tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp" "$tmp.ref" "$tmp.ord" "$tmp.sem" "$tmp.r2" "$tmp.m" "$tmp.x" "$tmp.ref.m" "$tmp.ref.x"' EXIT
: >"$tmp.ref"
lidos=""
pulados=""
for r in "$@"; do
  [ -r "$r" ] || { echo "não consigo ler: $r" >&2; exit 2; }
  h=$(hash12 "$r")
  nome=$(rel "$r")
  if grep -qF -- "$nome@$h" "$ach"; then
    pulados+="${pulados:+, }$nome"
    continue
  fi
  lidos+=" $nome@$h"
  # Um achado por bloco: cabeçalho [A-n] SEVERIDADE, depois Onde e Defeito. Saída em TSV.
  awk -v src="$nome" '
    function limpa(s) { gsub(/\t/, " ", s); gsub(/^[[:space:]*_`-]+|[[:space:]*_`]+$/, "", s); return s }
    # Bloco sem Onde nem Defeito não é achado (em geral, uma hipótese que cita o [A-n]): vai para o aviso, não some.
    function sai() {
      if (sev != "") {
        if (onde == "" && defeito == "") print "SEM\t" src ":" lin " [" lid "] (cabeçalho sem Onde nem Defeito)" > "/dev/stderr"
        else printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", src, lid, sev, lente, conf, (onde == "" ? "?" : onde), (defeito == "" ? "?" : defeito), lin
      }
      sev = ""
    }
    # Severidade logo depois do [A-n], em qualquer caixa e com ou sem acento (o locale é C: tolower só baixa o ASCII).
    function sevde(s,   l) {
      sub(/^[^A-Za-z]*/, "", s); l = tolower(s)
      if (l ~ /^cr(i|í|Í)tico/) return "CRÍTICO"
      if (l ~ /^alto/) return "ALTO"
      if (l ~ /^m(e|é|É)dio/) return "MÉDIO"
      if (l ~ /^baixo/) return "BAIXO"
      return ""
    }
    # Cabeçalho: [A-n] em qualquer ponto da linha ("1) [A-1]", "Achado [A-1] —", "**[A-1]**"), seguido da severidade.
    /\[A-[0-9]+\]/ {
      match($0, /\[A-[0-9]+\]/); id0 = substr($0, RSTART + 1, RLENGTH - 2); resto0 = substr($0, RSTART + RLENGTH)
      s0 = sevde(resto0)
      if (s0 != "") {
        sai(); lid = id0; resto = resto0; sev = s0
        n = split(resto, p, "·"); lente = (n >= 2 ? limpa(p[2]) : "?")
        conf = "?"; if (match(resto, /confian(c|ç)a[[:space:]]*[0-9]+/)) { c = substr(resto, RSTART, RLENGTH); gsub(/[^0-9]/, "", c); conf = c }
        onde = ""; defeito = ""; lin = FNR
        next
      }
      # [A-n] no começo da linha, sem severidade que se reconheça: não vira achado, mas não some.
      if ($0 ~ /^[^A-Za-z]*\[A-[0-9]+\]/) { sai(); print "SEM\t" src ":" FNR " [" id0 "] (sem severidade reconhecida)" > "/dev/stderr"; next }
      # [A-n] no meio do texto, sem severidade: menção, não cabeçalho.
    }
    # Onde de bloco aberto vale uma vez. Um segundo Onde, ou um Onde sem bloco, é de cabeçalho que não foi reconhecido:
    # fecha o bloco aberto (que fica com o próprio lugar) e é avisado.
    /^[[:space:]*_-]*Onde:/ {
      if (sev != "" && onde == "") { sub(/^[^:]*:/, ""); onde = limpa($0); next }
      sai(); print "SEM\t" src ":" FNR " (Onde sem cabeçalho [A-n] reconhecido)" > "/dev/stderr"; next
    }
    /^[[:space:]*_-]*Defeito:/ { if (sev != "" && defeito == "") { sub(/^[^:]*:/, ""); defeito = limpa($0) } next }
    # Referência a achado já julgado, sozinha na linha ou logo depois do título "REFERÊNCIAS:" do molde do adversário.
    /^[[:space:]*_-]*([Rr][Ee][Ff][Ee][Rr](Ê|ê|E|e)[Nn][Cc][Ii][Aa][Ss][[:space:]*_]*:[[:space:]*_-]*)?A-[0-9]+[[:space:]]*(→|->)[[:space:]]*([Mm]itigado|[Aa]berto)/ {
      l = $0; sub(/^[[:space:]*_-]*[Rr][Ee][Ff][Ee][Rr][^:]*:/, "", l)
      print "REF\t" limpa(l) "\t" src > "/dev/stderr"; next
    }
    END { sai() }
  ' "$r" >>"$tmp" 2>>"$tmp.ref"
done

if [ -z "$lidos" ]; then
  echo "JULGAR nada novo: todos os relatórios já foram lidos (${pulados})"
  exit 0
fi

# Separa as referências dos cabeçalhos sem severidade que o awk mandou para o mesmo arquivo.
grep '^SEM' "$tmp.ref" >"$tmp.sem"
grep '^REF' "$tmp.ref" >"$tmp.r2"
mv -f "$tmp.r2" "$tmp.ref"

# Máscara campo a campo, antes de montar as linhas: cada texto do revisor (lente, Onde, Defeito, referência) numa linha
# só, e a linha de BEGIN ou END de chave privada trocada antes, para a regra de chave (que tem estado) não atravessar
# campos e o "_KEY até o fim da linha" não comer a origem nem os achados seguintes.
mascara_coluna() { # mascara_coluna <arquivo TSV> <coluna>...
  local f=$1 m=$1.m
  shift
  [ "$mascara" = 1 ] && [ -s "$f" ] || return 0
  awk -F'\t' -v cols="$*" 'BEGIN { n = split(cols, c, " ") } { for (i = 1; i <= n; i++) print $(c[i]) }' "$f" |
    awk '/-----(BEGIN|END) [A-Z ]*PRIVATE KEY/ { print "<OMITIDO chave privada>"; next } { print }' | mascarar >"$m" || return 1
  [ "$(grep -c '' "$m")" -eq $(($(grep -c '' "$f") * $#)) ] || return 1
  awk -F'\t' -v cols="$*" 'BEGIN { OFS = "\t"; n = split(cols, c, " ") }
    NR == FNR { v[NR] = $0; next }
    { for (i = 1; i <= n; i++) $(c[i]) = v[(FNR - 1) * n + i]; print }' "$m" "$f" >"$f.x" && mv -f "$f.x" "$f"
  rm -f "$m"
}
mascara_coluna "$tmp" 4 6 7 && mascara_coluna "$tmp.ref" 2 ||
  { echo "a máscara de segredo falhou ou mudou o número de linhas; nada foi gravado" >&2; exit 2; }

# Maior ID só das linhas de achado que este script escreveu ("- A-n · "): um A-9999 citado num Defeito não conta.
maior=$(grep -oE '^- A-[0-9]+ · ' "$ach" | grep -oE '[0-9]+' | sort -n | tail -n 1)
maior=${maior:-0}
[ -n "$rodada" ] || rodada=$(($(grep -cE "^## Rodada [0-9]+ · $portao" "$ach") + 1))

# IDs da tarefa, chave de grupo (arquivo e linha, ou o texto do Onde) e ordem por severidade.
awk -F'\t' -v base="$maior" '
  BEGIN { ord["CRÍTICO"] = 1; ord["ALTO"] = 2; ord["MÉDIO"] = 3; ord["BAIXO"] = 4 }
  {
    id = "A-" (base + NR)
    arq = ""; ln = 0
    if (match($6, /[A-Za-z0-9_.\/-]+\.[A-Za-z0-9]+:[0-9]+/)) { c = substr($6, RSTART, RLENGTH); k = split(c, q, ":"); arq = q[1]; ln = q[2] + 0 }
    else { arq = tolower($6); gsub(/[[:space:]]+/, " ", arq) }
    printf "%s\t%s\t%09d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", arq, id, ln, ord[$3], $3, $4, $5, $6, $7, $1, $2, $8
  }' "$tmp" | sort -t "$(printf '\t')" -k1,1 -k3,3n |
  awk -F'\t' '
    { if ($1 == pa && $1 != "" && $1 != "?" && ($3 - pl) <= 3) g[NR] = gc; else g[NR] = ++gc; pa = $1; pl = $3; tam[g[NR]]++; l[NR] = $0 }
    END { for (i = 1; i <= NR; i++) { nm = (tam[g[i]] > 1 ? "G-" g[i] : "—"); print l[i] "\t" nm } }' |
  sort -t "$(printf '\t')" -k4,4n -k2.3,2n >"$tmp.ord"

# Renumera os grupos na ordem em que aparecem, para a tabela ler G-1, G-2...
awk -F'\t' 'BEGIN { OFS = "\t" } { if ($13 != "—") { if (!($13 in m)) m[$13] = "G-" (++n); $13 = m[$13] } print }' "$tmp.ord" >"$tmp" && mv -f "$tmp" "$tmp.ord"

total=$(grep -c '' "$tmp.ord")
resumo=$(awk -F'\t' '{ c[$5]++; if ($7 != "?" && $7 + 0 < 7) s++ } END {
  o = ""; split("CRÍTICO ALTO MÉDIO BAIXO", k, " "); for (i = 1; i <= 4; i++) if (c[k[i]]) o = o (o == "" ? "" : ", ") c[k[i]] " " k[i]
  printf "%s%s", o, (s ? "; " s " suspeita" (s > 1 ? "s" : "") " (confiança abaixo de 7)" : "") }' "$tmp.ord")
grupos=$(awk -F'\t' '$13 != "—" { g[$13] = 1 } END { print length(g) + 0 }' "$tmp.ord")

# O registro de lidos fica fora da máscara: é por ele que um relatório já lido é reconhecido.
printf '\n## Rodada %s · %s · %s\n<!-- lidos:%s -->\n' "$rodada" "$portao" "$(date '+%Y-%m-%d %H:%M')" "$lidos" >>"$ach"
{
  awk -F'\t' '{ printf "- %s · %s · %s · c%s · %s · %s · %s · origem %s:%s [%s]\n", $2, $5, $6, $7, $8, $13, $9, $10, $12, $11 }' "$tmp.ord"
  if [ -s "$tmp.ref" ]; then
    echo "Referências a achados já julgados:"
    awk -F'\t' '{ printf "- %s (%s)\n", $2, $3 }' "$tmp.ref"
  fi
  if [ -s "$tmp.sem" ]; then
    echo "Não contados: cabeçalho [A-n] sem severidade reconhecida, sem Onde nem Defeito, ou Onde solto (abra o relatório e julgue à mão):"
    sed 's/^SEM\t/- /' "$tmp.sem"
  fi
  echo "Vereditos (uma linha por achado: A-n → confirmado | falso: motivo | incerto · rota · agrupado com A-m):"
} >>"$ach"

{
printf 'JULGAR rodada %s · %s · %s achado%s (%s) · %s grupo%s · detalhe em %s\n' "$rodada" "$portao" "$total" \
  "$([ "$total" -eq 1 ] || echo s)" "${resumo:-nenhum}" "$grupos" "$([ "$grupos" -eq 1 ] || echo s)" "$ach"
[ -z "$pulados" ] || echo "já lidos antes, pulados: $pulados"
if [ "$total" -gt 0 ]; then
  echo "| ID | sev | lente | conf | onde | defeito | grupo |"
  echo "|---|---|---|---|---|---|---|"
  awk -F'\t' '{ d = $9; if (length(d) > 90) d = substr(d, 1, 87) "..."; printf "| %s | %s | %s | %s | %s | %s | %s |\n", $2, $5, $6, $7, $8, d, $13 }' "$tmp.ord"
fi
if [ -s "$tmp.ref" ]; then
  echo "REFERÊNCIAS:"
  awk -F'\t' '{ printf "- %s (%s)\n", $2, $3 }' "$tmp.ref"
fi
if [ -s "$tmp.sem" ]; then
  echo "SEM SEVERIDADE OU SEM CABEÇALHO (não contados; abra o relatório e julgue à mão):"
  sed 's/^SEM\t/- /' "$tmp.sem"
fi
[ "$mascara" = 1 ] || echo "(saída e achados.md sem máscara de segredo: falta o segredos.sh ou o sed GNU)"
}
exit 0
