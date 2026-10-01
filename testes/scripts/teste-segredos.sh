#!/usr/bin/env bash
# Testa scripts/segredos.sh: mascarar e pasta_ignorada. Só valores falsos óbvios (AAAA_FALSO_...).
# Uso: bash testes/scripts/teste-segredos.sh
# SEGREDOS_SH aponta para outro arquivo no lugar do scripts/segredos.sh (serve para ver o teste falhar sem ele).
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

# Git e configuração do usuário fora do teste: um gitignore global mudaria o resultado.
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

# shellcheck disable=SC1090
. "${SEGREDOS_SH:-$RAIZ/scripts/segredos.sh}"

n=0
erros=0
confere() { # confere <descrição> <comando...>: o caso passa quando o comando retorna 0
  n=$((n + 1))
  local desc=$1
  shift
  if ! "$@"; then
    erros=$((erros + 1))
    echo "FALHA: $desc"
  fi
}

# mascara <entrada> <valor falso> [trecho que precisa ficar]
mascara() {
  local saida
  saida=$(printf '%s\n' "$1" | mascarar) || return 1
  if printf '%s\n' "$saida" | grep -qF -- "$2"; then return 1; fi
  printf '%s\n' "$saida" | grep -qF -- '<OMITIDO' || return 1
  [ -z "${3:-}" ] || printf '%s\n' "$saida" | grep -qF -- "$3"
}

# igual <entrada> <saída esperada>: comparação exata (sem a quebra de linha final)
igual() {
  local saida
  saida=$(printf '%s\n' "$1" | mascarar) || return 1
  [ "$saida" = "$2" ]
}

# --- máscara: saída sem segredo sai idêntica --------------------------------
comum=$'texto comum sem segredo\njá mascarado: <OMITIDO>\nvariável ${TOKEN} e $HOME\ntoken: ${TOKEN}\nsenha: <OMITIDO>\ntoken: curto\nação é ótima, não é?'
confere "texto comum, <OMITIDO>, \${TOKEN} e valor curto saem idênticos" igual "$comum" "$comum"

# --- máscara: cada padrão conhecido ------------------------------------------
confere "API_KEY=" mascara 'API_KEY=AAAA_FALSO_1234 depois' 'AAAA_FALSO_1234'
confere "DB_PASSWORD=" mascara 'DB_PASSWORD=AAAA_FALSO_1234' 'AAAA_FALSO_1234'
confere "SERVICE_TOKEN=" mascara 'SERVICE_TOKEN=AAAA_FALSO_1234' 'AAAA_FALSO_1234'
confere "secure_link_md5 (resto depois do ponto e vírgula fica)" mascara 'secure_link_md5 AAAA_FALSO_1234; proximo' 'AAAA_FALSO_1234' '; proximo'
confere "sk-" mascara 'usando sk-AAAA_FALSO_1234567890 na chamada' 'AAAA_FALSO_1234567890' 'na chamada'
confere "AKIA" mascara 'conta AKIAFALSOFALSO123456 da nuvem' 'AKIAFALSOFALSO123456' 'da nuvem'
confere "ghp_" mascara 'repo ghp_AAAAFALSO1234567890AAAA clonado' 'ghp_AAAAFALSO1234567890AAAA' 'clonado'
confere "github_pat_" mascara 'repo github_pat_AAAAFALSO1234567890_AAAA clonado' 'github_pat_AAAAFALSO1234567890_AAAA' 'clonado'
confere "xoxb-" mascara 'slack xoxb-1234567890-FALSOFALSO ativo' 'xoxb-1234567890-FALSOFALSO' 'ativo'
confere "AIza" mascara 'mapa AIzaFALSO_AAAAAAAAAAAAAAAAAAAAAAAA ativo' 'AIzaFALSO_AAAAAAAAAAAAAAAAAAAAAAAA' 'ativo'
confere "JWT" mascara 'cookie eyJFALSO.eyJFALSO2.AAAA_FALSO_assinatura fim' 'eyJFALSO' 'fim'
confere "URL com senha (usuário e host ficam)" mascara 'banco postgres://usuario:AAAA_FALSO_1234@host:5432/db ok' 'AAAA_FALSO_1234' 'usuario:<OMITIDO>@host:5432/db ok'
confere "URL com senha que tem @" mascara 'banco postgres://usuario:AAAA@FALSO_1234@host/db ok' 'FALSO_1234' '@host/db ok'
confere "senha:" mascara 'senha: AAAA_FALSO_1234' 'AAAA_FALSO_1234'
confere "api-key=" mascara 'api-key=AAAA_FALSO_1234' 'AAAA_FALSO_1234'
confere "apikey=" mascara 'apikey=AAAA_FALSO_1234&x=1' 'AAAA_FALSO_1234' '&x=1'
confere "secret = com espaço" mascara 'client secret = AAAA_FALSO_1234' 'AAAA_FALSO_1234'
confere "\"token\": com aspas (JSON)" mascara '{"token": "AAAA_FALSO_1234", "b": 1}' 'AAAA_FALSO_1234' '"b": 1}'
confere "password:" mascara 'password: AAAA_FALSO_1234' 'AAAA_FALSO_1234'

