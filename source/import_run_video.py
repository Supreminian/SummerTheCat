from pathlib import Path
import cv2,numpy as np,json,hashlib,math,shutil
from PIL import Image,ImageDraw
from video_matte import chroma_matte
from register_whole import upright_landmarks
root=Path(__file__).resolve().parent.parent;video=root/'source/images/video/run.mp4';cap=cv2.VideoCapture(str(video));fps=cap.get(5);n=int(cap.get(7));ok,bgr=cap.read();assert ok
first=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB));bb=first.getchannel('A').point(lambda x:255 if x>180 else 0).getbbox();marks=upright_landmarks(first.crop(bb));marks['centerX']+=bb[0];marks['groundY']+=bb[1];marks['crownY']+=bb[1];scale=332/marks['stature'];matrix=[1/scale,0,marks['centerX']-384/scale,0,1/scale,marks['groundY']-560/scale]
# Fit a single grade using quiet sitting frames only; no anatomy edits.
yy,xx=np.mgrid[:640,:768];roi=(xx>327)&(xx<440)&(yy>344)&(yy<555)
def samples(im):
 a=np.array(im);m=cv2.erode((a[...,3]>250).astype('uint8'),np.ones((7,7),np.uint8)).astype(bool)&roi;c=a[...,:3];return c[m&(c.mean(axis=2)<95)],c[m&(c.min(axis=2)>145)]
src=[[],[]];target=[[],[]]
for i in [0,1,2,n-3,n-2,n-1]:
 cap.set(cv2.CAP_PROP_POS_FRAMES,i);ok,bgr=cap.read();assert ok;im=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)).transform((768,640),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC)
 for j,v in enumerate(samples(im)):src[j].append(v)
for i in [0,1,2,142,143,144]:
 im=Image.new('RGBA',(768,640));im.paste(Image.open(root/f'pet-pack/frames/natural_sit/{i:03}.png'),(96,128))
 for j,v in enumerate(samples(im)):target[j].append(v)
src=[np.concatenate(v) for v in src];target=[np.concatenate(v) for v in target];lut=np.zeros((256,3),np.uint8);gains=[];offsets=[]
for c in range(3):
 p=np.concatenate([np.percentile(src[0][:,c],[10,50,90]),np.percentile(src[1][:,c],[10,50,90])]);q=np.concatenate([np.percentile(target[0][:,c],[10,50,90]),np.percentile(target[1][:,c],[10,50,90])]);gain,off=np.linalg.lstsq(np.column_stack([p,np.ones(len(p))]),q,rcond=None)[0];lut[:,c]=np.clip(np.rint(np.arange(256)*gain+off),0,255);gains.append(float(gain));offsets.append(float(off))
np.save(root/'source/run-color-lut.npy',lut)
allframes=[];clipped=[];rawBounds=[];cap.set(cv2.CAP_PROP_POS_FRAMES,0)
for i in range(n):
 ok,bgr=cap.read();assert ok;rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB);r,g,b=rgb.astype(float).transpose(2,0,1);m=((g-np.maximum(r,b))<.35*g).astype('uint8');cnt,labels,stats,_=cv2.connectedComponentsWithStats(m);s=stats[1+np.argmax(stats[1:,4])];x,y,w,h,area=s;bad=bool(x<3 or x+w>rgb.shape[1]-3);clipped.append(bad);rawBounds.append([int(x),int(y),int(x+w),int(y+h)])
 if (43<=i<207 or 256<=i<445) and not bad:
  im=chroma_matte(rgb).transform((768,640),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC);a=np.array(im);a[...,:3]=lut[a[...,:3],np.arange(3)];im=Image.fromarray(a);allframes.append((i,im))
 if i%96==0:print('Run source:',i+1,'/',n,flush=True)
