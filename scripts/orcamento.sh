#!/usr/bin/env bash
# Lê o orçamento gravado pela statusline (scripts/statusline-orcamento.sh) e diz se a seiva pode abrir outra leva de agentes.
# Só vale no Claude Code, com a statusline instalada pelo usuário. Sem o arquivo, o estado é "desligado" e a seiva segue como sempre.
#
# Uso: orcamento.sh [--tarefa <pasta-da-tarefa>] [arquivo]
#   arquivo  padrão: ${XDG_CACHE_HOME:-$HOME/.cache}/seiva/orcamento.json
#   --tarefa grava o caminho absoluto de <pasta-da-tarefa>/registro.md no arquivo "retomar", ao lado do orçamento, para
#            a barra dizer qual tarefa retomar. Só grava se a pasta do orçamento já existe (quem a cria é a statusline)
#            e se o registro.md existe; senão não grava e diz por quê no fim da linha.
#
# Saída: uma linha
#   ORCAMENTO <estado> — 5h <n>% até <HH:MM> · 7d <n>% · ctx <n>% (sessão <8 primeiros>) · dado de <n> min[ · <aviso>]
#
#   estado     quando                                                                       código
#   desligado  sem arquivo, sem jq, JSON inválido, versao diferente de 1 ou 5h sem percentual   0
#   sem-dado   já passou da hora em que a janela de 5h reinicia                                0
#   ok         abaixo de 70                                                                     0
#   restrito   70 ou mais                                                                      10
#   parar      85 ou mais                                                                      20
#   Uso errado sai com 2.
#
# O percentual gravado vale como piso até a janela reiniciar (o uso só cresce dentro dela). A idade vem de
# cinco_horas.visto_em: a barra pode estar uma mensagem atrás. Avisos: "statusline desatualizada" quando a cópia
# instalada difere da do repositório; "versão da statusline não conferida" quando o script gravado no arquivo não é legível.
set -uo pipefail
export LC_ALL=C

uso() { echo "uso: orcamento.sh [--tarefa <pasta-da-tarefa>] [arquivo]" >&2; exit 2; }

tarefa=""
arquivo=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --tarefa)
      [ "$#" -ge 2 ] && [ -n "$2" ] || uso
      tarefa=$2
      shift 2
      ;;
    -*) uso ;;
    *)
      [ -z "$arquivo" ] || uso
      arquivo=$1
      shift
      ;;
  esac
done

if [ -z "$arquivo" ]; then
  base=${XDG_CACHE_HOME:-}
  [ -n "$base" ] || { [ -n "${HOME:-}" ] && base=$HOME/.cache; }
  arquivo=${base:+$base/seiva/orcamento.json}
fi
case $arquivo in */*) dir=${arquivo%/*} ;; *) dir=. ;; esac
case $0 in */*) aqui=${0%/*} ;; *) aqui=. ;; esac

estado=desligado
detalhe=""
script=""
if ! command -v jq >/dev/null 2>&1; then
  detalhe="jq não está instalado"
elif [ -z "$arquivo" ] || [ ! -r "$arquivo" ]; then
  detalhe="sem arquivo de orçamento (a statusline não está instalada ou ainda não recebeu resposta)"
elif lido=$(jq -r '
  def num: if type == "number" then . else null end;
  def janela: if type == "object" then {usado: (.usado | num), reinicia: (.reinicia | num), visto_em: (.visto_em | num)} else {usado: null, reinicia: null, visto_em: null} end;
  def pct: if . == null then "--" else "\((. * 10 + 1e-9 | floor) / 10)%" end;
  def hora: if . == null then "--:--" else strflocaltime("%H:%M") end;
  def valida($agora): .usado != null and (.reinicia == null or .reinicia > $agora);
  (now | floor) as $agora
  | if .versao != 1 then ["desligado", "o arquivo de orçamento é de outra versão do formato", ""]
    else
      (.cinco_horas | janela) as $c5
      | (.sete_dias | janela) as $d7
      | (.contexto | if type == "object" then {usado: (.usado | num), sessao: (.sessao // "" | tostring)} else {usado: null, sessao: ""} end) as $cx
      | ($cx.sessao | gsub("[^A-Za-z0-9._-]"; "") | .[0:8]) as $sid
      | (.script // "" | if type == "string" then gsub("[\n\r]"; "") else "" end) as $script
      | ($c5.visto_em | if . == null then "dado de idade desconhecida" else "dado de \((($agora - .) / 60 | floor) | if . < 0 then 0 else . end) min" end) as $idade
      | if $c5.usado == null then ["desligado", "o arquivo não traz o percentual da janela de 5 horas (plano sem esse dado, ou a sessão ainda não recebeu resposta)", $script]
        elif ($c5.reinicia != null and $agora >= $c5.reinicia) then
          ["sem-dado", "a janela de 5h reiniciou às \($c5.reinicia | hora); o percentual gravado é da janela anterior · \($idade)", $script]
        else
          [(if $c5.usado >= 85 then "parar" elif $c5.usado >= 70 then "restrito" else "ok" end),
           "5h \($c5.usado | pct) até \($c5.reinicia | hora) · 7d \(if ($d7 | valida($agora)) then ($d7.usado | pct) else "--" end) · ctx \($cx.usado | pct) (sessão \($sid)) · \($idade)",
           $script]
        end
    end
  | .[]
' "$arquivo" 2>/dev/null); then
  { IFS= read -r estado; IFS= read -r detalhe; IFS= read -r script; } <<< "$lido"
else
  detalhe="o arquivo de orçamento não é um JSON válido"
fi

avisos=""

# A cópia instalada da statusline acompanha a do repositório? (só informa; quem atualiza é o usuário)
if [ "$estado" != desligado ]; then
  if [ -n "$script" ] && [ -f "$script" ] && [ -r "$script" ] && [ -r "$aqui/statusline-orcamento.sh" ]; then
    cmp -s "$script" "$aqui/statusline-orcamento.sh"
    [ "$?" -eq 1 ] && avisos+=" · statusline desatualizada: rode a linha de atualização do harness.md"
  else
    avisos+=" · versão da statusline não conferida"
  fi
fi

# --tarefa: o ponto de retomada que a barra cita quando a janela estoura.
if [ -n "$tarefa" ]; then
  pasta=$(cd -- "$tarefa" 2>/dev/null && pwd -P)
  if [ -z "$pasta" ]; then
    avisos+=" · retomar não gravado: a pasta da tarefa não existe"
  elif [ ! -d "$dir" ]; then
    avisos+=" · retomar não gravado: a pasta do orçamento não existe (quem a cria é a statusline)"
  elif [ ! -f "$pasta/registro.md" ]; then
    avisos+=" · retomar não gravado: $pasta/registro.md não existe"
  elif tmp=$(umask 077 && mktemp "$dir/.retomar.XXXXXX") && (umask 077 && printf '%s\n' "$pasta/registro.md" > "$tmp") && mv -f "$tmp" "$dir/retomar"; then
    avisos+=" · retomar gravado"
  else
    [ -z "${tmp:-}" ] || rm -f "$tmp"
    avisos+=" · retomar não gravado: não consegui escrever na pasta do orçamento"
  fi
fi

printf 'ORCAMENTO %s — %s%s\n' "$estado" "$detalhe" "$avisos"

case $estado in
  restrito) exit 10 ;;
  parar) exit 20 ;;
  *) exit 0 ;;
esac