# --- máscara: chave privada ---------------------------------------------------
pem_varias=$'antes\n-----BEGIN PRIVATE KEY-----\nAAAAFALSO1\nBBBBFALSO2\n-----END PRIVATE KEY-----\ndepois'
confere "PEM em várias linhas vira uma linha" igual "$pem_varias" $'antes\n<OMITIDO chave privada>\ndepois'

pem_linha='{"a":"x","k":"-----BEGIN PRIVATE KEY-----\nAAAAFALSO\n-----END PRIVATE KEY-----\n","b":"y"}'
confere "PEM numa linha só (resto da linha fica)" igual "$pem_linha" '{"a":"x","k":"<OMITIDO chave privada>\n","b":"y"}'

pem_sem_fim=$'antes\n-----BEGIN RSA PRIVATE KEY-----\nAAAAFALSO1\nBBBBFALSO2\nlinha depois sem END'
confere "PEM sem END mascara até o fim" igual "$pem_sem_fim" $'antes\n<OMITIDO chave privada>'

pem_duas=$'-----BEGIN PRIVATE KEY-----\nAAAAFALSO1\n-----END PRIVATE KEY-----\nmeio\n-----BEGIN OPENSSH PRIVATE KEY-----\nBBBBFALSO2\n-----END OPENSSH PRIVATE KEY-----'
confere "duas chaves: o texto do meio fica" igual "$pem_duas" $'<OMITIDO chave privada>\nmeio\n<OMITIDO chave privada>'

# Nome na linha do BEGIN e texto depois do END: a chave tem que sair inteira (etapa 7, A-1).
pem_nome=$'JWT_PRIVATE_KEY=-----BEGIN RSA PRIVATE KEY-----\nCORPOFALSO1\n-----END RSA PRIVATE KEY----- API_KEY=FALSO_DEPOIS_1234'
confere "nome antes do BEGIN: o corpo não vaza" mascara "$pem_nome" CORPOFALSO1
confere "nome antes do BEGIN: o texto depois do END não vaza" mascara "$pem_nome" FALSO_DEPOIS_1234
pem_secret=$'secret: -----BEGIN PRIVATE KEY-----\nCORPOFALSO2\n-----END PRIVATE KEY-----'
confere "secret: antes do BEGIN: o corpo não vaza" mascara "$pem_secret" CORPOFALSO2
pem_aspas=$'PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nCORPOFALSO3\n-----END PRIVATE KEY-----"'
confere "nome com aspas antes do BEGIN: o corpo não vaza" mascara "$pem_aspas" CORPOFALSO3
pem_depois=$'-----BEGIN PRIVATE KEY-----\nCORPOFALSO4\n-----END PRIVATE KEY----- API_KEY=FALSO_DEPOIS_5678'
confere "texto depois do END: o segredo não vaza" mascara "$pem_depois" FALSO_DEPOIS_5678

