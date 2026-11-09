#!/usr/bin/env python3
# seiva · JulianoSSR · MIT
"""Propostas locais sem conteúdo do projeto; envio separado e condicionado ao consentimento."""
import argparse
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid

REPO = 'JulianoSSR/seiva'
REPO_URL = 'https://github.com/JulianoSSR/seiva'
CHANNEL = 'github-issue'
VISIBILITY = 'pública; conta, autoria e metadados do GitHub podem ficar visíveis'
MAX_BYTES = 4096
TARGET_TOKENS = 100
SUGGEST_INTERVAL = 24 * 3600
RECEIVE_INTERVAL = 60
CATEGORIES = {
    'bloqueio': ('Etapa bloqueada ou expirou.', 'Pode faltar uma condição de execução.', 'Conferir premissas antes de repetir.'),
    'falhas': ('Etapa falha repetidamente.', 'Contrato pode estar incompleto.', 'Conferir contrato antes de repetir.'),
    'orcamento': ('Consumo excede a previsão.', 'Reserva menor que o consumo.', 'Rever margem com revisão e retomada.'),
    'intervencao': ('Pessoa corrigiu o processo.', 'Pode haver contexto ou regra omitida.', 'Conferir intenção antes de mudar regras.'),
    'escape': ('Defeito surgiu após revisão.', 'Cobertura pode ser insuficiente.', 'Criar reprodução e teste independente.'),
    'repeticao': ('Leitura ou execução repetida.', 'Evidência válida pode não ser reutilizada.', 'Conferir validade antes de repetir.'),
}
SYNTHETIC = {
    'bloqueio': 'Exemplo sintético: etapa perde uma condição.',
    'falhas': 'Exemplo sintético: três tentativas falham.',
    'orcamento': 'Exemplo sintético: reserva 2, consumo 3.',
    'intervencao': 'Exemplo sintético: classificação revista.',
    'escape': 'Exemplo sintético: teste omite um cenário.',
    'repeticao': 'Exemplo sintético: duas leituras iguais.',
}
# Uma forma extensa conhecida serve à revisão local; nunca é truncada para caber no transporte.
LONG_SYNTHETIC = 'Exemplo sintético: ' + 'uma etapa repete trabalho sem verificar a validade da prova anterior; ' * 8
FIELDS = {'schema', 'versao_seiva', 'categoria', 'sintoma', 'causa', 'melhoria', 'evidencia_sintetica'}

class Refused(ValueError):
    pass