cap.release();cfgp=root/'pet-pack/pet.json';cfg=json.loads(cfgp.read_text());reports=[];contact=Image.new('RGB',(1536,1280),'#e7e8e2');draw=ImageDraw.Draw(contact)
for row,(state,start,end,moveStart,moveEnd) in enumerate([('evade_left',43,207,53,164),('evade_right',256,445,270,395)]):
 sequence=[(i,im) for i,im in allframes if start<=i<end];count=len(sequence);assert count>=30;cols=math.ceil(math.sqrt(count));rows=math.ceil(count/cols);sheet=Image.new('RGBA',(cols*768,rows*640));folder=root/'pet-pack/frames'/state;folder.mkdir(exist_ok=True);joins=[];bounds=[]
 for j,(i,im) in enumerate(sequence):
  im.save(folder/f'{j:03}.png');sheet.paste(im,(j%cols*768,j//cols*640));bbox=im.getchannel('A').point(lambda x:255 if x>32 else 0).getbbox();assert bbox and bbox[0]>5 and bbox[1]>5 and bbox[2]<763 and bbox[3]<635,(i,bbox);bounds.append(bbox)
  if j and i!=sequence[j-1][0]+1:joins.append({'frame':j,'durationMs':100})
 sheet.save(root/f'pet-pack/clips/{state}.webp',lossless=True,exact=True,method=6)
 activeStart=next(j for j,(i,_) in enumerate(sequence) if i>=moveStart);activeEnd=max(j for j,(i,_) in enumerate(sequence) if i<=moveEnd)
 cfg['animations'][state]={'label':'避让 · '+('向左跑' if row==0 else '向右跑'),'row':0,'frames':count,'fps':fps,'durationMs':count/fps*1000,'loop':False,'speed':0,'directional':False,'geometryLocked':True,'restState':'natural_sit','focusOnly':True,'frameTransitions':joins,'evadeMotion':{'startFrame':activeStart,'endFrame':activeEnd},'clip':{'file':f'clips/{state}.webp','width':cols*768,'height':rows*640,'frameWidth':768,'frameHeight':640,'columns':cols,'rows':rows,'offsetX':160,'offsetY':0},'authoredMotion':'Original 跑动.mp4; intact-tail frames in original order; one fixed whole-video registration; no mirroring or limb synthesis'}
 reports.append({'state':state,'sourceFrames':[i for i,_ in sequence],'frames':count,'fps':fps,'excludedSourceClippedFrames':[i for i in range(start,end) if clipped[i]],'joins':joins,'motionRange':[activeStart,activeEnd],'minimumTransparentMargin':min(min(b[0],b[1],768-b[2],640-b[3]) for b in bounds)})
 for j,index in enumerate(np.linspace(0,count-1,4).round().astype(int)):
  im=sequence[index][1].resize((384,320));x=j*384;y=row*640;contact.paste(im,(x,y),im);draw.text((x+5,y+330),f'{state}: source {sequence[index][0]}',fill='black')
cfg['displayFrame']={'width':1024,'height':640,'paddingLeft':256,'paddingTop':128};cfg['mouseInteraction']['anchor']=[544,386];cfg['focusMode']={'enabledByDefault':False,'triggerRect':[392,224,692,572],'dwellMs':100,'cooldownMs':2000,'minimumClearance':24,'preferredTravelFraction':.22,'screenMargin':12,'directions':{'left':'evade_left','right':'evade_right'}};cfgp.write_text(json.dumps(cfg,ensure_ascii=False,indent=2));contact.save(root/'左右避让动画预览.jpg')
report={'sourceVideo':'/Users/renchengkunwu/Desktop/SummerTheCat/movement_video/跑动.mp4','sourceSHA256':hashlib.sha256(video.read_bytes()).hexdigest(),'sourceFrames':n,'sourceFPS':fps,'uniformScale':scale,'wholeFrameTransform':matrix,'colorGrade':{'gains':gains,'offsets':offsets},'perFrameScaleChanges':False,'sourceTailClippingDetected':True,'segments':reports};(root/'跑动导入记录.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));(root/'source/run-registration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print([(x['state'],x['frames'],x['motionRange']) for x in reports],flush=True)
