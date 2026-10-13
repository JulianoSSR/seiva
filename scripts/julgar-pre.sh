#!/usr/bin/env bash
# Pré-julgamento mecânico dos achados de uma rodada, antes de o orquestrador julgar.
#
# Uso: julgar-pre.sh <pasta-da-tarefa> <plano|codigo> [--rodada <n>] <relatorio...>
#   Lê os achados no formato de referencias/contratos.md ([A-n] SEVERIDADE · lente · confiança c / Onde: / Defeito:),
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
trap 'rm -f "$tmp" "$tmp.ref" "$tmp.ord"' EXIT
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
    function sai() {
      if (sev != "") printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", src, lid, sev, lente, conf, (onde == "" ? "?" : onde), (defeito == "" ? "?" : defeito), lin
      sev = ""
    }
    /\[A-[0-9]+\]/ && /(CR(I|Í)TICO|ALTO|M(E|É)DIO|BAIXO)/ {
      sai()
      match($0, /\[A-[0-9]+\]/); lid = substr($0, RSTART + 1, RLENGTH - 2)
      resto = substr($0, RSTART + RLENGTH)
      if (resto ~ /CR(I|Í)TICO/) sev = "CRÍTICO"; else if (resto ~ /ALTO/) sev = "ALTO"
      else if (resto ~ /M(E|É)DIO/) sev = "MÉDIO"; else sev = "BAIXO"
      n = split(resto, p, "·"); lente = (n >= 2 ? limpa(p[2]) : "?")
      conf = "?"; if (match(resto, /confian(c|ç)a[[:space:]]*[0-9]+/)) { c = substr(resto, RSTART, RLENGTH); gsub(/[^0-9]/, "", c); conf = c }
      onde = ""; defeito = ""; lin = FNR
      next
    }
    sev != "" && /^[[:space:]*_-]*Onde:/ { sub(/^[^:]*:/, ""); onde = limpa($0); next }
    sev != "" && /^[[:space:]*_-]*Defeito:/ { sub(/^[^:]*:/, ""); defeito = limpa($0); next }
    /^[[:space:]*_-]*A-[0-9]+[[:space:]]*(→|->)[[:space:]]*(mitigado|aberto)/ { print "REF\t" limpa($0) " (" src ")" > "/dev/stderr"; next }
    END { sai() }
  ' "$r" >>"$tmp" 2>>"$tmp.ref"
done

if [ -z "$lidos" ]; then
  echo "JULGAR nada novo: todos os relatórios já foram lidos (${pulados})"
  exit 0
fi

maior=$(grep -oE '\bA-[0-9]+\b' "$ach" | grep -oE '[0-9]+' | sort -n | tail -n 1)
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

{
  printf '\n## Rodada %s · %s · %s\n' "$rodada" "$portao" "$(date '+%Y-%m-%d %H:%M')"
  printf '<!-- lidos:%s -->\n' "$lidos"
  awk -F'\t' '{ printf "- %s · %s · %s · c%s · %s · %s · %s · origem %s:%s [%s]\n", $2, $5, $6, $7, $8, $13, $9, $10, $12, $11 }' "$tmp.ord"
  if [ -s "$tmp.ref" ]; then
    echo "Referências a achados já julgados:"
    sed 's/^REF\t/- /' "$tmp.ref"
  fi
  echo "Vereditos (uma linha por achado: A-n → confirmado | falso: motivo | incerto · rota · agrupado com A-m):"
} >>"$ach"

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
  sed 's/^REF\t/- /' "$tmp.ref"
fi
exit 0
