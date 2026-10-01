#!/usr/bin/env bash
# Funções de segredo da seiva. Carrega-se com `source`; rodado direto, só aceita --mascarar.
#
#   mascarar           filtro stdin -> stdout. Troca por <OMITIDO> o que parece segredo.
#                      Rodado direto, `bash segredos.sh --mascarar` faz o mesmo (fallback do RECUSA).
#                      Sem sed GNU ou sem awk, não lê a entrada, não escreve nada e retorna 3.
#   pasta_ignorada <pasta>
#                      Retorna 0 quando nada gravado ali pode subir para um git; 1 em qualquer outro caso.
#
# Limite: a máscara reconhece padrões conhecidos (lista abaixo). Segredo sem padrão, como um
# `Authorization: Bearer <valor opaco>`, passa. Por isso o enxugar só grava em pasta ignorada.
#
# Não muda opção do shell de quem carrega (nada de `set` aqui).

# Chave privada, primeiro e em awk: linha a linha, com estado. Do BEGIN em diante tudo some até o
# END, que pode estar em qualquer ponto da linha (prefixo de diff ou de grep não atrapalha). A chave
# inteira vira uma linha <OMITIDO chave privada>, e o texto antes do BEGIN e depois do END segue para
# o sed. Vem antes do sed porque uma regra de nome (`JWT_PRIVATE_KEY=-----BEGIN…`) comeria o BEGIN e
# deixaria o corpo em claro. Chave sem END é mascarada até o fim da entrada. Tempo linear.
IFS= read -r -d '' _SEGREDOS_AWK <<'AWK' || true
{
  linha = $0; saida = ""; comecou_dentro = dentro
  while (1) {
    if (dentro) {
      if (match(linha, /-----END [A-Z ]*PRIVATE KEY[A-Z ]*-----/)) {
        linha = substr(linha, RSTART + RLENGTH); dentro = 0; continue
      }
      linha = ""; break
    }
    if (match(linha, /-----BEGIN [A-Z ]*PRIVATE KEY[A-Z ]*-----/)) {
      saida = saida substr(linha, 1, RSTART - 1) "<OMITIDO chave privada>"
      linha = substr(linha, RSTART + RLENGTH); dentro = 1; continue
    }
    saida = saida linha; break
  }
  if (comecou_dentro && saida == "") next
  print saida
}
AWK

# Programa do sed, na ordem em que cada regra vale. Tudo vira <OMITIDO>.
IFS= read -r -d '' _SEGREDOS_SED <<'SED' || true
s/(secure_link_md5)[^;]*/\1 <OMITIDO>/gI
s/(_SECRET|_KEY|_TOKEN|PASSWORD).*/\1 <OMITIDO>/I
s/\bAGE-SECRET-KEY-1[0-9A-Z]{20,}/<OMITIDO>/g
s/\bsk-[A-Za-z0-9_-]{16,}/<OMITIDO>/g
s/\bAKIA[0-9A-Z]{16}/<OMITIDO>/g
s/\bgh[pousr]_[A-Za-z0-9]{20,}/<OMITIDO>/g
s/\bgithub_pat_[A-Za-z0-9_]{20,}/<OMITIDO>/g
s/\bxox[A-Za-z]-[A-Za-z0-9-]{10,}/<OMITIDO>/g
s/\bAIza[0-9A-Za-z_-]{20,}/<OMITIDO>/g
s/eyJ[A-Za-z0-9_=-]+\.eyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]*/<OMITIDO>/g
s#(://[^/:@[:space:]]+):[^/[:space:]]+@#\1:<OMITIDO>@#g
s/((secret|token|password|senha|api[_-]?key)["']?[[:space:]]*[=:][[:space:]]*["']?)[^<$"'[:space:]][^"'[:space:],;&]{7,}/\1<OMITIDO>/gI
SED

mascarar() {
  # Só o sed GNU tem \b e o flag I como estes. Sem ele, falha fechada.
  case "$(sed --version 2>/dev/null)" in
    *GNU*) ;;
    *) return 3 ;;
  esac
  command -v awk >/dev/null 2>&1 || return 3
  # LC_ALL=C: byte inválido em UTF-8 faria o sed parar de casar no meio da linha e deixaria o resto à mostra.
  LC_ALL=C awk "$_SEGREDOS_AWK" | LC_ALL=C sed -E -e "$_SEGREDOS_SED"
  # Código de quem falhou primeiro, sem depender do pipefail de quem chama.
  local st=("${PIPESTATUS[@]}")
  [ "${st[0]}" -eq 0 ] || return "${st[0]}"
  return "${st[1]}"
}

pasta_ignorada() {
  local pasta abs d
  pasta=${1:-}
  { [ -n "$pasta" ] && [ -d "$pasta" ]; } || return 1
  abs=$(cd -- "$pasta" 2>/dev/null && pwd -P) || return 1
  d=$abs
  while :; do
    if [ -e "$d/.git" ]; then
      # Só o código 0 do git vale. Git ausente, "dubious ownership" ou erro qualquer caem no return 1.
      if (unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; git -C "$abs" check-ignore -q -- "$abs") 2>/dev/null; then
        return 0
      fi
      return 1
    fi
    [ "$d" = / ] && return 0
    d=${d%/*}
    [ -n "$d" ] || d=/
  done
}

# Rodado direto, e não por source: filtro para quem não pode carregar a função (fallback do RECUSA).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --mascarar) mascarar; exit $? ;;
    *) echo "uso: bash $0 --mascarar   (filtro: stdin -> stdout; código 3 sem sed GNU)" >&2; exit 2 ;;
  esac
fi
