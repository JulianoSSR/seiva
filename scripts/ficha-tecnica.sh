#!/usr/bin/env bash
# Fichas e trechos para os revisores: o que eles precisam do código, sem o arquivo inteiro e sem modelo nenhum.
#
# Uso: ficha-tecnica.sh <pasta-da-tarefa> [--de <relatorio>] [arquivo...]
#   arquivo   gera <pasta>/fichas/<caminho com / trocado por __>.md: linhas, hash, o que importa, o que exporta,
#             assinaturas (função, classe, rota, seção de markdown) e linhas-chave (SQL, transação, variável de
#             ambiente, segredo, TODO), cada uma com o número da linha
#   --de      lê as citações caminho:linha e caminho:início-fim do relatório (o do batedor, em geral), gera a ficha de
#             cada arquivo citado e grava <pasta>/trechos.md com cada citação e 10 linhas antes e depois, juntando os
#             intervalos que se encostam no mesmo arquivo
#   Caminho relativo é relativo à raiz do repositório (git rev-parse --show-toplevel), ou à pasta atual fora de git; rode
#   da raiz do projeto. Caminho absoluto, `..` ou link que saia dessa raiz não é lido e aparece como pulado.
#
# Extração por expressão regular (grep), sem tree-sitter nem modelo: assinatura em formato incomum pode faltar, e a
# ficha diz isso no topo. Tetos: 40 linhas por seção, 160 caracteres por linha, 30 arquivos e 400 linhas de trecho.
#
# Saída: uma linha "FICHAS <n> · TRECHOS <i> intervalos, <l> linhas · <pasta>" e, se houver, as citações puladas.
# Como o enxugar, só grava em pasta ignorada pelo git e com a máscara de segredo funcionando: senão "RECUSA <motivo>"
# e código 125, sem gravar nada. Uso errado sai com 2.
set -uo pipefail
umask 077
export LC_ALL=C

recusa() { printf 'RECUSA %s\n' "$1"; exit 125; }
uso() { echo "uso: ficha-tecnica.sh <pasta-da-tarefa> [--de <relatorio>] [arquivo...]" >&2; exit 2; }

aqui=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || recusa "não achei a pasta do script"
[ -r "$aqui/segredos.sh" ] || recusa "segredos.sh não está ao lado do ficha-tecnica.sh"
# shellcheck disable=SC1091
. "$aqui/segredos.sh"

[ "$#" -ge 2 ] || uso
pasta=${1%/}
shift
relatorio=""
arquivos=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --de)
      [ "$#" -ge 2 ] || uso
      relatorio=$2
      shift 2
      ;;
    -*) uso ;;
    *)
      arquivos+=("$1")
      shift
      ;;
  esac
done
[ -d "$pasta" ] || recusa "a pasta da tarefa não existe: $pasta"
pasta_ignorada "$pasta" || recusa "a pasta $pasta não está ignorada pelo git (ou não deu para conferir); nada foi gravado"
[ "$(printf 'x\n' | mascarar 2>/dev/null)" = x ] || recusa "a máscara de segredo não funciona aqui (falta sed GNU?); nada foi gravado"
[ -z "$relatorio" ] || [ -r "$relatorio" ] || recusa "não consigo ler o relatório: $relatorio"