# Etapa 8, rodada 1: END de uma chave e BEGIN da seguinte na mesma linha; END solto antes do BEGIN.
pem_colada=$'-----BEGIN PRIVATE KEY-----\nCORPOFALSOUM\n-----END PRIVATE KEY----------BEGIN PRIVATE KEY-----\nCORPOFALSODOIS\n-----END PRIVATE KEY-----\ndepois'
confere "END e BEGIN na mesma linha: a 2ª chave não vaza" mascara "$pem_colada" CORPOFALSODOIS depois
pem_solto=$'x -----END PRIVATE KEY----- y -----BEGIN PRIVATE KEY-----\nCORPOFALSOSOLTO\n-----END PRIVATE KEY-----\ndepois'
confere "END solto antes do BEGIN: o corpo não vaza" mascara "$pem_solto" CORPOFALSOSOLTO depois
pem_cifrada=$'-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,ABCDEF\n\nCORPOFALSOCIFRADO\n-----END RSA PRIVATE KEY-----\ndepois'
confere "chave cifrada com cabeçalho: o corpo não vaza" mascara "$pem_cifrada" CORPOFALSOCIFRADO depois
confere "senha com ; no valor: o resto não vaza" mascara 'DB_PASSWORD=parte1;PARTEFALSA2' PARTEFALSA2
confere "chave secreta do age" mascara 'AGE-SECRET-KEY-1QQQQFALSOQQQQFALSOQQQQFALSO' QQQQFALSOQQQQFALSO

# Etapa 8, rodada 2: chave com prefixo de diff e de grep; saída grande não pode travar o pipe.
pem_diff=$'------BEGIN PRIVATE KEY-----\n-CORPOFALSODIFF\n------END PRIVATE KEY-----\n contexto\nFAIL testes 3 falhas'
confere "chave num diff (prefixo -): o corpo some e o resto aparece" mascara "$pem_diff" CORPOFALSODIFF 'FAIL testes 3 falhas'
pem_grep=$'a.pem:1:-----BEGIN PRIVATE KEY-----\na.pem:2:CORPOFALSOGREP\na.pem:3:-----END PRIVATE KEY-----\nb.txt:1:depois'
confere "chave na saída do grep: o corpo some e o arquivo seguinte aparece" mascara "$pem_grep" CORPOFALSOGREP 'b.txt:1:depois'
grande() { # 40 mil linhas depois de uma chave sem fim: termina rápido, sem nada do corpo
  local saida rc
  saida=$( { printf -- '-----BEGIN PRIVATE KEY-----\n'; seq 1 40000 | sed 's/^/CORPOFALSOGRANDE/'; } | timeout 10 bash -c '. "$1"; mascarar' _ "${SEGREDOS_SH:-$RAIZ/scripts/segredos.sh}"; echo "rc=$?")
  rc=${saida##*rc=}
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$saida" | grep -c CORPOFALSOGRANDE)" = 0 ]
}
confere "40 mil linhas: termina em menos de 10 s sem vazar" grande

# Rodado direto, o segredos.sh é o filtro do fallback do RECUSA (contratos.md).
direto() { local saida; saida=$(printf 'API_KEY=FALSO_DIRETO_9\n' | bash "${SEGREDOS_SH:-$RAIZ/scripts/segredos.sh}" --mascarar) || return 1; [ "$saida" = "API_KEY <OMITIDO>" ]; }
confere "bash segredos.sh --mascarar filtra stdin" direto
sem_opcao() { bash "${SEGREDOS_SH:-$RAIZ/scripts/segredos.sh}" </dev/null >/dev/null 2>&1; [ "$?" -eq 2 ]; }
confere "rodado direto sem opção: uso e código 2" sem_opcao

# Desvios da D-19 presos por teste (etapa 7, A-3).
for p in gho ghu ghs ghr; do
  confere "token ${p}_ do GitHub" mascara "x ${p}_AAAAFALSOAAAAFALSOAAAA1234 y" "${p}_AAAAFALSOAAAAFALSOAAAA1234"
