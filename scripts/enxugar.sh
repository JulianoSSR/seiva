#!/usr/bin/env bash
# Roda um comando, guarda a saída inteira na pasta da tarefa (com segredo mascarado) e devolve um resumo curto.
# A saída longa fica em arquivo e volta para a conversa só o que cabe em até 51 linhas.
#
# Uso: enxugar.sh <pasta-da-tarefa> -- <comando> [args...]
#
# A 1ª linha do stdout diz o que aconteceu; quem chama lê a 1ª palavra:
#   SAIDA <caminho> · <n> linhas · código <rc> · <json|texto>
#       O comando rodou. O enxugar sai com o código dele. Seguem até 50 linhas de resumo.
#   RECUSA <motivo>
#       O comando NÃO rodou e nada foi gravado. Sai com 125.
#   DESCARTE <motivo> · o comando rodou com código <rc>
#       A máscara falhou no meio e o arquivo foi apagado. O comando já rodou: não rode de novo. Sai com 125.
# 125 é o código do próprio enxugar (a mesma convenção do env e do timeout). Se o comando embrulhado
# sair com 125, a 1ª linha (SAIDA) desfaz a dúvida.
#
# Arquivo: <pasta>/saidas/<AAAAMMDD-HHMMSS>-<nome do comando>-XXXXXX, modo 600. stdout e stderr vão juntos.
# Só grava em pasta ignorada pelo git (ou fora de repositório) e só com a máscara de segredo funcionando.
# Precisa de sed GNU (a máscara): sem ele, recusa. Sem jq ou sem timeout, o resumo vai como texto.
# Sem limite de tempo para o comando embrulhado: quem quer limite escreve `-- timeout <s> <comando>`.
# O saidas/ não tem limpeza automática.
set -uo pipefail
umask 077

recusa() { printf 'RECUSA %s\n' "$1"; exit 125; }

aqui=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || recusa "não achei a pasta do script; nada foi gravado"
[ -r "$aqui/segredos.sh" ] || recusa "segredos.sh não está ao lado do enxugar.sh; nada foi gravado"
# shellcheck disable=SC1091
. "$aqui/segredos.sh"

# 1. Uso
{ [ "$#" -ge 3 ] && [ "$2" = "--" ]; } || recusa "uso: enxugar.sh <pasta-da-tarefa> -- <comando> [args...]"
pasta=$1
shift 2

# 2. Pasta
[ -d "$pasta" ] || recusa "a pasta da tarefa não existe: $pasta"
pasta_ignorada "$pasta" || recusa "a pasta $pasta não está ignorada pelo git (ou não deu para conferir); nada foi gravado"

# 3. Máscara funcionando (cobre sed que não é GNU)
[ "$(printf 'x\n' | mascarar 2>/dev/null)" = x ] || recusa "a máscara de segredo não funciona aqui (falta sed GNU?); nada foi gravado"

# 4. Pasta de saída e arquivo
abs=$(cd -- "$pasta" 2>/dev/null && pwd -P) || recusa "não deu para abrir a pasta $pasta; nada foi gravado"
saidas="$abs/saidas"
mkdir -p -- "$saidas" 2>/dev/null || recusa "não deu para criar $saidas"
# saidas/ pode ser um link para outro lugar: confere de novo, já com o caminho real
pasta_ignorada "$saidas" || recusa "$saidas não está ignorada pelo git (link simbólico?); nada foi gravado"

nome=${1##*/}
nome=$(printf '%s' "$nome" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
nome=${nome:0:40}
[ -n "$nome" ] || nome=cmd
arq=$(mktemp "$saidas/$(date +%Y%m%d-%H%M%S)-$nome-XXXXXX" 2>/dev/null) || recusa "não deu para criar o arquivo de saída; nada foi gravado"

# 5. Roda. Sem shell no meio: "$@" vai direto para o exec.
"$@" </dev/null 2>&1 | mascarar > "$arq"
estado=("${PIPESTATUS[@]}")
rc_cmd=${estado[0]}
rc_mascara=${estado[1]}

if [ "$rc_mascara" -ne 0 ]; then
  rm -f -- "$arq"
  printf 'DESCARTE a máscara falhou no meio (código %s) e o arquivo foi apagado · o comando rodou com código %s\n' "$rc_mascara" "$rc_cmd"
  exit 125
fi

# 6. Resumo, sempre lido do arquivo já mascarado. Cada linha sai cortada em 200 caracteres.
tem_jq=0
if command -v jq >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then tem_jq=1; fi

resumo_json() {
  local f=$1 formas
  set +o pipefail
  timeout 20 jq -r '"raiz: \(type)" + (if type == "array" then " · \(length) itens" elif type == "object" then " · \(length) chaves" elif type == "string" then " · \(length) caracteres" else "" end)' "$f" || return 1
  formas=$(timeout 20 jq -r '[paths(scalars) | map(if type == "number" then "[]" else . end) | join(".")] | .[]' "$f") || return 1
  if [ -n "$formas" ]; then
    echo "formas dos caminhos (até 20):"
    printf '%s\n' "$formas" | sort | uniq -c | sort -k1,1nr -s | head -n 20 |
      awk '{ n = $1; sub(/^ *[0-9]+ /, ""); print "  " n "x " substr($0, 1, 200) }'
  fi
  echo "primeiros itens:"
  timeout 20 jq -c 'if type == "array" then .[:3][] elif type == "object" then (to_entries | .[:3][] | {(.key): .value}) else . end' "$f" |
    awk '{ print "  " substr($0, 1, 200) }'
}

resumo_texto() {
  local f=$1 rep erros
  set +o pipefail
  echo "linhas: $(grep -c '' "$f")"
  rep=$(awk '
    { if (!($0 in c)) ord[++k] = $0; c[$0]++ }
    END {
      for (r = 1; r <= 10; r++) {
        best = 0
        for (i = 1; i <= k; i++) if (!(i in usada) && c[ord[i]] > best) { best = c[ord[i]]; bi = i }
        if (best < 2) break
        usada[bi] = 1
        printf "  %dx %s\n", best, substr(ord[bi], 1, 200)
      }
    }' "$f")
  if [ -n "$rep" ]; then
    echo "linhas repetidas (até 10):"
    printf '%s\n' "$rep"
  fi
  erros=$(LC_ALL=C grep -aEi 'erro|error|fail|falh|warn|aviso|exception|traceback|✗' "$f" |
    awk '!v[$0]++ { print "  " substr($0, 1, 200); if (++q == 20) exit }')
  if [ -n "$erros" ]; then
    echo "erros e avisos (até 20):"
    printf '%s\n' "$erros"
  fi
  echo "final (15 últimas):"
  tail -n 15 "$f" | awk '{ print "  " substr($0, 1, 200) }'
}

tipo=""
resumo=""
if [ ! -s "$arq" ]; then
  tipo=texto
  resumo="saída vazia"
else
  if [ "$tem_jq" -eq 1 ] && [ "$(timeout 20 jq -s length "$arq" 2>/dev/null)" = 1 ]; then
    if resumo=$(resumo_json "$arq" 2>/dev/null); then tipo=json; fi
  fi
  if [ -z "$tipo" ]; then
    tipo=texto
    resumo=$(resumo_texto "$arq")
  fi
fi

linhas=$(grep -c '' "$arq")
corpo=$(printf '%s\n' "$resumo" | sed -n '1,50p')
printf 'SAIDA %s · %s linhas · código %s · %s\n%s\n' "$arq" "$linhas" "$rc_cmd" "$tipo" "$corpo"
exit "$rc_cmd"
