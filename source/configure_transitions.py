from pathlib import Path
import json
root=Path(__file__).resolve().parent.parent
policy=json.loads((root/'source/transition-policy.json').read_text())
p=root/'pet-pack/pet.json';config=json.loads(p.read_text());config['id']='summer-the-cat-v29';config['transitions']=policy['transitions']
for item in policy['ranges']:
 a=config['animations'][item['state']];start=item['startFrame'];end=item['endFrameExclusive'];assert 0<=start<end<=a['frames']
 a['playbackRange']={'startFrame':start,'endFrameExclusive':end}
 if item['state'].startswith('paw_'):a['holdLastFrameMs']=item['holdMs']
 a['durationMs']=(end-start)*1000/a['fps']+a.get('holdLastFrameMs',0)
p.write_text(json.dumps(config,ensure_ascii=False,indent=2))
(root/'衔接与静坐裁剪记录.json').write_text(json.dumps(policy,ensure_ascii=False,indent=2))
