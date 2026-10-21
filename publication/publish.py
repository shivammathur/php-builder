import base64,concurrent.futures as cf,hashlib,json,os,subprocess,sys,time,urllib.request,zlib
from pathlib import Path
minor=sys.argv[1];plan=json.loads(Path('publication/'+minor+'.json').read_text());repo=os.environ['GITHUB_REPOSITORY'];assert repo==plan['repository']
caps=json.loads(zlib.decompress(base64.b64decode(os.environ.pop('PRIVATE_PACKAGE_ACCESS'))))
def api(path):return json.loads(subprocess.check_output(['gh','api',path]))
def inventory():
 pages=json.loads(subprocess.check_output(['gh','api',f'repos/{repo}/releases/{plan["release_id"]}/assets?per_page=100','--paginate','--slurp']))
 out=[a for p in pages for a in p];assert len(out)==len({a['name'] for a in out});return {a['name']:a for a in out}
before=inventory();Path('work').mkdir();Path('receipts').mkdir()
def file_sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for c in iter(lambda:f.read(4*1024*1024),b''):h.update(c)
 return h.hexdigest()
def publish(f):
 name=f['name'];old=before.get(name);receipt={'name':name,'bytes':f['bytes'],'sha256':f['sha256'],'uploaded':False}
 if old and old['size']==f['bytes'] and old['digest']=='sha256:'+f['sha256']:
  receipt.update(uploaded=True,already_identical=True,asset_id=old['id']);Path('receipts/'+name+'.json').write_text(json.dumps(receipt));return receipt
 if old:
  prior=plan['backed_up_before'].get(name)
  assert prior and old['id']==prior['id'] and old['size']==prior['size'] and old['digest']==prior['digest'],('Unreviewed concurrent asset',name)
 p=Path('work')/name
 if f.get('metadata'):
  p.write_bytes(base64.b64decode(f['content_base64']))
 else:
  assert name in caps
  for attempt in range(4):
   try:
    h=hashlib.sha256();size=0
    with urllib.request.urlopen(caps[name],timeout=180) as response,p.open('wb') as out:
     for c in iter(lambda:response.read(4*1024*1024),b''):out.write(c);h.update(c);size+=len(c)
    assert size==f['bytes'] and h.hexdigest()==f['sha256'];break
   except Exception:
    if attempt==3:raise RuntimeError('Private GitHub download failed for '+name) from None
    time.sleep(2**attempt)
 assert p.stat().st_size==f['bytes'] and file_sha(p)==f['sha256']
 if old:
  subprocess.run(['gh','api','--method','DELETE',old['url']],check=True,stdout=subprocess.DEVNULL)
  receipt['replaced_asset_id']=old['id']
 Path('receipts/'+name+'.json').write_text(json.dumps(receipt))
 # No --clobber: only the exact reviewed, recoverably backed-up ID was deleted.
 result=subprocess.run(['gh','release','upload',plan['tag'],str(p),'--repo',repo],capture_output=True,text=True)
 if result.returncode:
  current=inventory().get(name)
  if not current or current['size']!=f['bytes'] or current['digest']!='sha256:'+f['sha256']:
   raise RuntimeError('Upload outcome needs inspection: '+name)
 receipt['uploaded']=True;Path('receipts/'+name+'.json').write_text(json.dumps(receipt));p.unlink();print('Uploaded',name,flush=True);return receipt
with cf.ThreadPoolExecutor(max_workers=6) as pool:results=list(pool.map(publish,[f for f in plan['files'] if not f.get('metadata')]))
for f in plan['files']:
 if f.get('metadata'):results.append(publish(f))
after=inventory()
for f in plan['files']:
 a=after[f['name']];assert a['size']==f['bytes'] and a['digest']=='sha256:'+f['sha256'],f['name']
summary={'repository':repo,'minor':minor,'run_id':os.environ['GITHUB_RUN_ID'],'revision':os.environ['GITHUB_SHA'],'uploaded':True,'files':len(results),'github_digests_verified':True,'download_verification':'separate read-only workflow','no_rebuild':True}
Path('receipts/summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
