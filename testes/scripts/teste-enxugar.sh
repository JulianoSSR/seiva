#!/usr/bin/env bash
# Testa scripts/enxugar.sh em pasta temporária, com repositório git temporário.
# Só valores falsos óbvios (AAAA_FALSO_...).
# Uso: bash testes/scripts/teste-enxugar.sh
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
ENX="$RAIZ/scripts/enxugar.sh"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

# Git e configuração do usuário fora do teste: um gitignore global mudaria o resultado.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

# Repositório temporário: .trab/ ignorada, versionada/ rastreada.
repo="$T/repo"
mkdir -p "$repo"
git -C "$repo" init -q 2>/dev/null
printf '.trab/\n' >> "$repo/.git/info/exclude"
mkdir -p "$repo/.trab" "$repo/versionada" "$T/solta"
printf 'x\n' > "$repo/versionada/a.txt"
git -C "$repo" add versionada/a.txt 2>/dev/null

nova_tarefa() { mkdir -p "$repo/.trab/$1" && (cd "$repo/.trab/$1" && pwd -P); }
tarefa=$(nova_tarefa principal)
versionada=$(cd "$repo/versionada" && pwd -P)

n=0
erros=0
confere() { # confere <descrição> <comando...>: o caso passa quando o comando retorna 0
  n=$((n + 1))
  local desc=$1
  shift
  if ! "$@"; then
    erros=$((erros + 1))
    echo "FALHA: $desc"
    if [ -n "${SAI:-}" ]; then printf '%s\n' "$SAI" | sed -n '1,6p' | sed 's/^/  | /'; fi
  fi
}

# rodar <args do enxugar>: guarda stdout em SAI e o código em RC
rodar() { SAI=$(bash "$ENX" "$@" 2>"$T/erro" </dev/null); RC=$?; }
primeira() { printf '%s\n' "$SAI" | sed -n 1p; }
# caminho do arquivo guardado, lido da primeira linha
arquivo() { local l; l=$(primeira); l=${l#SAIDA }; printf '%s\n' "${l%% · *}"; }
tem() { printf '%s\n' "$SAI" | grep -qF -- "$1"; }
nao_tem() { ! tem "$1"; }
linha1_termina() { case "$(primeira)" in *"$1") return 0 ;; *) return 1 ;; esac; }
comeca_saida() { case "$(primeira)" in "SAIDA $tarefa/saidas/"*) return 0 ;; *) return 1 ;; esac; }
comeca_com() { case "$(primeira)" in "$1"*) return 0 ;; *) return 1 ;; esac; }

# --- JSON ---------------------------------------------------------------------
caso_json() {
  rodar "$tarefa" -- printf '{"a":[1,2,3]}'
  [ "$RC" -eq 0 ] && comeca_saida && linha1_termina '· 1 linhas · código 0 · json' &&
    tem 'raiz: object' && tem '3x a.[]' && tem '{"a":[1,2,3]}' &&
    [ "$(cat "$(arquivo)")" = '{"a":[1,2,3]}' ]
}
confere "JSON: forma, contagem e primeiros itens" caso_json

# --- log repetitivo --------------------------------------------------------------
caso_log() {
  rodar "$tarefa" -- awk 'BEGIN{for(i=0;i<500;i++)print "linha repetida"; print "ERROR x"}'
  [ "$RC" -eq 0 ] && comeca_saida && linha1_termina '· 501 linhas · código 0 · texto' &&
    tem '500x linha repetida' && tem 'ERROR x' &&
    [ "$(printf '%s\n' "$SAI" | wc -l)" -le 51 ]
}
confere "log repetitivo: 500x, erro e no máximo 51 linhas" caso_log

# --- segredo na saída ---------------------------------------------------------------
caso_segredo() {
  rodar "$tarefa" -- echo API_KEY=AAAA_FALSO_1234
  local arq
  arq=$(arquivo)
  [ "$RC" -eq 0 ] && nao_tem 'AAAA_FALSO_1234' && tem '<OMITIDO>' &&
    ! grep -qF 'AAAA_FALSO_1234' "$arq" && grep -qF '<OMITIDO>' "$arq" &&
    [ "$(stat -c %a "$arq")" = 600 ]
}
confere "segredo: arquivo e resumo mascarados, modo 600" caso_segredo

# --- recusas -------------------------------------------------------------------------
caso_versionada() {
  rodar "$versionada" -- touch "$T/marcador1"
  comeca_com 'RECUSA ' && [ "$RC" -eq 125 ] && [ ! -e "$versionada/saidas" ] && [ ! -e "$T/marcador1" ]
}
confere "pasta versionada: RECUSA, 125, nada gravado, comando não rodou" caso_versionada

mkdir -p "$T/falso"
printf '#!/bin/sh\necho "sed (fake) 1.0"\n' > "$T/falso/sed"
chmod +x "$T/falso/sed"
caso_sem_gnu() {
  local t2
  t2=$(nova_tarefa sem-gnu)
  SAI=$(PATH="$T/falso:$PATH" bash "$ENX" "$t2" -- touch "$T/marcador2" 2>/dev/null </dev/null)
  RC=$?
  comeca_com 'RECUSA ' && [ "$RC" -eq 125 ] && [ ! -e "$t2/saidas" ] && [ ! -e "$T/marcador2" ]
}
confere "sem sed GNU: RECUSA, 125, nada gravado, comando não rodou" caso_sem_gnu

