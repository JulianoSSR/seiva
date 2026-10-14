#!/usr/bin/env bash
# Testa scripts/ficha-tecnica.sh num repositório git temporário. Segredos são falsos óbvios.
# Uso: bash testes/scripts/teste-ficha-tecnica.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
FT="$RAIZ/scripts/ficha-tecnica.sh"

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

R=$T/repo
mkdir -p "$R/src" "$R/.seiva/tarefas/t1/relatorios" "$R/versionada"
git -C "$R" init -q
printf '.seiva/\n' >"$R/.gitignore"
P=$R/.seiva/tarefas/t1

{
  echo "const express = require('express')"
  echo "import { db } from './db'"
  echo "const API_TOKEN = 'abcdefgh12345678'"
  for i in $(seq 4 18); do echo "// enchimento $i"; done
  echo "export async function listar(req, res) {"
  echo "  const r = await db.query('SELECT * FROM coletas WHERE id = \$1', [req.params.id])"
  echo "  return res.json(r.rows)"
  echo "}"
  echo "router.get('/coletas/:id', autenticar, listar)"
  echo "const somar = (a, b) => a + b"
  for i in $(seq 25 60); do echo "// enchimento $i"; done
  echo "module.exports = { listar, somar }"
} >"$R/src/a.js"
{
  echo "import os"
  echo "from x import y"
  echo "def calcular(peso):"
  echo "    chave = os.environ['CHAVE']"
  echo "    return peso * 2"
  echo "class Nota:"
  echo "    pass"
} >"$R/src/b.py"
printf '# Título\n\ntexto\n\n## Seção A\n\n### Sub\n' >"$R/src/doc.md"
cat >"$P/relatorios/batedor-1.md" <<'FIM'
MAPA:
- src/a.js:19 — função listar
- src/a.js:23 — rota (perto da anterior: o intervalo se junta)
- src/b.py:3-5 — cálculo
- nao/existe.js:4 — citação que não existe
FIM

roda() {
  SAI=$(cd "$R" && bash "$FT" "$@" 2>"$T/err")
  RC=$?
  ERR=$(cat "$T/err")
}

# --- uso errado e recusas -----------------------------------------------------------
roda "$P"
eq "sem arquivo nem --de: uso errado" 2 "$RC"
roda "$P" --xyz
eq "opção desconhecida: uso errado" 2 "$RC"
roda "$R/versionada" src/a.js
eq "pasta versionada: recusa com 125" 125 "$RC"
tem "pasta versionada: RECUSA" "$SAI" "RECUSA"
eq "pasta versionada: nada gravado" 0 "$(find "$R/versionada" -type f | wc -l | tr -d ' ')"
roda "$P" --de "$P/relatorios/nao-tem.md"
eq "relatório que não existe: recusa" 125 "$RC"

# --- fichas por arquivo -------------------------------------------------------------
roda "$P" src/a.js src/doc.md
eq "fichas: código 0" 0 "$RC"
tem "fichas: contagem" "$SAI" "FICHAS 2"
FA=$P/fichas/src__a.js.md
eq "ficha do JS existe" sim "$([ -f "$FA" ] && echo sim)"
F=$(cat "$FA")
tem "ficha: número de linhas" "$F" "61 linhas"
tem "ficha: import" "$F" "2:import { db } from './db'"
tem "ficha: require" "$F" "1:const express = require('express')"
tem "ficha: função exportada" "$F" "19:export async function listar(req, res) {"
tem "ficha: rota" "$F" "23:router.get('/coletas/:id', autenticar, listar)"
tem "ficha: arrow function" "$F" "24:const somar = (a, b) => a + b"
tem "ficha: module.exports" "$F" "61:module.exports"
tem "ficha: SQL como linha-chave" "$F" "20:  const r = await db.query('SELECT"
tem "ficha: segredo mascarado" "$F" "<OMITIDO>"
nao_tem "ficha: valor do segredo não aparece" "$F" "abcdefgh12345678"
nao_tem "ficha: enchimento não entra" "$F" "enchimento"
eq "ficha em modo 600" 600 "$(stat -c %a "$FA")"
tem "ficha de markdown traz as seções" "$(cat "$P/fichas/src__doc.md.md")" "5:## Seção A"

