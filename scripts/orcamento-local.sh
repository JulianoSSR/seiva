#!/usr/bin/env bash
# Orçamento vivo sem statusline. Lê os transcripts locais do Claude Code, que o terminal e o app desktop escrevem do
# mesmo jeito (~/.claude/projects/**/*.jsonl), estima o uso da janela de 5 horas e mede o contexto da sessão atual.
# Grava o resultado no formato do orcamento.json, com o campo "fonte", e passa a decisão ao scripts/orcamento.sh, que
# continua sendo o único que decide entre ok, restrito e parar. Não precisa de statusline, de hook nem de terminal.
#
# Uso: orcamento-local.sh [--tarefa <pasta-da-tarefa>] [--sessao <id>] [--leva "<papel>:<modelo> ..."]
#                          [--calibrar <pct> [--em <hora>] | --calibrar auto]
#      orcamento-local.sh --leituras | --descartar <hora|ultima>
#   --tarefa          repassado ao orcamento.sh, que grava o "retomar" da barra. Também marca a sessão em
#                     <pasta>/sessoes ("<epoch> <sessão>"): é por essas marcas que o medir.sh separa a parte do
#                     orquestrador. A pasta de trabalho (a que tem tarefas/) e a pasta tarefas/ são recusadas com código 2,
#                     antes de criar ou marcar qualquer coisa: a marca "sessoes" na pasta errada confunde o medir.sh
#   --leva            os agentes da próxima leva, um item por agente (ex.: "construtor:opus adversario:opus lente:sonnet").
#                     A linha ganha a previsão de custo da leva, pela mediana das corridas limpas (sem queda e sem
#                     retomada) do histórico que o medir.sh grava, e se ela cabe no que resta da janela de 5 horas.
#                     Item com menos de 3 corridas limpas fica fora da soma, e a linha diz qual
#   --sessao          a sessão cujo contexto se mede. Padrão: $CLAUDE_CODE_SESSION_ID (o app desktop define; medido em
#                     2026-10-13). Sem ela, o transcript mais recente da pasta do projeto, com o aviso "sessão deduzida"
#   --calibrar <pct>  leitura do /usage (ou da página de uso do claude.ai): <pct> é o uso da janela de 5 horas que
#                     ele mostrou (de 10 a 100). Vira um ponto de calibração, como um limite batido. A linha diz a hora
#                     gravada e como desfazer, e avisa quando o limite que a leitura dá foge do dobro ou da metade dos outros
#   --em <hora>       quando a leitura foi feita. Aceita: epoch; ISO com Z (2026-10-13T14:04:42.667Z, como o relatório do
#                     /usage traz) ou com deslocamento (2026-10-13T11:04:42-03:00 ou -0300); HH:MM ou HH:MM:SS (0 a 23)
#                     e H:MM[:SS] com am ou pm, em hora local do sistema, valendo a ocorrência mais recente que não passa
#                     de agora (a de hoje, ou a de ontem quando a de hoje ainda não chegou). ISO sem fuso é recusado: a
#                     janela de 5 horas deixaria passar um erro de horas. O recibo mostra o fuso do sistema e a hora em
#                     UTC, para quem digitou a hora no fuso errado ver a diferença. Sem --em, agora. Conta só o que a
#                     janela tinha gastado até aquela hora
#   --calibrar auto   refaz a calibração automática varrendo os transcripts dos últimos 30 dias. Não apaga leitura manual, salvo a que um
#                     /usage do transcript já trazia (mesmo percentual, até 15 minutos), que passa a ser a do transcript
#   --leituras        lista as leituras do /usage gravadas, com a hora em UTC que o --descartar aceita, a hora local e a
#                     fonte (transcript ou manual; leitura gravada sem fonte é manual) no fim da linha, e sai
#   --descartar <h>   apaga a leitura gravada naquela hora (as mesmas formas do --em, ou "ultima") e sai. Epoch ou forma
#                     com segundos casa a leitura dessa hora exata; forma sem segundos (HH:MM, H:MM am/pm, ISO sem
#                     segundos) casa a leitura que cai naquele minuto, e se houver duas ou mais recusa e pede a hora
#                     com segundos do --leituras. Leitura de fonte transcript é recusada (código 2): ela volta na varredura
#                     seguinte
#
# Variáveis: PESO_CACHE_LEITURA (padrão 0.01), SEIVA_JANELA_CONTEXTO (tokens; força a janela de contexto),
# SEIVA_TRANSCRIPTS (~/.claude/projects). Sem SEIVA_JANELA_CONTEXTO, a janela é de 1 milhão quando a própria sessão já
# passou de 200 mil (medida) ou quando o modelo passou de 200 mil em algum transcript dos últimos 30 dias (deduzida, e
# a linha diz isso: o transcript grava o mesmo nome de modelo nas janelas de 200 mil e de 1 milhão); senão, 200 mil.
#
# Saída: a linha do orcamento.sh com a fonte no fim. Códigos iguais aos dele: 0, 10 (restrito), 20 (parar); 2 é uso errado.
#
# Como estima (detalhe e limites em referencias/harness.md, seção "Orçamento vivo"):
#   - cada resposta pesa entrada + saída + escrita de cache + PESO_CACHE_LEITURA × leitura de cache, contada uma vez
#     (o transcript repete a mesma resposta numa linha por bloco de conteúdo; a chave é message.id + requestId);
#   - a janela começa na 1ª resposta depois do fim da anterior, arredondada para baixo em 10 minutos, e dura 5 horas.
#     Quando a conta bateu no limite, a mensagem "You've hit your session limit · resets <hora> (<fuso>)" dá a janela exata;
#   - o percentual divide os tokens da janela pelo limite calibrado. Cada vez que a conta bateu no limite, o total da
#     janela até ali vale 100%; cada leitura do /usage vale o percentual lido. O limite é o MENOR dos 5 pontos mais
#     recentes: freio conservador. (Em 2026-10-13 a mediana dos 20 limites anteriores dava 40% quando o /usage dava 73%.)
#     Com leitura do /usage dentro da janela aberta, ela é a âncora: o percentual parte do valor lido, e só o gasto
#     depois da leitura é estimado (duas leituras de 2026-10-13 não fecharam com peso nenhum: a janela tinha gasto
#     que os transcripts não veem).
#   - o /usage vira leitura sozinho, sem --calibrar. O Claude Code grava cada /usage no transcript, e a próxima
#     execução lê o que está lá. Só há leitura quando o usuário roda o /usage: a tela de uso vista ou colada do app, sem
#     rodar o comando, não deixa registro e não conta. Como a leitura entra:
#       . percentual e fim da janela vêm do usageReport (item session; a semana, do weekly_all; resets_at sem a fração, com
#         Z ou ±HH:MM). Sem o usageReport, vem do texto "Current session: <n>% used", que não traz o fim: só vale se
#         cair na janela aberta. /usage com número que não consigo ler é ignorado, e a linha avisa uma vez, com a hora
#         do mais recente (formato que não reconheço); /usage sem número nenhum não conta e não avisa
#       . o fim que o /usage dá manda sobre o estimado: a janela de 5 horas passa a acabar nele. Só os avisos de limite
#         viram ponto de calibração e "bateu no limite"
#       . x e y são o uso da janela dela até a hora do /usage; só entra leitura cuja janela começa dentro da varredura.
#         Leitura já gravada na mesma hora mantém o x e o y gravados. Manual e do transcript com o mesmo percentual a até
#         15 minutos uma da outra são a mesma leitura: fica a do transcript, com o x e o y da manual
#       . abaixo de 10% (o piso do --calibrar) a leitura é âncora só nesta execução: não é gravada nem vira ponto de limite
#       . com a janela aberta e ao menos uma leitura do /usage de 10% ou mais dentro dela, do transcript ou digitada no
#         --calibrar, o limite é a mediana dos limites que elas dão (rótulo "leitura da janela"), no lugar do menor dos 5
#         pontos. Sem leitura na janela aberta, vale o menor dos 5 pontos
#       . 7d sem statusline: a semana da última leitura dentro da janela aberta, enquanto o reinício dela não passou; senão
#         "--". É só exibição
#       . leitura do transcript o --descartar não apaga (recusa com código 2): a execução seguinte a traria de volta
#         enquanto o /usage dela estiver nos transcripts da varredura
#   - o contexto é o tamanho da última resposta da sessão (entrada + leitura e escrita de cache) sobre a janela do modelo.
#   O percentual é ESTIMADO: a contabilidade da assinatura não é pública. É freio, não medidor oficial.
#
# Arquivos, em ${XDG_CACHE_HOME:-$HOME/.cache}/seiva/, modo 600: orcamento-local.json (o estado) e calibracao.json.
# Duas execuções ao mesmo tempo esperam uma pela outra (flock em .trava, até 60 s). Calibração ilegível ou de forma
# desconhecida é guardada como calibracao.json.invalido-<epoch> e refeita, com aviso na linha.
# Transcript desta sessão mexido nos últimos 10 minutos, com resposta do modelo (fora as de erro da API) e nenhum
# registro de uso reconhecível, sai como "desligado": o formato do transcript mudou, e a estimativa daria 0% em silêncio.
# Do transcript só saem números, horários, o nome do modelo e o texto do aviso de limite: nenhum texto de conversa
# (do /usage só os números e o resets_at).
set -uo pipefail
export LC_ALL=C
umask 077