caso_uso() {
  rodar
  comeca_com 'RECUSA ' && [ "$RC" -eq 125 ] || return 1
  rodar "$tarefa" true
  comeca_com 'RECUSA ' && [ "$RC" -eq 125 ] || return 1
  rodar "$tarefa" --
  comeca_com 'RECUSA ' && [ "$RC" -eq 125 ]
}
confere "uso errado (sem --, sem comando): RECUSA e 125" caso_uso

caso_sem_pasta() {
  rodar "$T/nao-existe" -- touch "$T/marcador3"
  comeca_com 'RECUSA ' && [ "$RC" -eq 125 ] && [ ! -e "$T/marcador3" ]
}
confere "pasta inexistente: RECUSA e 125" caso_sem_pasta

caso_link() {
  local t5
  t5=$(nova_tarefa com-link)
  ln -s "$versionada" "$t5/saidas"
  rodar "$t5" -- touch "$T/marcador4"
  comeca_com 'RECUSA ' && [ "$RC" -eq 125 ] && [ ! -e "$T/marcador4" ] && [ "$(ls -A "$versionada")" = 'a.txt' ]
}
confere "saidas/ que aponta para pasta versionada: RECUSA, nada gravado" caso_link

# --- código de saída do comando -------------------------------------------------------------
caso_125() {
  rodar "$tarefa" -- sh -c 'exit 125'
  comeca_saida && linha1_termina 'código 125 · texto' && [ "$RC" -eq 125 ]
}
confere "comando que sai com 125: a 1ª palavra (SAIDA) decide" caso_125

caso_7() {
  rodar "$tarefa" -- sh -c 'exit 7'
  comeca_saida && linha1_termina 'código 7 · texto' && [ "$RC" -eq 7 ]
}
confere "código do comando passa adiante" caso_7

caso_127() {
  rodar "$tarefa" -- nao-existe-xyz
  comeca_saida && linha1_termina 'código 127 · texto' && [ "$RC" -eq 127 ]
}
confere "comando inexistente: código 127" caso_127

caso_vazia() {
  rodar "$tarefa" -- true
  comeca_saida && linha1_termina '· 0 linhas · código 0 · texto' && tem 'saída vazia' && [ "$RC" -eq 0 ]
}
confere "saída vazia" caso_vazia

caso_segundo() {
  local t3 a b
  t3=$(nova_tarefa mesmo-segundo)
  rodar "$t3" -- true
  a=$(arquivo)
  rodar "$t3" -- true
  b=$(arquivo)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] && [ "$(ls "$t3/saidas" | wc -l)" -eq 2 ]
}
confere "duas chamadas seguidas: dois arquivos diferentes" caso_segundo

# --- máscara que falha no meio ------------------------------------------------------------------
mkdir -p "$T/falso2"
cp "$ENX" "$T/falso2/enxugar.sh"
cat > "$T/falso2/segredos.sh" <<FAKE
. "$RAIZ/scripts/segredos.sh"
mascarar() { IFS= read -r l; printf '%s\n' "\$l"; cat > /dev/null; return 1; }
FAKE
caso_descarte() {
  local t4
  t4=$(nova_tarefa descarte)
  SAI=$(bash "$T/falso2/enxugar.sh" "$t4" -- printf 'a\nb\nc\n' 2>/dev/null </dev/null)
  RC=$?
  comeca_com 'DESCARTE ' && linha1_termina 'o comando rodou com código 0' && [ "$RC" -eq 125 ] &&
    [ -z "$(ls -A "$t4/saidas")" ]
}
confere "máscara falha no meio: DESCARTE, 125, arquivo apagado" caso_descarte

# --- linha gigante, sem eval, stdin, argumentos ----------------------------------------------------------
caso_gigante() {
  rodar "$tarefa" -- bash -c 'printf "%010000d\n" 0 | tr 0 a'
  tem "$(printf 'a%.0s' $(seq 1 200))" && ! tem "$(printf 'a%.0s' $(seq 1 201))"
}
confere "linha de 10 mil caracteres aparece cortada em 200" caso_gigante

caso_sem_eval() {
  rodar "$tarefa" -- echo "\$(touch $T/marcador5)"
  [ "$RC" -eq 0 ] && [ ! -e "$T/marcador5" ] && [ "$(cat "$(arquivo)")" = "\$(touch $T/marcador5)" ]
}
confere "argumento com \$(...) não é executado" caso_sem_eval

caso_argumentos() {
  rodar "$tarefa" -- printf '%s|' 'a b' 'c"d'
  [ "$(cat "$(arquivo)")" = 'a b|c"d|' ]
}
confere "argumentos com espaço e aspa chegam inteiros" caso_argumentos

caso_stdin() {
  SAI=$(echo dados-do-stdin | bash "$ENX" "$tarefa" -- cat 2>/dev/null)
  RC=$?
  nao_tem 'dados-do-stdin' && tem 'saída vazia' && [ "$RC" -eq 0 ]
}
confere "o comando lê /dev/null, não o stdin de quem chamou" caso_stdin

caso_fora_de_repo() {
  rodar "$T/solta" -- echo ola
  comeca_com "SAIDA $T/solta/saidas/" && [ "$RC" -eq 0 ]
}
confere "pasta fora de repositório git grava" caso_fora_de_repo

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
