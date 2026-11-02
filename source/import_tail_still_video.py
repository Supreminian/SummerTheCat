"""Import complete seated video with a still tail, preserving all source motion."""
from pathlib import Path
import cv2,numpy as np,json,hashlib,shutil,math
from PIL import Image,ImageDraw
from video_matte import chroma_matte
from register_whole import upright_landmarks
ROOT=Path(__file__).resolve().parent.parent
VIDEO=ROOT/'source/images/video/natural_sit_still.mp4';PACK=ROOT/'pet-pack'
cap=cv2.VideoCapture(str(VIDEO));fps=cap.get(cv2.CAP_PROP_FPS);frames=[]
while True:
 ok,bgr=cap.read()
 if not ok:break
 frames.append(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB))
assert len(frames)==145 and fps==24
first=chroma_matte(frames[0]);box=first.getchannel('A').point(lambda v:255 if v>180 else 0).getbbox();assert box
marks=upright_landmarks(first.crop(box));marks['centerX']+=box[0];marks['groundY']+=box[1];marks['crownY']+=box[1]
scale=332/marks['stature'];matrix=(1/scale,0,marks['centerX']-288/scale,0,1/scale,marks['groundY']-432/scale)
folder=PACK/'frames/natural_sit_still'
if folder.exists():shutil.rmtree(folder)
folder.mkdir(parents=True);(PACK/'clips').mkdir(exist_ok=True)
columns=math.ceil(math.sqrt(len(frames)));rows=math.ceil(len(frames)/columns);sheet=Image.new('RGBA',(columns*512,rows*512))
contact=Image.new('RGB',(6*256,3*280),'#dce4d5');draw=ImageDraw.Draw(contact);indices=list(np.linspace(0,len(frames)-1,18).round().astype(int));hashes=[]
for k,rgb in enumerate(frames):
 frame=chroma_matte(rgb).transform((512,512),Image.Transform.AFFINE,matrix,resample=Image.Resampling.BICUBIC)
 frame.save(folder/f'{k:03}.png');hashes.append(hashlib.sha256(frame.tobytes()).hexdigest());sheet.paste(frame,(k%columns*512,k//columns*512))
 if k in indices:
  j=indices.index(k);im=frame.resize((256,256),Image.Resampling.LANCZOS);contact.paste(im,(j%6*256,j//6*280),im);draw.text((j%6*256+8,j//6*280+259),f'{k+1}/{len(frames)} {k/fps:.2f}s',fill='#293a2e')
sheet.save(PACK/'clips/natural_sit_still.webp',lossless=True,exact=True,method=6);contact.save(ROOT/'tail-still-transparent-review.jpg')
cfg=json.loads((PACK/'pet.json').read_text());cfg['id']='summer-the-cat-v29';cfg['animations']['natural_sit_still']={'label':'自然静坐 · 尾巴不动','row':0,'frames':len(frames),'fps':int(fps),'durationMs':len(frames)/fps*1000,'loop':True,'speed':0,'directional':False,'geometryLocked':True,'restState':'natural_sit','clip':{'file':'clips/natural_sit_still.webp','width':columns*512,'height':rows*512,'frameWidth':512,'frameHeight':512,'columns':columns,'rows':rows},'authoredMotion':'Original user-provided cat idle B tail still.mp4, all frames in original order'}
(PACK/'pet.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2))
report={'sourceVideo':str(VIDEO),'sourceSHA256':hashlib.sha256(VIDEO.read_bytes()).hexdigest(),'frames':len(frames),'fps':fps,'uniqueFrames':len(set(hashes)),'durationMs':len(frames)/fps*1000,'registrationLandmarks':marks,'wholeFrameTransform':list(matrix),'uniformScale':scale,'frameSize':512,'perFrameScaleChanges':False,'sourceMotionAndFrameOrderUnchanged':True,'localMotionSynthesis':False,'audio':False,'completionState':'natural_sit'}
(ROOT/'tail-still-import.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(report)
for k in [0,48,96,144]:
 im=Image.open(folder/f'{k:03}.png');canvas=Image.new('RGB',(1024,512),'white')
 for j,color in enumerate(['white','#293648']):
  bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im);canvas.paste(bg.convert('RGB'),(j*512,0))
 canvas.save(ROOT/f'tail-still-edge-{k:03}.png')