uso() {
  echo "uso: orcamento-local.sh [--tarefa <pasta-da-tarefa>] [--sessao <id>] [--leva \"<papel>:<modelo> ...\"] [--calibrar <pct> [--em <hora>] | --calibrar auto] | --leituras | --descartar <hora|ultima>" >&2
  echo "     <hora>: $formas" >&2
  exit 2
}
formas='epoch (só dígitos); ISO com Z ou com deslocamento (2026-10-13T14:04:42Z, 2026-10-13T11:04:42-03:00; ISO sem fuso não vale); hora local do sistema (HH:MM, HH:MM:SS ou H:MM am/pm, como 08:21 ou 8:21pm)'
# Hora digitada (--em, --descartar) para "<epoch> <1 se tinha segundos, 0 se não>"; vazio se não for forma aceita.
# Formas: epoch (só dígitos); AAAA-MM-DDTHH:MM[:SS][.fração] seguido de Z, ±HH:MM ou ±HHMM; HH:MM[:SS] (hora de 0 a 23) e
# H:MM[:SS] com am ou pm (hora de 1 a 12), estas em hora local do sistema, valendo a ocorrência mais recente que não passa
# de agora. O deslocamento do fuso é calculado na hora candidata, em duas passadas (a do instante pode ser outra, no
# horário de verão). O texto digitado entra no jq só por --arg, nunca no programa. A conversão é toda em jq: o date do
# GNU e o do BSD não leem as mesmas formas.
epoch_de() {
  case $1 in
    '') return 0 ;;
    *[!0-9]*) ;;
    *) [ "${#1}" -le 11 ] && printf '%s 1\n' "$((10#$1))"; return 0 ;;
  esac
  jq -nr --arg t "$1" --argjson agora "$agora" '
    def deslocamento($e): ($e | localtime | mktime) - $e;
    def de_parede($n): ($n - deslocamento($agora)) as $c | $n - deslocamento($c);
    def hoje_ou_ontem($h; $m; $s):
      ($agora | localtime | [.[0], .[1], .[2], 0, 0, 0, 0, 0] | mktime) as $dia
      | ($h * 3600 + $m * 60 + $s) as $d
      | de_parede($dia + $d) as $e
      | if $e <= $agora then $e else de_parede($dia - 86400 + $d) end;
    def iso:
      capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})T(?<h>[0-9]{2}):(?<m>[0-9]{2})(:(?<s>[0-9]{2}))?(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$") as $c
      | "\($c.d)T\($c.h):\($c.m):\($c.s // "00")Z" as $l
      | ($l | try fromdateiso8601 catch empty) as $e0
      | select(($e0 | todate) == $l)
      | (if $c.z == "Z" then 0 else
           ($c.z | capture("^(?<sg>[+-])(?<zh>[0-9]{2}):?(?<zm>[0-9]{2})$")) as $o
           | select(($o.zh | tonumber) <= 23 and ($o.zm | tonumber) <= 59)
           | (($o.zh | tonumber) * 3600 + ($o.zm | tonumber) * 60) * (if $o.sg == "-" then -1 else 1 end)
         end) as $off
      | [$e0 - $off, (if $c.s == null then 0 else 1 end)];
    def hora24:
      capture("^(?<h>[0-9]{1,2}):(?<m>[0-9]{2})(:(?<s>[0-9]{2}))?$") as $c
      | select(($c.h | tonumber) <= 23 and ($c.m | tonumber) <= 59 and (($c.s // "0") | tonumber) <= 59)
      | [hoje_ou_ontem(($c.h | tonumber); ($c.m | tonumber); (($c.s // "0") | tonumber)), (if $c.s == null then 0 else 1 end)];
    def hora12:
      capture("^(?<h>[0-9]{1,2}):(?<m>[0-9]{2})(:(?<s>[0-9]{2}))? ?(?<ap>[AaPp][Mm])$") as $c
      | select(($c.h | tonumber) >= 1 and ($c.h | tonumber) <= 12 and ($c.m | tonumber) <= 59 and (($c.s // "0") | tonumber) <= 59)
      | ((($c.h | tonumber) % 12) + (if ($c.ap | ascii_downcase) == "pm" then 12 else 0 end)) as $h
      | [hoje_ou_ontem($h; ($c.m | tonumber); (($c.s // "0") | tonumber)), (if $c.s == null then 0 else 1 end)];
    first($t | (iso, hora24, hora12)) | "\(.[0]) \(.[1])"' 2>/dev/null
}

tarefa=""
sessao=""
deduzida=""
calibrar=""
em=""
leituras=0
descartar=""
leva=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --tarefa | --sessao | --calibrar | --em | --descartar | --leva)
      [ "$#" -ge 2 ] && [ -n "$2" ] || uso
      case $1 in
        --tarefa) tarefa=$2 ;;
        --sessao) sessao=$2 ;;
        --calibrar) calibrar=$2 ;;
        --em) em=$2 ;;
        --descartar) descartar=$2 ;;
        --leva) leva=$2 ;;
      esac
      shift 2
      ;;
    --leituras)
      leituras=1
      shift
      ;;
    *) uso ;;
  esac
done
if [ "$leituras" = 1 ] || [ -n "$descartar" ]; then
  { [ -z "$calibrar$em" ] && { [ "$leituras" = 0 ] || [ -z "$descartar" ]; }; } || uso
fi
# --tarefa pede a pasta da tarefa. Pasta de trabalho (tem tarefas/ na raiz) e pasta tarefas (chama-se tarefas e alguma
# subpasta tem registro.md ou progresso.md) são recusadas antes de qualquer coisa ser criada ou marcada: a marca
# "sessoes" numa pasta errada confunde o medir.sh. O caminho é resolvido antes (atalho vira o destino).
if [ -n "$tarefa" ] && ptarefa=$(cd -- "$tarefa" 2>/dev/null && pwd -P); then
  if [ -d "$ptarefa/tarefas" ]; then
    echo "orcamento-local.sh: $ptarefa é pasta de trabalho (tem tarefas/); --tarefa pede a pasta da tarefa, $ptarefa/tarefas/<tarefa>" >&2
    exit 2
  fi
  if [ "${ptarefa##*/}" = tarefas ]; then
    for sub in "$ptarefa"/*/; do
      if [ -f "${sub}registro.md" ] || [ -f "${sub}progresso.md" ]; then
        echo "orcamento-local.sh: $ptarefa é a pasta tarefas/; --tarefa pede uma tarefa dentro dela, $ptarefa/<tarefa>" >&2
        exit 2
      fi
    done
  fi
fi
agora=$(date +%s)
desc_seg=1
if [ -n "$descartar" ] && [ "$descartar" != ultima ]; then
  r=$(epoch_de "$descartar")
  [ -n "$r" ] || { echo "--descartar: use a hora que o --leituras mostra (ISO em UTC), outra forma aceita ou \"ultima\". Formas aceitas: $formas" >&2; exit 2; }
  descartar=${r% *}
  desc_seg=${r#* }
fi
case $calibrar in
  '' | auto) ;;
  *[!0-9.]* | *.*.* | .*) uso ;;
  *)
    awk -v p="$calibrar" 'BEGIN { exit !(p + 0 >= 10 && p + 0 <= 100) }' ||
      { echo "--calibrar: o percentual vai de 10 a 100 (abaixo de 10, o erro da conta fica grande demais)" >&2; exit 2; }
    ;;
esac

# --leva: papel conhecido e família de modelo, para a previsão não errar em silêncio por um nome digitado errado.
if [ -n "$leva" ]; then
  read -r -a itens <<<"$leva"
  [ "${#itens[@]}" -gt 0 ] || uso
  for item in "${itens[@]}"; do
    case ${item%%:*} in
      batedor | construtor | adversario | lente | implementador | verificador | invasor | revisor) ;;
      *) echo "--leva: cada item é <papel>:<modelo>; papéis: batedor construtor adversario lente implementador verificador invasor revisor (veio '$item')" >&2; exit 2 ;;
    esac
    case ${item#*:} in
      "$item" | '' | *[!a-z0-9.-]*) echo "--leva: modelo inválido em '$item' (use a família: opus, sonnet, haiku, fable)" >&2; exit 2 ;;
    esac
  done
fi

hora_lida=""
if [ -n "$em" ]; then
  case $calibrar in '' | auto) echo "--em só vale com --calibrar <pct>" >&2; exit 2 ;; esac
  em_digitado=$em
  r=$(epoch_de "$em")
  [ -n "$r" ] || { echo "--em: hora não reconhecida. Formas aceitas: $formas" >&2; exit 2; }
  em=${r% *}
  # Quem não digitou epoch vê, no erro de janela, a hora que o script entendeu.
  case $em_digitado in *[!0-9]*) hora_lida=$(jq -nr --argjson e "$em" '$e | todate' 2>/dev/null) ;; esac
fi

pcl=${PESO_CACHE_LEITURA:-0.01}
awk -v p="$pcl" 'BEGIN { exit !(p ~ /^[0-9]*\.?[0-9]+$/ && p + 0 <= 1) }' ||
  { echo "PESO_CACHE_LEITURA precisa ser um número de 0 a 1 (veio '$pcl')" >&2; exit 2; }
janela_env=${SEIVA_JANELA_CONTEXTO:-}
case $janela_env in '' | *[!0-9]*) janela_env=0 ;; esac

case $0 in */*) aqui=${0%/*} ;; *) aqui=. ;; esac
lei="$aqui/orcamento.sh"
[ -r "$lei" ] || { echo "ORCAMENTO desligado — o orcamento.sh não está ao lado do orcamento-local.sh"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "ORCAMENTO desligado — jq não está instalado · fonte transcripts"; exit 0; }

base=${XDG_CACHE_HOME:-}
[ -n "$base" ] || { [ -n "${HOME:-}" ] && base=$HOME/.cache; }
[ -n "$base" ] || { echo "ORCAMENTO desligado — sem HOME nem XDG_CACHE_HOME para gravar o estado"; exit 0; }
dir=$base/seiva
mkdir -p -- "$dir" 2>/dev/null || { echo "ORCAMENTO desligado — não consegui criar $dir"; exit 0; }
arq=$dir/orcamento-local.json
cal=$dir/calibracao.json
stl=$dir/orcamento.json
trans=${SEIVA_TRANSCRIPTS:-${HOME:-/nonexistent}/.claude/projects}
[ -n "$em" ] || em=$agora
avisos=""

# Uma execução por vez: a calibração é lida no começo e regravada no fim, e duas execuções juntas perderiam a leitura
# gravada pela mais rápida.
if command -v flock >/dev/null 2>&1; then
  if { exec 9>"$dir/.trava"; } 2>/dev/null; then
    flock -w 60 9 2>/dev/null ||
      { echo "ORCAMENTO desligado — outra execução do orcamento-local.sh segura $dir/.trava há mais de 60 s"; exit 0; }
  else
    avisos+=" · não consegui abrir $dir/.trava: sem trava nesta execução"
  fi
else
  avisos+=" · sem flock: duas execuções ao mesmo tempo podem perder uma leitura do /usage"
fi

# Sessão: a do harness; sem ela, a do transcript mais recente na pasta do projeto. O nome da pasta é o caminho com
# tudo que não é letra ou número trocado por hífen, um por caractere; com acento no caminho, o hífen por byte (locale C)
# fica de reserva, porque a regra do Claude Code para caractere fora do ASCII não foi medida.
[ -n "$sessao" ] || sessao=${CLAUDE_CODE_SESSION_ID:-}
sessao=${sessao//[^A-Za-z0-9._-]/}
if [ -z "$sessao" ] && [ -d "$trans" ]; then
  proj=""
  for loc in C.UTF-8 C.utf8 C; do
    p=$(printf '%s' "$PWD" | LC_ALL=$loc sed 's/[^A-Za-z0-9]/-/g' 2>/dev/null)
    [ -n "$p" ] && [ -d "$trans/$p" ] && { proj=$p; break; }
  done
  ultimo=""
  [ -z "$proj" ] || ultimo=$(ls -t -- "$trans/$proj"/*.jsonl 2>/dev/null | head -n 1)
  if [ -n "$ultimo" ]; then
    sessao=${ultimo##*/}
    sessao=${sessao%.jsonl}
    sessao=${sessao//[^A-Za-z0-9._-]/}
    deduzida=1
    avisos+=" · sessão deduzida pelo transcript mais recente do projeto"
  fi
fi

# Marca da sessão na pasta da tarefa: o medir.sh conta o orquestrador da 1ª à última marca de cada sessão.
if [ -n "$tarefa" ] && [ -n "$sessao" ] && [ -d "$tarefa" ]; then
  printf '%s %s%s\n' "$agora" "$sessao" "${deduzida:+ deduzida}" >>"$tarefa/sessoes" 2>/dev/null ||
    avisos+=" · não consegui marcar a sessão em $tarefa/sessoes"
fi

# Calibração: só a forma conhecida entra. A 1.2.0 gravava uma leitura só, em "manual"; ela vira a 1ª leitura.
# O que não passa é guardado ao lado, nunca regravado por cima sem aviso.
calj=null
if [ -e "$cal" ]; then
  calj=$(jq -c '
    def num: type == "number";
    if type == "object" and .versao == 1 then
      (if (.manual | type) == "object" and .leituras == null then .leituras = [.manual] else . end | del(.manual))
      | if ((.pontos // []) | type == "array" and all(.[]; type == "object" and (.r | num) and (.hit | num) and (.x | num) and (.y | num)))
           and ((.leituras // []) | type == "array" and all(.[]; type == "object" and (.em | num) and (.pct | num) and (.x | num) and (.y | num)))
           and ((.contexto_max // {}) | type == "object" and all(.[]; num))
           and ((.contexto_1m // {}) | type == "object" and all(.[]; num))
           and ((.varrido_ate // 0) | num)
        then . else "invalido" end
    else "invalido" end' "$cal" 2>/dev/null) || calj='"invalido"'
  if [ -z "$calj" ] || [ "$calj" = '"invalido"' ]; then
    guarda=$cal.invalido-$agora-$$
    if mv -f -- "$cal" "$guarda" 2>/dev/null; then
      avisos+=" · calibracao.json ilegível ou de forma desconhecida: guardada em ${guarda##*/} e refeita"
    else
      avisos+=" · calibracao.json ilegível e não consegui guardá-la à parte: refeita por cima"
    fi
    calj=null
  fi
fi

# --leituras e --descartar: só a calibração, sem varrer transcript.
if [ "$leituras" = 1 ]; then
  [ "$calj" != null ] || { echo "LEITURAS 0 · sem calibração gravada$avisos"; exit 0; }
  printf '%s' "$calj" | jq -r --argjson pcl "$pcl" '
    def fmt: if . >= 1000000 then "\((. / 100000 | floor) / 10) mi" else "\(. / 1000 | floor) mil" end | gsub("\\."; ",");
    ((.leituras // []) | map(select(.pct >= 1))) as $l
    | "LEITURAS \($l | length) (hora em UTC, para o --descartar)",
      ($l | sort_by(.em) | .[] | "\(.em | todate) · \(.pct)% · limite que ela dá ≈ \((.x + $pcl * .y) / (.pct / 100) | fmt) tokens ponderados · local \(.em | strflocaltime("%d/%m %H:%M")) · fonte \(if .f == "transcript" then "transcript" else "manual" end)")'
  exit 0
fi
if [ -n "$descartar" ]; then
  [ "$calj" != null ] || { echo "--descartar: não há calibração gravada$avisos" >&2; exit 2; }
  # Epoch ou forma com segundos: a leitura dessa hora exata. Forma sem segundos: a que cai naquele minuto.
  achados=$(printf '%s' "$calj" | jq -r --arg d "$descartar" --argjson seg "$desc_seg" '(.leituras // []) | sort_by(.em)
    | (if $d == "ultima" then (if length == 0 then [] else [last | .em] end)
       else ($d | tonumber) as $e | [.[] | select(if $seg == 1 then .em == $e else (.em >= $e and .em < $e + 60) end) | .em] end) as $a
    | ($a | length), ($a[0] // "")')
  { IFS= read -r nachados; IFS= read -r alvo; } <<<"$achados"
  [ "${nachados:-0}" -ge 1 ] || { echo "--descartar: nenhuma leitura nessa hora. Veja orcamento-local.sh --leituras" >&2; exit 2; }
  [ "$nachados" -eq 1 ] ||
    { echo "--descartar: $nachados leituras nesse minuto, nada apagado. Use a hora com segundos que o orcamento-local.sh --leituras mostra" >&2; exit 2; }
  # Leitura do transcript volta na varredura seguinte enquanto o /usage dela estiver nos transcripts: apagar não adianta.
  fonte=$(printf '%s' "$calj" | jq -r --argjson a "$alvo" '[.leituras[] | select(.em == $a) | .f // "manual"] | first // "manual"')
  if [ "$fonte" = transcript ]; then
    echo "--descartar: a leitura dessa hora vem do transcript (foi um /usage rodado) e volta na varredura seguinte enquanto ele estiver nos transcripts; nada apagado" >&2
    exit 2
  fi
  novo=$(printf '%s' "$calj" | jq -c --argjson a "$alvo" '.leituras |= map(select(.em != $a))')
  tmpd=$(mktemp "$dir/.calibracao.XXXXXX") && printf '%s\n' "$novo" >"$tmpd" && mv -f "$tmpd" "$cal" ||
    { rm -f -- "${tmpd:-}"; echo "--descartar: não consegui gravar $cal" >&2; exit 2; }
  printf '%s' "$calj" | jq -r --argjson a "$alvo" '.leituras[] | select(.em == $a) | "DESCARTADA a leitura de \(.em | todate) (\(.pct)%)"'
  exit 0
fi

# Quanto varrer: 30 dias na 1ª vez e no --calibrar auto; depois, desde a última varredura mais 5 horas, no mínimo
# 24 horas (o encadeamento das janelas precisa do dia anterior).
minutos=1440
recalibrou=0
if [ "$calibrar" = auto ] || [ "$calj" = null ]; then
  minutos=43200
  recalibrou=1
else
  desde=$(printf '%s' "$calj" | jq -r '.varrido_ate // 0 | if type == "number" then floor else 0 end')
  m=$(((agora - desde) / 60 + 300))
  [ "$m" -gt "$minutos" ] && minutos=$m
  [ "$minutos" -gt 43200 ] && minutos=43200
fi

tmp=$(mktemp "$dir/.registros.XXXXXX") || { echo "ORCAMENTO desligado — não consegui criar arquivo temporário em $dir"; exit 0; }
tmpj=""
tmpc=""
trap 'rm -f -- "$tmp" ${tmpj:+"$tmpj"} ${tmpc:+"$tmpc"}' EXIT

# Extração: uma linha pequena por resposta (k=u), por aviso de limite da janela de 5 horas (k=h) e por /usage rodado (k=r
# leitura, k=rx formato que não reconheço). O /usage vem do registro system/local_command da própria sessão: do
# usageReport.rate_limits.limits (f=usageReport: item session, e weekly_all quando houver) ou, sem ele, do texto
# "Current session: <n>% used" (f=texto, sem fim da janela). O resets_at perde a fração de segundo e aceita Z e ±HH:MM.
# s: 1 = transcript desta sessão, 2 = subagente desta sessão, 0 = outra.
if [ -d "$trans" ]; then
  find "$trans" -type f -name '*.jsonl' -mmin "-$minutos" -exec jq -cR --arg sid "$sessao" '
    def epoch: sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null;
    # resets_at (ISO com fração de segundo e Z ou ±HH:MM, ou ±HHMM) como epoch inteiro; null se não for isso
    def resets: if type != "string" then null else
        (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$")? // null) as $c
        | if $c == null then null else
            (($c.d + "Z") | try fromdateiso8601 catch null) as $e
            | if $e == null then null
              elif $c.z == "Z" then $e
              else ($c.z | capture("^(?<sg>[+-])(?<zh>[0-9]{2}):?(?<zm>[0-9]{2})$")) as $o
                | if ($o.zh | tonumber) > 23 or ($o.zm | tonumber) > 59 then null
                  else $e - ((($o.zh | tonumber) * 3600 + ($o.zm | tonumber) * 60) * (if $o.sg == "-" then -1 else 1 end)) end
              end
          end
      end;
    def pctnum: if type == "number" and . >= 0 and . <= 100 then . else null end;
    def leitura($ts):
      ((.usageReport | if type == "object" then .rate_limits else null end) | if type == "object" then .limits else null end | if type == "array" then . else null end) as $lim
      | (if $lim == null then null else ([$lim[] | select(type == "object" and .kind == "session" and (.percent | pctnum) != null)] | first) end) as $ses
      | (if $lim == null then null else ([$lim[] | select(type == "object" and .kind == "weekly_all" and (.percent | pctnum) != null)] | first) end) as $sem
      | ((.content | if type == "string" then . else "" end) as $c
         | ($c | capture("Current session: *(?<p>[0-9]+(\\.[0-9]+)?)% used")? // null) as $m
         | {m: (if $m == null then null else ($m.p | tonumber | pctnum) end), pct: ($c | test("[0-9] *%"))}) as $tx
      | if $ses != null then
          {k: "r", ts: $ts, pct: $ses.percent, fim: ($ses.resets_at | resets),
           sem: ($sem.percent // null), semfim: (if $sem == null then null else ($sem.resets_at | resets) end), f: "usageReport"}
        elif $tx.m != null then {k: "r", ts: $ts, pct: $tx.m, fim: null, sem: null, semfim: null, f: "texto"}
        elif (.usageReport != null) or $tx.pct then {k: "rx", ts: $ts}
        else empty end;
    fromjson? | select(type == "object")
    | (.timestamp | if type == "string" then epoch else null end) as $ts | select($ts != null)
    | select(.type == "assistant" or (.type == "system" and .subtype == "local_command" and ((.commandRun | if type == "object" then .command else null end) == "usage")))
    | if .type == "system" then leitura($ts)
      elif .apiErrorStatus != null or .isApiErrorMessage == true then
        ((.message.content // []) | if type == "array" then ((.[0].text? // "") | tostring) else tostring end) as $t
        | select($t | test("session limit")) | {k: "h", ts: $ts, t: ($t | .[0:200])}
      elif (.message.usage | type) == "object" then
        input_filename as $f
        | {k: "u", ts: $ts, id: ((.message.id // "" | tostring) + ":" + (.requestId // "" | tostring)),
           m: (.message.model // "" | tostring | .[0:60]), sc: (.isSidechain == true),
           s: (if $sid == "" then 0 elif ($f | endswith("/" + $sid + ".jsonl")) then 1
               elif ($f | contains("/" + $sid + "/")) then 2 else 0 end),
           u: (.message.usage | [.input_tokens, .output_tokens, .cache_creation_input_tokens, .cache_read_input_tokens]
               | map(if type == "number" then . else 0 end))}
      elif $sid != "" and (input_filename | endswith("/" + $sid + ".jsonl")) then {k: "a"}
      else empty end
  ' {} + >"$tmp" 2>/dev/null
else
  avisos+=" · pasta de transcripts não encontrada: $trans"
fi

# O horário do aviso de limite vem no fuso do usuário, com o nome dele entre parênteses. A conta da hora usa esse fuso.
tz=$(jq -r 'select(.k == "h") | .t | (capture("\\((?<z>[A-Za-z0-9_/+-]+)\\)\\s*$").z? // empty)' "$tmp" 2>/dev/null | tail -n 1)

# Transcript desta sessão mexido há pouco: se ele tem resposta do modelo (fora as de erro) e nenhum registro de uso sai
# dele, o formato mudou. A extração marca essas respostas com k=a.
sessao_recente=0
if [ -n "$sessao" ] && [ -d "$trans" ]; then
  [ -n "$(find "$trans" -type f -name "$sessao.jsonl" -mmin -10 -print -quit 2>/dev/null)" ] && sessao_recente=1
fi

stlj=null
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" != claude-desktop ] && [ -r "$stl" ]; then
  stlj=$(jq -c --argjson agora "$agora" '
    if type == "object" and .versao == 1 and (.cinco_horas.usado | type) == "number"
       and ((.gravado_em // 0) | type == "number" and . >= $agora - 600) then . else null end' "$stl" 2>/dev/null) || stlj=null
  [ -n "$stlj" ] || stlj=null
fi

saida=$(env ${tz:+TZ="$tz"} jq -s -r \
  --argjson agora "$agora" --argjson pcl "$pcl" --argjson janela_env "$janela_env" --argjson inicio "$((agora - minutos * 60))" \
  --arg sid "$sessao" --argjson cal "$calj" --argjson stl "$stlj" --arg calibrar "$calibrar" --argjson em "$em" --arg script "$0" \
  --argjson sessao_recente "$sessao_recente" '
  def mediana: sort | .[(length - 1) / 2 | floor];
  def fmt: if . >= 1000000 then "\((. / 100000 | floor) / 10) mi" else "\(. / 1000 | floor) mil" end | gsub("\\."; ",");
  def pct: (. * 10 + 1e-9 | floor) / 10;
  # Deslocamento do fuso do sistema em um instante, como UTC-03:00.
  def fuso: (((localtime | mktime) - .) as $o | ($o | if . < 0 then -. else . end) as $a
    | def p2: tostring | if length < 2 then "0" + . else . end;
      "UTC\(if $o < 0 then "-" else "+" end)\($a / 3600 | floor | p2):\(($a % 3600) / 60 | floor | p2)");
  # Hora de reinício do aviso ("resets 1:10pm", "resets 11am") como epoch: a próxima ocorrência depois do aviso, até 5h10.
  def reinicio($ts):
    (capture("resets (?<h>[0-9]{1,2})(:(?<m>[0-9]{2}))?(?<ap>am|pm)")? // null) as $c
    | if $c == null then null else
        ((($c.h | tonumber) % 12) + (if $c.ap == "pm" then 12 else 0 end)) as $H
        | (($c.m // "0") | tonumber) as $M
        | ($ts | floor) as $t
        | (($t | localtime | mktime) - $t) as $off
        | ($t | localtime) as $l
        | ([$l[0], $l[1], $l[2], $H, $M, 0, 0, 0] | mktime) - $off
        | if . <= $t then . + 86400 else . end
        | if . - $t <= 18600 then . else null end
      end;

  (map(select(.k == "u")) | unique_by(.id) | map(. + {x: (.u[0] + .u[1] + .u[2]), y: .u[3]}) | sort_by(.ts)) as $us
  | if $sessao_recente == 1 and (map(select(.k == "a")) | length) > 0 and ([$us[] | select(.s == 1)] | length) == 0 then
      "formato", "o transcript desta sessão tem resposta do modelo e nenhum registro de uso que eu reconheça: o formato do Claude Code pode ter mudado, e a estimativa daria 0% em silêncio"
    else
  (map(select(.k == "h")) | map(.ts as $t | {ts: $t, r: (.t | reinicio($t))}) | map(select(.r != null))
     | group_by(.r) | map({r: .[0].r, hit: (map(.ts) | min)})) as $hits
  # /usage rodado pelo usuário (k=r). fim fora de 0 a 18.060 s depois da leitura não é o fim de uma janela de 5 horas:
  # a leitura vale pelo percentual e perde o fim. k=rx são os que não consegui ler.
  | (map(select(.k == "r")) | unique_by(.ts)
     | map(if .fim != null and ((.fim - .ts) < 0 or (.fim - .ts) > 18060) then .fim = null else . end)) as $leit
  | (map(select(.k == "rx") | .ts)) as $rxts
  # Janelas que o reduce abaixo usa: as dos avisos de limite e as que o /usage deu (fim arredondado para o minuto).
  # Só os avisos de limite viram ponto de calibração e "bateu no limite" ($hits); o /usage entra aqui e nas leituras.
  | ([$hits[] | {r}] + [$leit[] | select(.fim != null) | {r: ((.fim / 60 | round) * 60)}] | unique_by(.r)) as $janelas

  # Janelas em sequência; a de um aviso de limite ou do /usage manda sobre a estimada.
  | (reduce $us[] as $e ({ini: 0, fim: 0, x: 0, y: 0};
      ([$janelas[] | select(.r - 18000 <= $e.ts and $e.ts < .r)] | first) as $a
      | if $a != null then
          (if .fim == $a.r then .x += $e.x | .y += $e.y else {ini: ($a.r - 18000), fim: $a.r, x: $e.x, y: $e.y} end)
        elif $e.ts < .fim then .x += $e.x | .y += $e.y
        else (($e.ts / 600 | floor) * 600) as $i | {ini: $i, fim: ($i + 18000), x: $e.x, y: $e.y}
        end)) as $bloco
  | ($bloco.fim > $agora) as $aberta
  | ($bloco.x + $pcl * $bloco.y) as $w

  # Pontos de calibração: janela inteira dentro da varredura e aberta por uso que aparece nos transcripts (até 10 min
  # depois do início). Janela aberta pelo claude.ai ou por outra máquina sairia com total baixo demais.
  | ([$hits[] | select(.r - 18000 >= $inicio) | . as $h
      | [$us[] | select(.ts >= $h.r - 18000 and .ts <= $h.hit)] as $j
      | select(($j | length) > 0 and (($j | map(.ts) | min) - ($h.r - 18000)) < 600)
      | {r: $h.r, hit: $h.hit, x: ($j | map(.x) | add), y: ($j | map(.y) | add)}]) as $novos
  | ((if $calibrar == "auto" then [] else ($cal.pontos // []) end) + $novos | unique_by(.r) | sort_by(.r) | .[-30:]) as $pontos
  # Leitura do /usage: o percentual lido em $em, contra o total da janela até $em.
  | (if $calibrar != "" and $calibrar != "auto" then
       ([$us[] | select(.ts >= $bloco.ini and .ts <= $em)]) as $ate
       | (if $aberta and $em >= $bloco.ini and $em <= $agora and ($ate | length) > 0
          then {em: $em, pct: ($calibrar | tonumber), x: ($ate | map(.x) | add), y: ($ate | map(.y) | add)} else "erro" end)
     else null end) as $nova
  | if $nova == "erro" then "erro", "--calibrar: a hora da leitura não cai na janela de 5 horas aberta nos transcripts (ou não há janela aberta agora)"
    else
  ((($cal.leituras // []) + (if $nova != null then [$nova] else [] end)) | group_by(.em) | map(last)) as $guardadas
  # Leituras do /usage que o transcript trouxe: a janela delas começa dentro da varredura (sem fim: cai na janela aberta)
  # e o x e o y são o uso da janela até a hora da leitura. Abaixo de 10% (o piso do --calibrar) a leitura é âncora só
  # nesta execução: não vai para o arquivo nem é ponto de limite.
  | ([$leit[] | select(.ts <= $agora) | . as $r
      | (if $r.fim != null then ($r.fim - 18000 >= $inicio) else ($aberta and $r.ts >= $bloco.ini and $r.ts < $bloco.fim) end) as $vale
      | select($vale)
      | (if $r.fim != null then $r.fim - 18000 else $bloco.ini end) as $ij
      | [$us[] | select(.ts >= $ij and .ts <= $r.ts)] as $ate
      | {em: $r.ts, pct: $r.pct, x: (($ate | map(.x) | add) // 0), y: (($ate | map(.y) | add) // 0), f: "transcript"}
        + (if $r.fim != null then {fim: $r.fim} else {} end)]) as $dotr
  # Manual e do transcript com o mesmo pct a até 15 minutos uma da outra são a mesma leitura: fica a do transcript, com
  # o x e o y da manual (a que passou na guarda). Leitura já gravada com o mesmo em também mantém o x e o y gravados.
  | (reduce ($dotr | map(select(.pct >= 10))[]) as $t ({s: $guardadas, t: []};
      ([.s[] | select(.em == $t.em or ((.f // "manual") != "transcript" and .pct == $t.pct and ((.em - $t.em) | fabs) <= 900))]
        | sort_by((.em - $t.em) | fabs) | first) as $m
      | if $m == null then .t += [$t]
        else .s |= map(select(. != $m)) | .t += [$t + {x: $m.x, y: $m.y}] end)) as $mescla
  | (($mescla.s + $mescla.t) | group_by(.em) | map(last) | sort_by(.em) | .[-10:]) as $leituras
  | (($leituras + ($dotr | map(select(.pct < 10)))) | sort_by(.em)) as $ancoras
  # Cada ponto estima o limite (limite batido = 100%; leitura = o percentual lido). Vale o menor dos 5 mais recentes.
  | (([$pontos[] | {t: .hit, l: (.x + $pcl * .y), k: "l"}] + [$leituras[] | select(.pct > 0) | {t: .em, l: ((.x + $pcl * .y) / (.pct / 100)), k: "u"}])
     | map(select(.l > 0)) | sort_by(.t) | .[-5:]) as $rec
  | (if ($rec | length) == 0 then null else
      ($rec | map(.l)) as $v | ($v | add / length) as $m
      | ($rec | map(select(.k == "l")) | length) as $nl | ($rec | map(select(.k == "u")) | length) as $nu
      | {limite: ($v | min),
         rotulo: ("menor de \($v | length) ponto\(if ($v | length) > 1 then "s" else "" end): \($nl) limite\(if $nl == 1 then "" else "s" end) batido\(if $nl == 1 then "" else "s" end) e \($nu) leitura\(if $nu == 1 then "" else "s" end) do /usage"
                  + (if ($v | length) >= 3 and $m > 0 then ", dispersão \(($v | map((. - $m) * (. - $m)) | add / length | sqrt) / $m * 100 | floor)%" else "" end))}
     end) as $limhoje
  # Com a janela aberta e ao menos uma leitura do /usage (do transcript ou digitada) de 10% ou mais dentro dela, o limite
  # é a mediana dos limites que essas leituras dão: a leitura da janela manda sobre os pontos de janelas antigas.
  | ([$leituras[] | select($aberta and .pct >= 10 and .em >= $bloco.ini and .em <= $agora)
      | {em, l: ((.x + $pcl * .y) / (.pct / 100))} | select(.l > 0)]) as $naj
  | (if ($naj | length) > 0 then
      {limite: ($naj | map(.l) | mediana),
       rotulo: "leitura da janela: \($naj | length) leitura\(if ($naj | length) == 1 then "" else "s" end) do /usage, a última às \($naj | map(.em) | max | strflocaltime("%H:%M"))"}
     else $limhoje end) as $lim

  # Contexto: o da última resposta do transcript desta sessão. A janela de 1 milhão se prova pela própria sessão acima de
  # 200 mil; o histórico do modelo (última vez acima de 200 mil, por nome) só vale por 30 dias e sai marcado como deduzido.
  | (($cal.contexto_1m // (($cal.contexto_max // {}) | with_entries(select(.value > 200000) | .value = ($cal.varrido_ate // $agora))))
     | reduce ($us[] | select((.u[0] + .u[2] + .u[3]) > 200000) | {m, ts}) as $e (.; .[$e.m] = ([(.[$e.m] // 0), $e.ts] | max))
     | with_entries(select(.value >= $agora - 2592000))) as $c1m
  | ($us | map(select(.s == 1 and (.sc | not)))) as $dasessao
  | ($dasessao | last) as $ult
  | (if $ult == null then null else ($ult.u[0] + $ult.u[2] + $ult.u[3]) end) as $ctx
  | (if $janela_env > 0 then {n: $janela_env, f: "variavel"}
     elif ($dasessao | map(.u[0] + .u[2] + .u[3]) | max // 0) > 200000 then {n: 1000000, f: "medida"}
     elif $ult != null and $c1m[$ult.m] != null then {n: 1000000, f: "deduzida"}
     else {n: 200000, f: "padrao"} end) as $janx
  | $janx.n as $jan
  # Recibo da leitura nova: a hora gravada, como desfazer e se o limite que ela dá foge dos outros pontos.
  # A leitura manual que o transcript já trazia (mesmo percentual, até 15 minutos) fica com a hora do transcript.
  | (if $nova == null then null else
      ([$leituras[] | select(.em == $nova.em or (.f == "transcript" and .pct == $nova.pct and ((.em - $nova.em) | fabs) <= 900))]
       | sort_by((.em - $nova.em) | fabs) | first | .em) // $nova.em end) as $emnova
  | (if $nova == null then null else
      (($nova.x + $pcl * $nova.y) / ($nova.pct / 100)) as $ln
      | ([$rec[] | select(.k != "u" or .t != $nova.em) | .l] | if length == 0 then null else mediana end) as $med
      | "leitura gravada: \($nova.pct)% às \($nova.em | strflocaltime("%H:%M")) em \($nova.em | fuso), que são \($nova.em | strftime("%H:%M")) UTC"
        + (if $emnova != $nova.em then "; o /usage das \($emnova | strflocaltime("%H:%M")) já trazia essa leitura no transcript, e fica a dele (leitura do transcript o --descartar não apaga)"
           else " (para desfazer: orcamento-local.sh --descartar \($nova.em | todate))" end)
        + (if $med != null and $med > 0 and ($ln / $med > 2 or $ln / $med < 0.5)
           then "; ATENÇÃO: o limite que ela dá é \($ln / $med * 10 | floor | . / 10 | tostring | gsub("\\."; ","))× o dos outros pontos. Se o número foi digitado errado, descarte"
           else "" end)
     end) as $recibo
  | ($us | map(select(.s > 0)) | if length == 0 then null else map(.x + $pcl * .y) | add end) as $tsessao
  | ([$hits[] | select(.r > $agora)] | last) as $limitada
  # 7d sem statusline: a última leitura do /usage com a semana, ainda válida e dentro da janela de 5 horas aberta.
  # Só exibição: a semana não entra em decisão nenhuma.
  | ([$leit[] | select($aberta and (.sem | type) == "number" and (.semfim | type) == "number" and .semfim > $agora
        and .ts >= $bloco.ini and .ts <= $agora)] | last) as $l7
  | (if $l7 == null then null else {usado: $l7.sem, reinicia: $l7.semfim, visto_em: $l7.ts} end) as $d7leitura
  # /usage que não consegui ler, depois da última varredura: aviso uma vez, com a hora do mais recente.
  | ($rxts | map(select(. > ($cal.varrido_ate // 0))) | max) as $rxn
  | ([$ancoras[] | select(.em >= $bloco.ini and .em <= $agora)] | last) as $anc
  | (if $anc == null then null else $w - ($anc.x + $pcl * $anc.y) end) as $depois

  | (if $stl != null then {fonte: "statusline", c5: $stl.cinco_horas, d7: $stl.sete_dias, script: ($stl.script // "")}
     elif $limitada != null then {fonte: "jsonl", c5: {usado: 100, reinicia: $limitada.r, visto_em: $agora}}
     elif $lim == null then {fonte: "jsonl", c5: {usado: null, reinicia: (if $aberta then $bloco.fim else null end), visto_em: $agora,
       motivo: "sem calibração: a conta não bateu no limite de 5 horas nos transcripts dos últimos 30 dias e não há leitura do /usage. Rode orcamento-local.sh --calibrar <percentual que o /usage mostra>"}}
     elif $aberta and $anc != null then {fonte: "jsonl", c5: {usado: ($anc.pct + 100 * $depois / $lim.limite), reinicia: $bloco.fim, visto_em: $agora}}
     elif $aberta then {fonte: "jsonl", c5: {usado: (100 * $w / $lim.limite), reinicia: $bloco.fim, visto_em: $agora}}
     else {fonte: "jsonl", c5: {usado: 0, reinicia: null, visto_em: $agora}} end) as $f

  | {versao: 1, harness: "claude-code", fonte: $f.fonte, script: ($f.script // $script), gravado_em: $agora, sessao: $sid,
     cinco_horas: $f.c5, sete_dias: ((if $f.fonte == "statusline" then $f.d7 else $d7leitura end) // {usado: null, reinicia: null, visto_em: null}),
     contexto: {usado: (if $ctx == null then null else 100 * $ctx / $jan end), sessao: $sid, desta_sessao: ($ctx != null),
                tokens: $ctx, janela: $jan, janela_fonte: $janx.f},
     estimativa: {tokens: ($w | floor), limite: ($lim.limite // null | if . == null then null else floor end),
                  calibracao: ($lim.rotulo // null), peso_cache_leitura: $pcl, sessao_tokens: ($tsessao // null | if . == null then null else floor end)}} as $obj

  | ([
      (if $f.fonte == "statusline" then "fonte statusline (5h oficial) e transcripts (contexto)"
       elif $limitada != null then "fonte transcripts: a conta bateu no limite de 5 horas às \($limitada.hit | strflocaltime("%H:%M"))"
       elif $lim == null then "fonte transcripts: ≈ \($w | fmt) tokens ponderados na janela, sem calibração"
       elif $aberta and $anc != null then "âncora: /usage das \($anc.em | strflocaltime("%H:%M")) com \($anc.pct)%, mais ≈ \($depois | fmt) tokens ponderados desde então sobre \($lim.limite | fmt) (\($lim.rotulo))"
       else "estimado pelos transcripts: ≈ \($w | fmt) de \($lim.limite | fmt) tokens ponderados (\($lim.rotulo))" end),
      (if $ctx == null then "contexto não medido: \(if $sid == "" then "sem id de sessão" else "sessão sem resposta nos transcripts" end)"
       else "contexto \($ctx | fmt) de \($jan | fmt)\(if $janx.f == "deduzida" then " (janela deduzida pelo histórico do modelo)" else "" end)" end),
      (if $tsessao == null then empty else "sessão ≈ \($tsessao | fmt) com subagentes" end),
      ($recibo // empty),
      (if $rxn == null then empty else "/usage das \($rxn | strflocaltime("%H:%M")) num formato que não reconheço: leitura ignorada" end)
    ] | join(" · ")) as $nota

  | ($obj | tojson),
    ({versao: 1, varrido_ate: $agora, pontos: $pontos, leituras: $leituras, contexto_1m: $c1m} | tojson),
    $nota
    end
    end
' "$tmp" 2>/dev/null)
rc_jq=$?

json="" calnovo="" nota=""
{ IFS= read -r json; IFS= read -r calnovo; IFS= read -r nota; } <<<"$saida"
if [ "$json" = erro ]; then
  echo "$calnovo${hora_lida:+, hora lida: $hora_lida}$avisos" >&2
  exit 2
fi
if [ "$json" = formato ]; then
  echo "ORCAMENTO desligado — $calnovo · fonte transcripts$avisos"
  exit 0
fi
if [ "$rc_jq" -ne 0 ] || [ -z "$json" ] || [ -z "$calnovo" ]; then
  echo "ORCAMENTO desligado — não consegui ler os transcripts em $trans (jq saiu com $rc_jq)"
  exit 0
fi

# Gravação atômica dos dois arquivos. Falha ao gravar a calibração não impede a linha.
if tmpc=$(mktemp "$dir/.calibracao.XXXXXX") && printf '%s\n' "$calnovo" >"$tmpc" && mv -f "$tmpc" "$cal"; then
  tmpc=""
else
  avisos+=" · calibração não gravada"
fi
if ! { tmpj=$(mktemp "$dir/.orcamento-local.XXXXXX") && printf '%s\n' "$json" >"$tmpj" && mv -f "$tmpj" "$arq"; }; then
  echo "ORCAMENTO desligado — não consegui gravar $arq"
  exit 0
fi
tmpj=""
[ "$recalibrou" = 1 ] && avisos+=" · varredura de 30 dias feita agora"

args=()
[ -n "$tarefa" ] && args+=(--tarefa "$tarefa")
linha=$(bash "$lei" ${args[@]+"${args[@]}"} "$arq")
rc=$?

# --leva: previsão pelo histórico do medir.sh (custos.jsonl), contra o que resta da janela pelo estado que acabou de sair.
if [ -n "$leva" ]; then
  custos=$dir/custos.jsonl
  [ -r "$custos" ] || custos=/dev/null
  prev=$(jq -nr --slurpfile st "$arq" --rawfile h "$custos" --arg leva "$leva" '
    def fmt: if . >= 1000000 then "\((. / 100000 | floor) / 10) mi" else "\(. / 1000 | floor) mil" end | gsub("\\."; ",");
    def mediana: sort | .[length / 2 | floor];
    ($h | split("\n") | map(fromjson? // empty | select(type == "object" and (.ponderado | type) == "number"))) as $hist
    | [$leva | splits(" +") | select(length > 0) | {k: ., p: split(":")[0], m: split(":")[1]}] as $itens
    | [$itens[] as $i
        | [$hist[] | select(.papel == $i.p and .modelo == $i.m and .quedas == 0 and .corridas == 1) | .ponderado] as $v
        | $i + {n: ($v | length), c: (if ($v | length) >= 3 then ($v | mediana) else null end)}] as $prev
    | ($prev | map(.c // 0) | add) as $soma
    | ($prev | map(select(.c != null)) | unique_by(.k) | map("\(.k) \(.c | fmt)") | join(", ")) as $cada
    | ($prev | map(select(.c == null) | .k) | unique) as $sem
    | $st[0].cinco_horas.usado as $u | $st[0].estimativa.limite as $l
    | (if ($u | type) == "number" and ($l | type) == "number" and $l > 0 then ([100 - $u, 0] | max) / 100 * $l else null end) as $resta
    | "leva ≈ \($soma | fmt)"
      + (if $cada == "" then "" else " (\($cada), mediana das corridas limpas)" end)
      + (if ($sem | length) > 0 then ", sem contar \($sem | join(", ")): menos de 3 corridas limpas no histórico" else "" end)
      + " · resta ≈ " + (if $resta == null then "? (sem calibração)" else ($resta | fmt) end)
      + (if $resta == null then "" elif $soma > $resta then ": NÃO CABE" elif ($sem | length) > 0 then ": a parte conhecida cabe" else ": cabe" end)
  ' 2>/dev/null) || prev="leva: não consegui ler o histórico em $custos"
  nota+=" · $prev"
fi
printf '%s · %s%s\n' "$linha" "$nota" "$avisos"
exit "$rc"