raiz=$(git rev-parse --show-toplevel 2>/dev/null) || raiz=$(pwd -P)
raiz=$(cd -- "$raiz" 2>/dev/null && pwd -P) || recusa "não consegui resolver a raiz do repositório"
# Caminho citado -> caminho real do arquivo, só se ficar dentro da raiz. A citação vem de relatório escrito por outro
# modelo: caminho absoluto de fora, "..", ou link que sai da raiz não é lido. Código 1: não existe; 3: fora da raiz.
resolve() {
  local c d
  case $1 in /*) c=$1 ;; *) c=$raiz/${1#./} ;; esac
  [ -f "$c" ] || return 1
  d=$(cd -- "$(dirname -- "$c")" 2>/dev/null && pwd -P) || return 1
  c=$d/${c##*/}
  if [ -L "$c" ]; then
    c=$(realpath -- "$c" 2>/dev/null || readlink -f -- "$c" 2>/dev/null) || return 3
  fi
  case $c in "$raiz"/*) printf '%s\n' "$c" ;; *) return 3 ;; esac
}
# O arquivo com cada linha de chave privada, do BEGIN ao END, trocada por <OMITIDO chave privada>, sem mudar a
# numeração. Vem antes de cortar: o mascarar trabalha com estado, e um corte no meio da chave deixaria o corpo dela
# sem o BEGIN, em claro (ou um BEGIN sem END engoliria o resto da saída).
sem_chave() {
  awk '
    dentro { if ($0 ~ /-----END [A-Z ]*PRIVATE KEY[A-Z ]*-----/) dentro = 0; print "<OMITIDO chave privada>"; next }
    /-----BEGIN [A-Z ]*PRIVATE KEY[A-Z ]*-----/ { dentro = ($0 !~ /-----END [A-Z ]*PRIVATE KEY[A-Z ]*-----/); print "<OMITIDO chave privada>"; next }
    { print }' "$1"
}
fichas=$pasta/fichas
mkdir -p -- "$fichas" || recusa "não deu para criar $fichas"
pasta_ignorada "$fichas" || recusa "$fichas não está ignorada pelo git (link simbólico?); nada foi gravado"

secao() { # secao <título> <arquivo> <regex ERE>
  local r
  r=$(sem_chave "$2" | grep -nE -- "$3" 2>/dev/null | cut -c1-160 | head -n 41)
  [ -n "$r" ] || return 0
  printf '\n## %s\n' "$1"
  printf '%s\n' "$r" | head -n 40
  [ "$(printf '%s\n' "$r" | wc -l)" -le 40 ] || echo "(mais linhas: cortado em 40)"
}

ficha() { # ficha <caminho como citado>
  local nome f destino imp exp ass chave
  nome=${1#./}
  f=$(resolve "$nome") || return $?
  destino="$fichas/$(printf '%s' "$nome" | sed 's#^/##; s#/#__#g').md"
  case $f in
    *.js | *.jsx | *.ts | *.tsx | *.mjs | *.cjs)
      imp='^[[:space:]]*import[[:space:]]|require\('
      exp='^[[:space:]]*export[[:space:]]|module\.exports|^[[:space:]]*exports\.[A-Za-z_$]+[[:space:]]*='
      ass='^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?function\b|^[[:space:]]*(export[[:space:]]+)?(abstract[[:space:]]+)?class[[:space:]]|^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*(async[[:space:]]*)?(\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*=>|^[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*\.(get|post|put|patch|delete|use|all)\([[:space:]]*["'"'"'`/]'
      ;;
    *.py)
      imp='^[[:space:]]*(import|from)[[:space:]]'
      exp='^__all__'
      ass='^[[:space:]]*(async[[:space:]]+)?def[[:space:]]|^[[:space:]]*class[[:space:]]|^[[:space:]]*@[A-Za-z_]'
      ;;
    *.sh | *.bash)
      imp='^[[:space:]]*(\.|source)[[:space:]]'
      exp='^[[:space:]]*export[[:space:]]'
      ass='^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)'
      ;;
    *.go)
      imp='^import|^[[:space:]]+"[^"]+"$'
      exp='^func[[:space:]]+(\([^)]*\)[[:space:]]*)?[A-Z]|^type[[:space:]]+[A-Z]'
      ass='^func[[:space:]]|^type[[:space:]]'
      ;;
    *.rs)
      imp='^[[:space:]]*use[[:space:]]'
      exp='^[[:space:]]*pub[[:space:]]'
      ass='^[[:space:]]*(pub[^ ]*[[:space:]]+)?(async[[:space:]]+)?fn[[:space:]]|^[[:space:]]*(pub[^ ]*[[:space:]]+)?(struct|enum|trait|impl|mod)\b'
      ;;
    *.java | *.kt | *.cs)
      imp='^[[:space:]]*(import|using|package)[[:space:]]'
      exp='^[[:space:]]*public[[:space:]]'
      ass='^[[:space:]]*((public|private|protected|internal|static|final|abstract|override|suspend|open)[[:space:]]+)*(class|interface|enum|record|fun|void|[A-Z][A-Za-z0-9_<>,]*)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[({]'
      ;;
    *.rb)
      imp='^[[:space:]]*require'
      exp=''
      ass='^[[:space:]]*(def|class|module)[[:space:]]'
      ;;
    *.php)
      imp='^[[:space:]]*(use|require|include)'
      exp=''
      ass='^[[:space:]]*((public|private|protected|static|abstract|final)[[:space:]]+)*(function|class|interface|trait)[[:space:]]'
      ;;
    *.md | *.markdown)
      imp=''
      exp=''
      ass='^#{1,4}[[:space:]]'
      ;;
    *.sql)
      imp=''
      exp=''
      ass='^[[:space:]]*(CREATE|ALTER|DROP|GRANT|REVOKE|COMMENT)\b'
      ;;
    *)
      imp='^[[:space:]]*(import|require|include|use)[[:space:]]'
      exp='^[[:space:]]*export[[:space:]]'
      ass='^[[:space:]]*(function|def|class|fn|func)[[:space:]]'
      ;;
  esac
  chave='process\.env|os\.environ|getenv|\b(BEGIN|COMMIT|ROLLBACK)\b|\b(SELECT|INSERT|UPDATE|DELETE)[[:space:]]|TODO|FIXME|XXX|([Ss]ecret|[Tt]oken|[Pp]assword|[Ss]enha|[Aa]pi_?[Kk]ey|SECRET|TOKEN|PASSWORD|SENHA|_KEY)'
  {
    printf '# Ficha: %s\n\n' "$nome"
    printf '%s linhas · sha256 %s · gerada em %s por scripts/ficha-tecnica.sh, por expressão regular e sem modelo: pode faltar assinatura em formato incomum. Para ler mais, abra só o intervalo de linhas (nunca o arquivo inteiro).\n' \
      "$(grep -c '' "$f")" "$( (sha256sum <"$f" 2>/dev/null || shasum -a 256 <"$f") | cut -c1-12)" "$(date '+%Y-%m-%d %H:%M')"
    [ -z "$imp" ] || secao "Importa" "$f" "$imp"
    [ -z "$exp" ] || secao "Exporta" "$f" "$exp"
    case $f in *.md | *.markdown) secao "Seções" "$f" "$ass" ;; *) secao "Assinaturas" "$f" "$ass" ;; esac
    case $f in *.md | *.markdown) ;; *) secao "Linhas-chave" "$f" "$chave" ;; esac
  } | mascarar >"$destino.tmp" && mv -f "$destino.tmp" "$destino" || { rm -f "$destino.tmp"; return 2; }
  return 0
}

n_fichas=0
puladas=()
vistos=" "
gera() {
  case $vistos in *" $1 "*) return 0 ;; esac
  vistos+="$1 "
  [ "$n_fichas" -lt 30 ] || { puladas+=("$1 (teto de 30 arquivos)"); return 0; }
  ficha "$1"
  case $? in
    0) n_fichas=$((n_fichas + 1)) ;;
    3) puladas+=("$1 (fora do repositório: só se lê dentro de $raiz)") ;;
    *) puladas+=("$1 (não existe a partir de $raiz)") ;;
  esac
}
for a in ${arquivos[@]+"${arquivos[@]}"}; do gera "$a"; done

intervalos=0
linhas=0
if [ -n "$relatorio" ]; then
  # Citações: caminho com extensão, dois-pontos, linha e, opcional, -fim. Uma por linha: arquivo início fim.
  cits=$(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?' "$relatorio" |
    awk -F: '{ split($2, r, "-"); i = r[1] + 0; f = (r[2] == "" ? i : r[2] + 0); if (f < i) f = i; print $1, i, f }' | sort -u)
  destino=$pasta/trechos.md
  {
    printf '# Trechos citados em %s\n\n' "$relatorio"
    printf 'Gerado por scripts/ficha-tecnica.sh: cada citação com 10 linhas antes e depois, intervalos do mesmo arquivo juntados. Segredo de padrão conhecido sai mascarado. Para ler além disto, abra só o intervalo de que precisa.\n'
    printf '%s\n' "$cits" | awk 'NF == 3' | sort -k1,1 -k2,2n | while read -r nome i f; do
      arq=$(resolve "$nome")
      case $? in
        0) echo "$nome $i $f" ;;
        3) echo "PULADA $nome:$i (fora do repositório: só se lê dentro de $raiz)" ;;
        *) echo "PULADA $nome:$i (não existe a partir de $raiz)" ;;
      esac
    done | awk -v teto=400 '
      /^PULADA / { print > "/dev/stderr"; next }
      { a = $1; i = $2 - 10; if (i < 1) i = 1; f = $3 + 10
        if (a == cur && i <= fim + 1) { if (f > fim) fim = f; next }
        if (cur != "") print cur, ini, fim
        cur = a; ini = i; fim = f }
      END { if (cur != "") print cur, ini, fim }' 2>"$pasta/.puladas" | while read -r nome i f; do
      arq=$(resolve "$nome")
      total=$(grep -c '' "$arq")
      [ "$f" -le "$total" ] || f=$total
      [ "$i" -le "$f" ] || continue
      printf '\n## %s:%s-%s\n```\n' "$nome" "$i" "$f"
      sem_chave "$arq" | awk -v i="$i" -v f="$f" 'NR >= i && NR <= f { printf "%5d  %s\n", NR, substr($0, 1, 200) } NR > f { exit }' 
      printf '```\n'
    done
  } | awk -v teto=400 '/^ *[0-9]+  / { if (++n > teto) { if (!avisou) { print "(teto de 400 linhas de trecho: o resto foi cortado)"; avisou = 1 } next } } { print }' |
    mascarar >"$destino.tmp" && mv -f "$destino.tmp" "$destino" || { rm -f "$destino.tmp"; recusa "a máscara falhou ao gravar $destino; nada foi gravado"; }
  intervalos=$(grep -c '^## ' "$destino")
  linhas=$(grep -cE '^ *[0-9]+  ' "$destino")
  while read -r p; do
    [ -n "$p" ] && puladas+=("${p#PULADA }")
  done <"$pasta/.puladas"
  rm -f "$pasta/.puladas"
  for nome in $(printf '%s\n' "$cits" | awk 'NF == 3 { print $1 }' | sort -u); do gera "$nome"; done
fi

printf 'FICHAS %s · TRECHOS %s intervalos, %s linhas · %s\n' "$n_fichas" "$intervalos" "$linhas" "$pasta"
if [ "${#puladas[@]}" -gt 0 ]; then
  printf 'puladas (%s): ' "${#puladas[@]}"
  printf '%s\n' "${puladas[@]}" | head -n 5 | paste -sd ';' -
fi
exit 0
