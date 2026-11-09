#!/usr/bin/env python3
# seiva · JulianoSSR · MIT
"""Valida e agrega avaliações fornecidas; não executa modelos e não inventa economia."""
import argparse
import collections
import json
from pathlib import Path
import sys

MODES = {'direta','um-revisor','seiva'}
KINDS = {'simples','varios-arquivos','autorizacao-isolamento','dados','integracao','retomada'}


def validate(rows):
    seen = set()
    for row in rows:
        required = {'run','case','kind','split','mode','real','models','conditions','acceptance',
                    'passed','tokens','monitor_tokens','duration_seconds','defects_detected',
                    'defects_escaped','false_positives','rework_tokens','evidence'}
        if not required <= row.keys():
            raise ValueError('registro incompleto')
        if row['mode'] not in MODES or row['kind'] not in KINDS or row['split'] not in {'calibracao','avaliacao'}:
            raise ValueError('classe/modo/split inválido')
        key = row['run'],row['case'],row['mode']
        if key in seen:
            raise ValueError('execução duplicada')
        seen.add(key)
        if type(row['real']) is not bool or type(row['passed']) is not bool:
            raise ValueError('real/passed precisam ser booleanos')
        if not row['evidence'] or not row['models'] or not row['acceptance'] or not row['conditions']:
            raise ValueError('modelo/condições/evidência ausentes')
        for model in row['models']:
            if not {'app','version','model','effort'} <= model.keys():
                raise ValueError('modelo sem versão ou esforço')
        numeric = [row[k] for k in ('monitor_tokens','duration_seconds','defects_detected',
                   'defects_escaped','false_positives','rework_tokens')]
        numeric += [row['tokens'][k] for k in ('input','output','cache_read','cache_write')]
        if not all(type(v) in (int,float) and v >= 0 and v < float('inf') for v in numeric):
            raise ValueError('métrica inválida/indisponível; não substituir por zero')
        # Entrada inclui ou exclui cache conforme o provedor: o total já precisa ser normalizado pelo produtor.
        if type(row['tokens'].get('total')) not in (int,float) or not 0 <= row['tokens']['total'] < float('inf'):
            raise ValueError('total normalizado ausente')
        if row['tokens']['total'] < row['monitor_tokens'] or row['tokens']['total'] < row['rework_tokens']:
            raise ValueError('total precisa incluir monitor e retrabalho')
    calibration = {r['case'] for r in rows if r['split']=='calibracao'}
    evaluation = {r['case'] for r in rows if r['split']=='avaliacao'}
    if calibration & evaluation:
        raise ValueError('vazamento entre calibração e avaliação')
    return rows


def aggregate(rows):
    validate(rows)
    groups = collections.defaultdict(list)
    for row in rows:
        if row['split']=='avaliacao':groups[(row['run'],row['case'])].append(row)
    comparisons=[]
    for key,group in sorted(groups.items()):
        if {r['mode'] for r in group} != MODES:
            continue
        if len({json.dumps(r['acceptance'],sort_keys=True) for r in group}) != 1 or len({json.dumps(r['conditions'],sort_keys=True) for r in group}) != 1:
            raise ValueError('comparação sem critérios e condições equivalentes')
        measured=all(r['real'] for r in group)
        accepted=all(r['passed'] and r['defects_escaped']==0 for r in group)
        totals={r['mode']:r['tokens']['total'] for r in group}
        comparisons.append({'run':key[0],'case':key[1],'real':measured,'equivalent_quality':accepted,
            'total_tokens':totals,'difference_seiva_vs_direct':totals['seiva']-totals['direta'],
            'economy_proven':measured and accepted and totals['seiva']<totals['direta'],
            'escaped_defects':{r['mode']:r['defects_escaped'] for r in group}})
    return {'schema':1,'runs':len(rows),'comparisons':comparisons,
            'limitations':['dados simulados validam o protocolo; não demonstram economia real',
                            'comparação pareada não estabelece significância estatística',
                            'ausência de execuções não significa economia zero']}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('resultados');parser.add_argument('--saida')
    args=parser.parse_args()
    try:
        rows=[json.loads(line) for line in Path(args.resultados).read_text().splitlines() if line.strip()]
        if not rows:raise ValueError('nenhuma execução registrada')
        result=aggregate(rows)
        content=json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n'
        if args.saida:
            from monitor import atomic
            atomic(Path(args.saida),result)
        print(content,end='')
    except (OSError,ValueError,TypeError,KeyError):
        print('avaliação recusada: formato, métricas ou equivalência inválidos',file=sys.stderr)
        return 2
    return 0


if __name__=='__main__':raise SystemExit(main())