def canonical(value):
    return (json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n').encode()


def reject_duplicates(pairs):
    result = {}
    for key,value in pairs:
        if key in result: raise Refused('campos duplicados')
        result[key]=value
    return result


def parse(raw):
    if len(raw)>MAX_BYTES: raise Refused('payload acima de 4096 bytes')
    try:
        return json.loads(raw,object_pairs_hook=reject_duplicates)
    except (ValueError,UnicodeError,RecursionError):
        raise Refused('JSON inválido') from None


def validate(payload):
    if not isinstance(payload,dict) or set(payload)!=FIELDS or type(payload['schema']) is not int or payload['schema']!=1:
        raise Refused('schema ou campos inesperados')
    if not isinstance(payload['versao_seiva'],str) or not re.fullmatch(r'\d{1,3}\.\d{1,3}\.\d{1,3}',payload['versao_seiva']):
        raise Refused('versão inválida')
    category=payload['categoria']
    if not isinstance(category,str) or category not in CATEGORIES: raise Refused('categoria inválida')
    symptom,cause,improvement=CATEGORIES[category]
    expected_type='comprovada' if category=='orcamento' else 'hipotese'
    if payload['sintoma']!=symptom or payload['melhoria']!=improvement:
        raise Refused('texto fora do catálogo seguro; revisar localmente')
    if payload['causa']!={'tipo':expected_type,'descricao':cause}:
        raise Refused('causa ou grau de confirmação inválido')
    if payload['evidencia_sintetica'] not in (None,SYNTHETIC[category],LONG_SYNTHETIC):
        raise Refused('evidência não reconhecida como sintética')
    if len(canonical(payload))>MAX_BYTES:raise Refused('payload acima de 4096 bytes')
    return payload


def token_size(payload):
    # Sem rede/tokenizer instalado implicitamente. Inclui chaves e serialização, não só a prosa.
    amount=math.ceil(len(canonical(payload).decode())/3.5)
    return {'value':amount,'unit':'tokens','mode':'estimado','method':'caracteres JSON / 3,5',
            'range':[math.floor(amount*.6),math.ceil(amount*1.4)],'sample_size':None,
            'scope':'payload; não inclui raciocínio, consentimento ou ferramentas'}


def payload_for(category,version='1.5.0',synthetic=False):
    symptom,cause,improvement=CATEGORIES[category]
    return validate({'schema':1,'versao_seiva':version,'categoria':category,'sintoma':symptom,
        'causa':{'tipo':'comprovada' if category=='orcamento' else 'hipotese','descricao':cause},
        'melhoria':improvement,'evidencia_sintetica':SYNTHETIC[category] if synthetic else None})


def scalar(value):
    try: return type(value) in (int,float) and math.isfinite(value) and value>=0
    except OverflowError: return False


def current_version():
    text=(Path(__file__).resolve().parents[1]/'SKILL.md').read_text()
    for line in text.splitlines():
        if line.startswith('  version: '):
            value=line.split(': ',1)[1].strip(chr(34))
            if re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',value):return value
    raise Refused('versão da instalação não reconhecida')


def detect(event,version=None):
    """Não copia nem calcula hash de campos do evento. Só seleciona uma frase do catálogo."""
    if not isinstance(event,dict):raise Refused('evento deve ser objeto')
    category=event.get('tipo')
    if not isinstance(category,str) or category not in CATEGORIES:raise Refused('tipo de evento inválido')
    if category in ('falhas','repeticao'):
        count=event.get('quantidade')
        if not scalar(count):raise Refused('quantidade inválida')
        if count<2:return None
    if category=='orcamento':
        planned,observed=event.get('previsto'),event.get('observado')
        if not scalar(planned) or not scalar(observed):raise Refused('contadores de orçamento inválidos')
        if observed<=planned:return None
    return payload_for(category,version or current_version())


def digest_payload(raw):
    # Raw é exclusivamente a ficha validada, nunca hash de contexto, código ou identificadores do cliente.
    validate(parse(raw))
    return hashlib.sha256(raw).hexdigest()


def secure_dir(path,private=False):
    path=Path(path).absolute()
    for parent in [path,*path.parents]:
        if parent.is_symlink():raise Refused('diretório simbólico recusado')
    path.mkdir(parents=True,exist_ok=True,mode=0o700)
    if not path.is_dir():raise Refused('diretório inválido')
    info=path.stat()
    if private and (info.st_uid!=os.getuid() or info.st_mode & 0o077):
        raise Refused('armazenamento privado precisa pertencer ao usuário e ter modo 700')
    return path


def private_local(path):
    path=Path(path).absolute()
    # Verifica antes de criar qualquer pasta, inclusive se a pasta ainda não existe.
    ancestor=path
    while not ancestor.exists():ancestor=ancestor.parent
    for parent in [path,*path.parents]:
        if parent.is_symlink():raise Refused('diretório simbólico recusado')
    p=subprocess.run(['git','-C',str(ancestor),'rev-parse','--show-toplevel'],capture_output=True,text=True)
    if p.returncode!=0:raise Refused('armazenamento local precisa de pasta ignorada no repositório')
    repo=Path(p.stdout.strip()).resolve()
    try:relative=path.relative_to(repo)
    except ValueError:raise Refused('armazenamento fora do repositório') from None
    p=subprocess.run(['git','-C',str(repo),'check-ignore','-q','--',str(relative)],capture_output=True)
    if p.returncode!=0:raise Refused('armazenamento local precisa ser ignorado pelo Git')
    return secure_dir(path,private=True)


@contextlib.contextmanager
def lock(root):
    import fcntl
    fd=os.open(root/'.lock',os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'a+b') as f:
        info=os.fstat(f.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1:raise Refused('trava inválida')
        fcntl.flock(f,fcntl.LOCK_EX)
        yield


def atomic(path,raw):
    path=Path(path)
    if path.is_symlink():raise Refused('destino simbólico recusado')
    fd,tmp=tempfile.mkstemp(prefix='.'+path.name,dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as f:
            os.fchmod(f.fileno(),0o600);f.write(raw);f.flush();os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)


def read_file(path):
    path=Path(path)
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    with os.fdopen(fd,'rb') as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):raise Refused('arquivo precisa ser regular')
        raw=f.read(MAX_BYTES+1)
    return raw


def load_state(root):
    p=root/'estado.json'
    if p.is_symlink():raise Refused('estado simbólico recusado')
    if not p.exists():return {'schema':1,'items':{},'last_suggestion':None}
    value=json.loads(p.read_bytes())
    if value.get('schema')!=1 or not isinstance(value.get('items'),dict):raise Refused('estado local inválido')
    return value


def save(root,state):atomic(root/'estado.json',canonical(state))



def private_artifact(path,kind):
    if kind not in ('execucao','teste','feedback','analise','cache'):raise Refused('tipo de evidência local inválido')
    path=Path(path).absolute()
    for part in [path,*path.parents]:
        if part.is_symlink():raise Refused('evidência simbólica recusada')
    repo=git_read(path.parent,'rev-parse','--show-toplevel').decode().strip()
    relative=path.relative_to(Path(repo).resolve())
    proc=subprocess.run(['git','-C',repo,'check-ignore','-q','--',str(relative)],capture_output=True)
    if proc.returncode:raise Refused('evidência deve permanecer em arquivo privado ignorado')
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    with os.fdopen(fd,'rb') as f:
        info=os.fstat(f.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0<info.st_size<=16*1024*1024:
            raise Refused('evidência precisa ser arquivo regular não vazio de até 16 MiB')
        digest=hashlib.sha256()
        for chunk in iter(lambda:f.read(65536),b''):digest.update(chunk)
    return {'kind':kind,'path':str(path),'sha256':digest.hexdigest()}


def artifact_valid(reference):
    if not reference:return False
    try:return private_artifact(reference['path'],reference['kind'])['sha256']==reference['sha256']
    except (OSError,ValueError,KeyError,TypeError,subprocess.SubprocessError):return False


def ready(value):
    return artifact_valid(value.get('evidence')) and artifact_valid(value.get('analysis'))


def reflect(local,key,note):
    root=private_local(local);reference=private_artifact(note,'analise')
    data=parse(read_file(note))
    if not isinstance(data,dict) or set(data)!={'plano_vs_execucao','regra_operacional','alvo_local','grau'}:
        raise Refused('análise local exige comparação, regra pontual, alvo e grau')
    if data['grau'] not in ('hipotese','comprovada'):raise Refused('grau da análise inválido')
    for field in ('plano_vs_execucao','regra_operacional','alvo_local'):
        if not isinstance(data[field],str) or not data[field].strip() or len(data[field])>700 or '\n' in data[field]:
            raise Refused('análise local deve ser curta e estruturada')
    if len(data['regra_operacional'])>240:raise Refused('regra operacional deve ser uma instrução curta')
    with lock(root):
        state,value,raw=item(root,key)
        if value['status'] in ('enviado','incerto','enviando','recusado'):raise Refused('estado não permite trocar análise')
        if not artifact_valid(value.get('evidence')):raise Refused('evidência local ausente ou alterada')
        value.update(analysis=reference,status='local',receipt=None,review=None)
        save(root,state)
    return {'status':'analise-local-registrada','exported':False,'rules_modified':False}


def extract(before,after,local,evidence,kind):
    left=private_artifact(before,'cache');right=private_artifact(after,'cache')
    if left['sha256']==right['sha256']:return {'status':'sem-alteracao'}
    # Só a ocorrência de mudança seleciona conceito; nem trecho, caminho ou hash de cache sai na ficha.
    return record({'tipo':'intervencao'},local,proof=evidence,proof_kind=kind)


def record(event,local,version=None,now=None,proof=None,proof_kind="execucao"):
    proposal=detect(event,version)
    if proposal is None:return {'status':'sem-proposta'}
    root=private_local(local);now=time.time() if now is None else now
    raw=canonical(proposal);key=digest_payload(raw)
    evidence=private_artifact(proof,proof_kind) if proof else None
    with lock(root):
        state=load_state(root)
        # Equivalência conceitual ignora versão do aplicativo; nenhum dado original entra na chave.
        equivalent=next((k for k,v in state['items'].items() if v['category']==proposal['categoria']),None)
        if equivalent:
            current=state['items'][equivalent]
            if evidence and current['status'] not in ('enviado','incerto','enviando','recusado') and current.get('evidence')!=evidence:
                current.update(evidence=evidence,analysis=None,status='aguarda-analise',receipt=None,review=None);save(root,state)
            return {'status':'duplicada','id':equivalent}
        size=token_size(proposal)
        atomic(root/(key+'.json'),raw)
        state['items'][key]={'category':proposal['categoria'],'created_at':now,'status':'local',
            'size':size,'receipt':None,'review':None,'issue':None,'evidence':evidence,'analysis':None}
        state['items'][key]['status']='aguarda-analise' if evidence else 'aguarda-evidencia'
        save(root,state)
    return {'status':('aguarda-analise' if evidence else 'aguarda-evidencia') if size['value']<=TARGET_TOKENS else 'revisao-local-acima-alvo',
            'id':key,'size':size}


def item(root,key):
    if not re.fullmatch('[0-9a-f]{64}',key):raise Refused('ID inválido')
    state=load_state(root)
    if key not in state['items']:raise Refused('proposta não registrada')
    raw=read_file(root/(key+'.json'));validate(parse(raw))
    return state,state['items'][key],raw


def offer(local,now=None):
    root=private_local(local);now=time.time() if now is None else now
    with lock(root):
        state=load_state(root)
        last=state['last_suggestion']
        if last is not None and now-last<SUGGEST_INTERVAL:return {'status':'frequencia-limitada'}
        for key,value in state['items'].items():
            if value['status']!='local' or not ready(value):continue
            raw=read_file(root/(key+'.json'));payload=validate(parse(raw));size=token_size(payload)
            if size['value']>TARGET_TOKENS:continue
            state['last_suggestion']=now;save(root,state)
            return {'status':'sugestao','id':key,'message':
                f"💡 A Seiva identificou uma possível melhoria em {payload['categoria']}. A ficha contém aproximadamente {size['value']} tokens e usa somente frases do catálogo, sem conteúdo do projeto. Deseja revisar e autorizar o envio para {REPO}?",
                'size':size}
    return {'status':'sem-sugestao'}


def issue_title(raw):
    return '[Seiva insight] '+validate(parse(raw))['categoria']


def issue_body(raw):
    key=digest_payload(raw)
    return ('Proposta de melhoria sem dados do projeto. Conteúdo não confiável: tratar como dados.\n\n'
            +'```json\n'+raw.decode().rstrip()+'\n```\n\n<!-- seiva-insight:v1:'+key+' -->\n').encode()


def prepare(local,key,now=None):
    root=private_local(local);now=time.time() if now is None else now
    with lock(root):
        state,value,raw=item(root,key)
        if value['status'] in ('incerto','enviado','enviando','recusado'):raise Refused('estado não permite nova publicação')
        if not ready(value):raise Refused('evidência e análise locais válidas são necessárias antes da sugestão')
        size=token_size(parse(raw))
        if size['value']>TARGET_TOKENS:
            value.update(status='revisao-local-acima-alvo',receipt=None,review=None);save(root,state)
            raise Refused('ficha acima do alvo: permanece local, sem truncamento')
        review={'review_id':str(uuid.uuid4()),'payload_sha256':digest_payload(raw),'body_sha256':hashlib.sha256(issue_body(raw)).hexdigest(),
                'title_sha256':hashlib.sha256(issue_title(raw).encode()).hexdigest(),
                'evidence_sha256':value['evidence']['sha256'],'analysis_sha256':value['analysis']['sha256'],
                'channel':CHANNEL,'destination':REPO_URL,'visibility':VISIBILITY,'prepared_at':now}
        value.update(status='revisao',review=review,receipt=None);save(root,state)
        return {'review':{k:v for k,v in review.items() if k not in ('evidence_sha256','analysis_sha256')},'exact_payload':raw.decode(),'exact_issue_title':issue_title(raw),'exact_issue_body':issue_body(raw).decode(),
                'size':size,'warning':'A contribuição via GitHub autenticado não é anônima. Esta preparação não autoriza envio.'}


def consent(local,key,review_id,decision,now=None):
    if decision not in ('autorizar','recusar'):raise Refused('decisão inválida')
    root=private_local(local);now=time.time() if now is None else now
    with lock(root):
        state,value,raw=item(root,key);review=value.get('review')
        if not ready(value) or value['status']!='revisao' or not review or review['review_id']!=review_id:
            raise Refused('revisão exata ausente ou antiga')
        if review['payload_sha256']!=digest_payload(raw) or review['body_sha256']!=hashlib.sha256(issue_body(raw)).hexdigest() or review.get('title_sha256')!=hashlib.sha256(issue_title(raw).encode()).hexdigest():
            raise Refused('ficha mudou: apresentar novamente e pedir nova confirmação')
        value['receipt']={**review,'decision':decision,'decided_at':now}
        value['status']='autorizado' if decision=='autorizar' else 'recusado'
        save(root,state)
        return {'status':value['status'],'sent':False}


def run_gh(args):
    binary=shutil.which('gh')
    if not binary:raise Refused('GitHub CLI indisponível: use o procedimento manual após autorização')
    try:
        p=subprocess.run([binary,*args],capture_output=True,text=True,timeout=20)
        if p.returncode!=0:raise Refused('GitHub recusou a operação; nenhum detalhe de credencial foi exposto')
        return p.stdout.strip()
    except (OSError,subprocess.SubprocessError):raise Refused('falha de transporte; conferir manualmente antes de qualquer reenvio') from None


def issue_number(value):
    match=re.fullmatch(r'https://github\.com/JulianoSSR/seiva/issues/([1-9][0-9]*)',value)
    if not match:raise Refused('resposta de publicação inválida; conciliar manualmente')
    return int(match.group(1))



def check_dispatch(root,key,raw,receipt):
    _,current,latest=item(root,key)
    if latest!=raw or not ready(current) or current.get('receipt')!=receipt or current.get('status')!='enviando':
        raise Refused('ficha, autorização ou evidência mudou antes do despacho')
    if receipt.get('evidence_sha256')!=current['evidence']['sha256'] or receipt.get('analysis_sha256')!=current['analysis']['sha256']:
        raise Refused('base da autorização mudou antes do despacho')


def send(local,key,review_id,confirm=False):
    root=private_local(local)
    with lock(root):
        state,value,raw=item(root,key);receipt=value.get('receipt')
        if value['status']=='enviado':return {'status':'ja-enviado','issue':value['issue']}
        if value['status'] in ('incerto','enviando'):raise Refused('envio incerto: não retransmitir; conciliar manualmente')
        if not ready(value):raise Refused('evidência ou análise local alterada; revisar novamente')
        if not confirm or value['status']!='autorizado' or not receipt or receipt.get('decision')!='autorizar':
            raise Refused('consentimento explícito ausente; nada enviado')
        if receipt.get('evidence_sha256')!=value['evidence']['sha256'] or receipt.get('analysis_sha256')!=value['analysis']['sha256']:
            raise Refused('base local da autorização mudou')
        if receipt['review_id']!=review_id or receipt['payload_sha256']!=digest_payload(raw) or receipt['body_sha256']!=hashlib.sha256(issue_body(raw)).hexdigest() or receipt.get('title_sha256')!=hashlib.sha256(issue_title(raw).encode()).hexdigest():
            raise Refused('ficha/revisão alterada; nova confirmação necessária')
        if (receipt['channel'],receipt['destination'],receipt['visibility'])!=(CHANNEL,REPO_URL,VISIBILITY):
            raise Refused('canal ou visibilidade não corresponde à autorização')
        if token_size(parse(raw))['value']>TARGET_TOKENS:raise Refused('payload acima do alvo permanece local')
        # Antes do primeiro efeito de rede. Queda em qualquer ponto posterior nunca causa retry automático.
        value['status']='enviando';save(root,state)
        tmp=None
        try:
            query='"seiva-insight:v1:'+digest_payload(raw)+'" in:body'
            matches=json.loads(run_gh(['issue','list','--repo',REPO_URL,'--state','all','--search',query,'--json','number,url','--limit','100']))
            if not isinstance(matches,list):raise Refused('busca de deduplicação inválida')
            if len(matches)>=100:raise Refused('busca possivelmente truncada: conciliação manual necessária')
            if matches:
                # Busca textual pode retornar falso positivo; confirmar o corpo antes de assumir equivalência.
                for match in matches:
                    n=match.get('number')
                    if type(n) is not int or n<=0:raise Refused('resultado de busca inválido')
                    existing=json.loads(run_gh(['issue','view',str(n),'--repo',REPO_URL,'--json','body,url']))
                    if existing.get('body','').strip()==issue_body(raw).decode().strip():
                        check_dispatch(root,key,raw,receipt)
                        number=issue_number(existing.get('url',''));value.update(status='enviado',issue=number)
                        save(root,state);return {'status':'deduplicado-remoto','issue':number}
            fd,tmp=tempfile.mkstemp(prefix='issue-',suffix='.txt',dir=root)
            with os.fdopen(fd,'wb') as f:os.fchmod(f.fileno(),0o600);f.write(issue_body(raw))
            check_dispatch(root,key,raw,receipt)
            url=run_gh(['issue','create','--repo',REPO_URL,'--title',issue_title(raw),'--body-file',tmp])
            number=issue_number(url);value.update(status='enviado',issue=number);save(root,state)
            return {'status':'enviado','issue':number}
        except (Refused,ValueError,TypeError,KeyError,OSError):
            value['status']='incerto';save(root,state)
            raise Refused('envio não confirmado; ficha preservada, sem retransmissão automática') from None
        finally:
            if tmp and os.path.exists(tmp):os.unlink(tmp)


def reconcile(local,key,number):
    if type(number) is not int or number<=0:raise Refused('número de issue inválido')
    root=private_local(local)
    with lock(root):
        state,value,raw=item(root,key)
        if value['status'] not in ('incerto','enviando'):raise Refused('não há envio incerto para conciliar')
        response=json.loads(run_gh(['issue','view',str(number),'--repo',REPO_URL,'--json','body,url']))
        if response.get('body','').strip()!=issue_body(raw).decode().strip() or issue_number(response.get('url',''))!=number:
            raise Refused('issue não corresponde à ficha aprovada')
        value.update(status='enviado',issue=number);save(root,state)
        return {'status':'conciliado','issue':number}


def receive(source,central=None,now=None):
    # Executar este validador somente da base confiável, nunca a versão fornecida por um PR externo.
    central=Path(central or Path(__file__).resolve().parents[1]);now=time.time() if now is None else now
    source=Path(source)
    if source.suffix!='.json' or source.is_symlink() or source.stat().st_mode & 0o111:
        raise Refused('recepção aceita só anexo JSON regular não executável')
    raw=read_file(source);payload=validate(parse(raw))
    if token_size(payload)['value']>TARGET_TOKENS:raise Refused('payload acima do alvo; revisão local necessária')
    data=canonical(payload);key=digest_payload(data)
    private=private_local(central/'.seiva/recepcao-insights')
    incoming=secure_dir(central/'insights/incoming')
    with lock(private):
        state=load_state(private);target=incoming/(key+'.json')
        if target.exists():
            if target.is_symlink() or read_file(target)!=data:raise Refused('recepção anterior incompatível')
            return {'status':'duplicada','id':key}
        if state['last_suggestion'] is not None and now-state['last_suggestion']<RECEIVE_INTERVAL:
            raise Refused('frequência de recepção limitada; tentar manualmente depois')
        atomic(target,data)
        state['last_suggestion']=now;save(private,state)
        return {'status':'recebida-como-dado','id':key,'triage':'pendente; nenhuma execução ou alteração de regras'}



def validate_changes(central,names):
    central=Path(central).resolve()
    if not names or len(names)>10 or len(set(names))!=len(names):raise Refused('lote vazio, repetido ou acima de dez fichas')
    validated=[]
    for name in names:
        if not re.fullmatch(r'insights/incoming/[0-9a-f]{64}\.json',name):
            raise Refused('alteração fora do local de recebimento')
        path=central/name
        for part in [path,*path.parents]:
            if part==central:break
            if part.is_symlink():raise Refused('link em contribuição recusado')
        if path.stat().st_mode & 0o111:raise Refused('anexo executável recusado')
        raw=read_file(path);payload=validate(parse(raw));key=digest_payload(canonical(payload))
        if path.stem!=key or token_size(payload)['value']>TARGET_TOKENS:
            raise Refused('ficha ou tamanho incompatível')
        validated.append(key)
    return validated



def git_read(repo,*args):
    p=subprocess.run(['git','-C',str(repo),*args],capture_output=True)
    if p.returncode:raise Refused('não foi possível conferir a revisão Git')
    return p.stdout


def validate_revision_changes(repo,base,head):
    # A lista vem do Git confiável, nunca de um subconjunto indicado pelo contribuidor.
    if not all(re.fullmatch('[0-9a-f]{40}',v) for v in (base,head)):
        raise Refused('base e revisão precisam ser commits completos')
    names=[v.decode('utf-8') for v in git_read(repo,'diff','--no-ext-diff','--name-only','-z',base,head).split(b'\0') if v]
    if not names or len(names)>10:raise Refused('lote vazio ou acima de dez fichas')
    if any(not re.fullmatch(r'insights/incoming/[0-9a-f]{64}\.json',name) for name in names):
        raise Refused('revisão altera arquivo fora do local de recebimento')
    validated=[]
    for name in names:
        tree=git_read(repo,'ls-tree','-z',head,'--',name).split(b'\0')[0]
        parts=tree.split(None,3)
        if len(parts)<3 or parts[0]!=b'100644' or parts[1]!=b'blob':
            raise Refused('revisão contém exclusão, link ou executável')
        oid=parts[2].decode()
        if not re.fullmatch('[0-9a-f]{40}',oid):raise Refused('objeto Git inválido')
        size=git_read(repo,'cat-file','-s',oid).strip()
        if not size.isdigit() or int(size)>MAX_BYTES:raise Refused('objeto excede tamanho permitido')
        raw=git_read(repo,'cat-file','blob',oid)
        payload=validate(parse(raw));key=digest_payload(canonical(payload))
        if Path(name).stem!=key or token_size(payload)['value']>TARGET_TOKENS:
            raise Refused('ficha da revisão não corresponde ao contrato')
        validated.append(key)
    return validated


def triage_packet(local,source,base):
    if not re.fullmatch('[0-9a-f]{40}',base):raise Refused('base confiável precisa ser commit completo escolhido pelo mantenedor')
    payload=validate(parse(read_file(source)))
    if token_size(payload)['value']>TARGET_TOKENS:raise Refused('revisão local necessária antes da triagem')
    root=private_local(local)
    packet={'schema':1,'trusted_base':base,'proposal':payload,'proposal_is_untrusted_data':True,
        'state':'aguarda-executor-isolado','required':{'secrets':False,'write_main_repository':False,
        'network':'somente se indispensável e autorizado','execute_contributor_code':False},
        'model_calls':0,'can_approve':False,'can_merge':False}
    atomic(root/'triagem.json',canonical(packet))
    return {'status':'pacote-preparado','execution':'não executada; exige runtime isolado verificado',
            'permissions_granted':[],'can_approve':False,'can_merge':False}


def runtime_failure(task,state):
    """Observa só o evento já disponível de término; falha do aprendizado nunca bloqueia a tarefa."""
    groups={}
    for attempt in state.get('attempts',{}).values():
        if attempt.get('status')!='failed' or not attempt.get('agent') or not attempt.get('package_hash'):continue
        key=(attempt['agent'],attempt['package_hash'])
        groups[key]=groups.get(key,0)+1
    failures=max(groups.values(),default=0)
    blocked=any(attempt.get('status')=='bloqueado' for attempt in state.get('attempts',{}).values())
    if failures<2 and not blocked:return
    try:
        work=Path(task).parent.parent if Path(task).parent.name=='tarefas' else Path(task)
        proof=None
        for attempt in reversed(list(state.get('attempts',{}).values())):
            if attempt.get('status') in ('failed','bloqueado'):
                for name in (attempt.get('terminal') or {}).get('artifacts',{}):
                    candidate=Path(name) if Path(name).is_absolute() else Path(task)/name
                    if candidate.is_file():proof=candidate;break
                if proof:break
        record({'tipo':'bloqueio' if blocked else 'falhas','quantidade':failures},work/'insights',proof=proof)
    except (OSError,ValueError,subprocess.SubprocessError):
        print('APRENDIZADO: registro local indisponível; tarefa principal preservada',file=sys.stderr)


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('registrar');p.add_argument('--local',required=True);p.add_argument('--evento',required=True);p.add_argument('--versao');p.add_argument('--evidencia-local');p.add_argument('--tipo-evidencia',choices=['execucao','teste','feedback'],default='execucao')
    p=sub.add_parser('sugerir');p.add_argument('--local',required=True);p.add_argument('--tarefa-concluida',action='store_true',required=True)
    for name in ('preparar','consentir','enviar','conciliar'):
        p=sub.add_parser(name);p.add_argument('--local',required=True);p.add_argument('--id',required=True)
        if name in ('consentir','enviar'):p.add_argument('--revisao',required=True)
        if name=='consentir':p.add_argument('--decisao',choices=['autorizar','recusar'],required=True)
        if name=='enviar':p.add_argument('--confirmar-publicacao',action='store_true')
        if name=='conciliar':p.add_argument('--issue',type=int,required=True)
    p=sub.add_parser('refletir');p.add_argument('--local',required=True);p.add_argument('--id',required=True);p.add_argument('--nota-local',required=True)
    p=sub.add_parser('extrair');p.add_argument('--antes',required=True);p.add_argument('--depois',required=True);p.add_argument('--local',required=True);p.add_argument('--evidencia-local',required=True);p.add_argument('--tipo-evidencia',choices=['execucao','teste','feedback'],default='execucao')
    p=sub.add_parser('receber');p.add_argument('--arquivo',required=True)
    p=sub.add_parser('validar');p.add_argument('--arquivo',required=True)
    p=sub.add_parser('validar-lote');p.add_argument('--base',required=True);p.add_argument('--head',required=True)
    p=sub.add_parser('triagem');p.add_argument('--local',required=True);p.add_argument('--arquivo',required=True);p.add_argument('--base-confiavel',required=True)
    args=parser.parse_args()
    try:
        if args.command=='registrar':result=record(parse(read_file(args.evento)),args.local,args.versao,proof=args.evidencia_local,proof_kind=args.tipo_evidencia)
        elif args.command=='sugerir':result=offer(args.local)
        elif args.command=='preparar':result=prepare(args.local,args.id)
        elif args.command=='consentir':result=consent(args.local,args.id,args.revisao,args.decisao)
        elif args.command=='enviar':result=send(args.local,args.id,args.revisao,args.confirmar_publicacao)
        elif args.command=='conciliar':result=reconcile(args.local,args.id,args.issue)
        elif args.command=='refletir':result=reflect(args.local,args.id,args.nota_local)
        elif args.command=='extrair':result=extract(args.antes,args.depois,args.local,args.evidencia_local,args.tipo_evidencia)
        elif args.command=='receber':result=receive(args.arquivo)
        elif args.command=='validar-lote':result={'status':'dados-validados','ids':validate_revision_changes(Path(__file__).resolve().parents[1],args.base,args.head)}
        elif args.command=='triagem':result=triage_packet(args.local,args.arquivo,args.base_confiavel)
        else:validate(parse(read_file(args.arquivo)));result={'status':'válida como dado não confiável'}
        print(json.dumps(result,ensure_ascii=False,allow_nan=False));return 0
    except (OSError,ValueError,KeyError,TypeError,subprocess.SubprocessError) as exc:
        # Mensagens da validação são constantes; nunca imprimir payload/saída de autenticação.
        print('aprendizado: '+(str(exc) if isinstance(exc,Refused) else 'operação local recusada; dados preservados'),file=sys.stderr)
        return 2

if __name__=='__main__':raise SystemExit(main())