# --- trechos a partir do relatório do batedor ---------------------------------------
roda "$P" --de "$P/relatorios/batedor-1.md"
eq "trechos: código 0" 0 "$RC"
tem "trechos: fichas dos arquivos citados que existem" "$SAI" "FICHAS 2"
tem "trechos: dois intervalos (as citações de a.js se juntam)" "$SAI" "TRECHOS 2 intervalos"
tem "trechos: citação inexistente pulada" "$SAI" "nao/existe.js:4"
TR=$(cat "$P/trechos.md")
tem "trechos: a.js de 9 a 33" "$TR" "## src/a.js:9-33"
tem "trechos: b.py de 1 a 7 (corta no fim do arquivo)" "$TR" "## src/b.py:1-7"
tem "trechos: linha numerada" "$TR" "   19  export async function listar"
nao_tem "trechos: fora do intervalo não entra" "$TR" "enchimento 40"
eq "ficha do Python gerada pela citação" sim "$([ -f "$P/fichas/src__b.py.md" ] && echo sim)"
tem "ficha do Python: def" "$(cat "$P/fichas/src__b.py.md")" "3:def calcular(peso):"
tem "ficha do Python: variável de ambiente" "$(cat "$P/fichas/src__b.py.md")" "4:    chave = os.environ"

# --- teto de linhas de trecho -------------------------------------------------------
seq 1 1000 | sed 's/^/linha /' >"$R/src/longo.txt"
: >"$P/relatorios/muitas.md"
for i in $(seq 30 30 900); do echo "- src/longo.txt:$i" >>"$P/relatorios/muitas.md"; done
roda "$P" --de "$P/relatorios/muitas.md"
tem "teto de 400 linhas avisado" "$(cat "$P/trechos.md")" "teto de 400 linhas"
eq "no máximo 400 linhas de trecho" 400 "$(grep -cE '^ *[0-9]+  ' "$P/trechos.md")"

# --- citação que sai do repositório não é lida -----------------------------------------
mkdir -p "$T/fora"
printf 'conteudo_de_fora_falso_1\nconteudo_de_fora_falso_2\n' >"$T/fora/credencial.cfg"
ln -sf "$T/fora/credencial.cfg" "$R/src/link.cfg"
cat >"$P/relatorios/fora.md" <<FIM
- ../fora/credencial.cfg:1
- $T/fora/credencial.cfg:2
- src/link.cfg:1
- src/a.js:1
FIM
roda "$P" --de "$P/relatorios/fora.md"
nao_tem "caminho com .. ou absoluto de fora: não entra no trecho" "$(cat "$P/trechos.md")" "conteudo_de_fora_falso"
nao_tem "nem na ficha" "$(cat "$P"/fichas/*.md)" "conteudo_de_fora_falso"
tem "a citação de fora é dita como pulada" "$SAI" "fora do repositório"
tem "a citação de dentro continua" "$(cat "$P/trechos.md")" "## src/a.js:"
rm -f "$R/src/link.cfg"

# --- chave privada: corte no meio dela não deixa o corpo em claro nem engole o resto ------
{
  echo "-----BEGIN PRIVATE KEY-----"
  for i in $(seq -w 1 25); do echo "MIIEcorpofalsodechave00$i"; done
  echo "-----END PRIVATE KEY-----"
  echo "depois_da_chave_1"
} >"$R/src/k1.pem"
cp "$R/src/k1.pem" "$R/src/k2.pem"
printf 'texto_do_arquivo_seguinte\n' >"$R/src/z.txt"
cat >"$P/relatorios/chave.md" <<'FIM'
- src/k1.pem:20
- src/k2.pem:1
- src/z.txt:1
FIM
roda "$P" --de "$P/relatorios/chave.md"
nao_tem "trecho que começa no meio da chave: corpo mascarado" "$(cat "$P/trechos.md")" "MIIEcorpofalso"
tem "trecho com BEGIN sem o END dentro: o arquivo seguinte não some" "$(cat "$P/trechos.md")" "texto_do_arquivo_seguinte"
tem "a linha depois do END continua" "$(cat "$P/trechos.md")" "depois_da_chave_1"
eq "a numeração das linhas não muda" 1 "$(grep -cE '^ +28  depois_da_chave_1' "$P/trechos.md")"
{
  echo 'JWT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----'
  echo 'MIIEcorpofalsodechaveNoScript'
  echo '-----END PRIVATE KEY-----"'
  echo '# TODO conferir depois da chave'
} >"$R/src/com-chave.sh"
roda "$P" src/com-chave.sh
nao_tem "ficha de arquivo com chave: sem o corpo" "$(cat "$P/fichas/src__com-chave.sh.md")" "MIIEcorpofalso"
tem "ficha de arquivo com chave: a linha-chave depois dela continua" "$(cat "$P/fichas/src__com-chave.sh.md")" "4:# TODO conferir depois da chave"

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
