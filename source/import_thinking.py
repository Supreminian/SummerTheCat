"""Import the three supplied whole-cat clips, retaining their frame order."""
from pathlib import Path
import cv2, numpy as np, json, math, hashlib
from PIL import Image, ImageDraw
from video_matte import chroma_matte
from register_whole import upright_landmarks

ROOT=Path(__file__).resolve().parent.parent
PACK=ROOT/'pet-pack'
names=['thinking_enter','thinking_loop','thinking_exit']
cap=cv2.VideoCapture(str(ROOT/'source/images/video/thinking_enter.mp4'))
ok,bgr=cap.read();assert ok;cap.release()
first=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB))
marks=upright_landmarks(first);scale=332/marks['stature']
cfg=json.loads((PACK/'pet.json').read_text());report=[]
review=Image.new('RGB',(4*256,3*280),'#e6e9e3');draw=ImageDraw.Draw(review)
for row,name in enumerate(names):
 path=ROOT/'source/images/video'/f'{name}.mp4'
 cap=cv2.VideoCapture(str(path));fps=cap.get(cv2.CAP_PROP_FPS);frames=[]
 while True:
  ok,bgr=cap.read()
  if not ok:break
  frames.append(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB))
 cap.release();assert len(frames)>30
 anchor=upright_landmarks(chroma_matte(frames[0]))
 clip_scale=scale*first.width/frames[0].shape[1]
 matrix=(1/clip_scale,0,anchor['centerX']-288/clip_scale,0,1/clip_scale,anchor['groundY']-432/clip_scale)
 columns=math.ceil(math.sqrt(len(frames)));rows=math.ceil(len(frames)/columns)
 atlas=Image.new('RGBA',(columns*512,rows*512));ends=[]
 indices=[0,len(frames)//3,2*len(frames)//3,len(frames)-1]
 for i,rgb in enumerate(frames):
  rgba=chroma_matte(rgb).transform((512,512),Image.Transform.AFFINE,matrix,resample=Image.Resampling.BICUBIC)
  atlas.paste(rgba,(i%columns*512,i//columns*512))
  if i in indices:
   col=indices.index(i);thumb=rgba.resize((256,256),Image.Resampling.LANCZOS)
   review.paste(thumb,(col*256,row*280),thumb)
   draw.text((col*256+8,row*280+260),f'{name} / {i}',fill='#304434')
  if i in (0,len(frames)-1):ends.append(np.array(rgba))
 atlas.save(PACK/'clips'/f'{name}.webp',lossless=True,exact=True,method=4)
 cfg['animations'][name]={'label':{'thinking_enter':'开始倾听 · 歪头','thinking_loop':'歪头等待 · 呼吸','thinking_exit':'结束倾听 · 回正'}[name],
  'row':0,'frames':len(frames),'fps':fps,'durationMs':len(frames)/fps*1000,'loop':name=='thinking_loop','speed':0,
  'conversationLoop':name=='thinking_loop','geometryLocked':True,'restState':{'thinking_enter':'thinking_loop','thinking_exit':'natural_sit_still','thinking_loop':'thinking_loop'}[name],
  'clip':{'file':f'clips/{name}.webp','width':atlas.width,'height':atlas.height,'frameWidth':512,'frameHeight':512,'columns':columns,'rows':rows},
  'authoredMotion':'User-supplied whole-character video; fixed uniform transform, original frames in order'}
 report.append({'state':name,'frames':len(frames),'fps':fps,'sourceSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),'uniformScale':clip_scale,'resolutionNormalized':True,'transform':matrix,'perFrameRegistration':False,'clipBytes':(PACK/'clips'/f'{name}.webp').stat().st_size})
 print(name,len(frames),'frames imported',flush=True)
cfg['id']='summer-the-cat-v30';cfg['chat']={'enterState':'thinking_enter','loopState':'thinking_loop','exitState':'thinking_exit'}
(PACK/'pet.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2))
(ROOT/'思考素材导入记录.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
review.save(ROOT/'思考透明素材预览.jpg')