done
utf8_invalido() { # o sed de quem chama pode estar em UTF-8; o mascarar não pode depender disso
  local saida
  saida=$(export LC_ALL=C.UTF-8; printf 'API_KEY=abc\377SEGREDORESTO\n' | mascarar) || return 1
  ! printf '%s\n' "$saida" | LC_ALL=C grep -q SEGREDORESTO
}
confere "byte inválido em UTF-8 não deixa o resto da linha à mostra" utf8_invalido

# --- máscara sem sed GNU -------------------------------------------------------
mkdir -p "$T/falso"
printf '#!/bin/sh\necho "sed (fake) 1.0"\n' > "$T/falso/sed"
chmod +x "$T/falso/sed"
printf 'API_KEY=AAAA_FALSO_1234\n' > "$T/entrada.txt"
sem_gnu() {
  local saida rc resto
  saida=$(PATH="$T/falso:$PATH"; mascarar < "$T/entrada.txt"; echo "rc=$?")
  [ "$saida" = "rc=3" ] || return 1
  # a entrada continua inteira no descritor: a função não leu nada
  resto=$( { PATH="$T/falso:$PATH"; mascarar >/dev/null; rc=$?; cat; [ "$rc" -eq 3 ] || echo "rc=$rc"; } < "$T/entrada.txt")
  [ "$resto" = 'API_KEY=AAAA_FALSO_1234' ]
}
confere "sem sed GNU: retorna 3, sem saída e sem ler a entrada" sem_gnu

# --- pasta_ignorada --------------------------------------------------------------
mkdir -p "$T/repo" "$T/solta" "$T/vazio"
git -C "$T/repo" init -q 2>/dev/null
printf '.trab/\n' >> "$T/repo/.git/info/exclude"
mkdir -p "$T/repo/.trab/tarefa/x" "$T/repo/versionada" "$T/repo/solta-no-repo"
printf 'x\n' > "$T/repo/versionada/a.txt"
git -C "$T/repo" add versionada/a.txt 2>/dev/null

confere "pasta ignorada pelo exclude" pasta_ignorada "$T/repo/.trab"
confere "subpasta de pasta ignorada" pasta_ignorada "$T/repo/.trab/tarefa/x"
negado() { ! "$@"; }
confere "pasta versionada recusa" negado pasta_ignorada "$T/repo/versionada"
confere "pasta nova fora do exclude recusa" negado pasta_ignorada "$T/repo/solta-no-repo"
confere "pasta inexistente recusa" negado pasta_ignorada "$T/nao-existe"
confere "argumento vazio recusa" negado pasta_ignorada ""
confere "fora de repositório vale" pasta_ignorada "$T/solta"
sem_git() { (PATH="$T/vazio"; pasta_ignorada "$T/repo/.trab"); }
mkdir -p "$T/so-sed" && ln -s "$(command -v sed)" "$T/so-sed/sed"
sem_awk() { (PATH="$T/so-sed"; printf 'x\n' | mascarar >/dev/null 2>&1; [ "$?" -eq 3 ]); }
confere "sem awk: a máscara recusa com 3" sem_awk
# Etapa 8, rodada 3: falha do awk não pode virar 0, com ou sem pipefail em quem chama.
mkdir -p "$T/awk-falso" && ln -s "$(command -v sed)" "$T/awk-falso/sed"
printf '#!/bin/sh\necho "FAIL linha1"\nexit 2\n' > "$T/awk-falso/awk" && chmod +x "$T/awk-falso/awk"
awk_quebrado() { (set +o pipefail; PATH="$T/awk-falso"; printf 'a\nb\nc\n' | mascarar >/dev/null 2>&1; [ "$?" -ne 0 ]); }
confere "awk que falha: mascarar não devolve 0" awk_quebrado
awk_quebrado_direto() { (PATH="$T/awk-falso:$PATH"; printf 'a\n' | bash "${SEGREDOS_SH:-$RAIZ/scripts/segredos.sh}" --mascarar >/dev/null 2>&1; [ "$?" -ne 0 ]); }
confere "awk que falha: modo direto não devolve 0" awk_quebrado_direto
confere "git ausente dentro de repositório recusa" negado sem_git

if [ "$erros" -ne 0 ]; then
  echo "FALHA: $erros de $n casos"
  exit 1
fi
echo "ok: $n casos"
