"""Import all frames of 动耳朵3.mp4 with a single registration and color grade."""
from pathlib import Path
import cv2,numpy as np,json,hashlib,math,shutil
from PIL import Image,ImageDraw
from video_matte import chroma_matte
from register_whole import upright_landmarks
root=Path(__file__).resolve().parent.parent;video=root/'source/images/video/ears.mp4';cap=cv2.VideoCapture(str(video));fps=cap.get(5);count=int(cap.get(7));assert 30<=count<=600 and 0<fps<=60
ok,bgr=cap.read();assert ok;first=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB));bb=first.getchannel('A').point(lambda x:255 if x>180 else 0).getbbox();marks=upright_landmarks(first.crop(bb));marks['centerX']+=bb[0];marks['groundY']+=bb[1];marks['crownY']+=bb[1]
scale=332/marks['stature'];matrix=[1/scale,0,marks['centerX']-288/scale,0,1/scale,marks['groundY']-432/scale]
reg={'landmarks':marks,'scale':scale,'matrix':matrix,'video':{'frames':count,'fps':fps,'width':cap.get(3),'height':cap.get(4)},'sourceSHA256':hashlib.sha256(video.read_bytes()).hexdigest()}
(root/'source/ears-registration.json').write_text(json.dumps(reg,ensure_ascii=False,indent=2))
ys,xs=np.mgrid[:512,:512];roi=(xs>231)&(xs<344)&(ys>216)&(ys<427)
def sample(im):
 a=np.array(im);mask=cv2.erode((a[...,3]>250).astype('uint8'),np.ones((7,7),np.uint8)).astype(bool)&roi;c=a[...,:3];lum=c.mean(axis=2);return c[mask&(lum<95)],c[mask&(c.min(axis=2)>145)]
source=[[],[]];target=[[],[]]
for i in [0,1,2,count-3,count-2,count-1]:
 cap.set(cv2.CAP_PROP_POS_FRAMES,i);ok,bgr=cap.read();assert ok;im=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)).transform((512,512),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC)
 for j,v in enumerate(sample(im)):source[j].append(v)
for i in [0,1,2,142,143,144]:
 for j,v in enumerate(sample(Image.open(root/f'pet-pack/frames/natural_sit/{i:03}.png'))):target[j].append(v)
source=[np.concatenate(a) for a in source];target=[np.concatenate(a) for a in target];lut=np.empty((256,3),np.uint8);gains=[];offsets=[];stats={}
for c in range(3):
 p=np.concatenate([np.percentile(source[0][:,c],[10,50,90]),np.percentile(source[1][:,c],[10,50,90])]);q=np.concatenate([np.percentile(target[0][:,c],[10,50,90]),np.percentile(target[1][:,c],[10,50,90])]);gain,off=np.linalg.lstsq(np.column_stack([p,np.ones(len(p))]),q,rcond=None)[0];gains.append(float(gain));offsets.append(float(off));lut[:,c]=np.clip(np.rint(np.arange(256)*gain+off),0,255).astype('uint8')
for j,name in enumerate(['blackCoat','whiteFur']):
 goal=np.median(target[j],axis=0);before=np.median(source[j],axis=0);after=np.median(lut[source[j],np.arange(3)],axis=0);stats[name]={'targetMedianRGB':goal.tolist(),'sourceMedianRGB':before.tolist(),'correctedMedianRGB':after.tolist(),'beforeError':float(np.mean(np.abs(before-goal))),'afterError':float(np.mean(np.abs(after-goal)))}
calibration={'method':'One fixed per-channel grade matched to opaque black and white fur of natural sitting','gains':gains,'offsets':offsets,'samples':stats,'perFrameExposureChanges':False};np.save(root/'source/ears-color-lut.npy',lut);(root/'source/ears-color-calibration.json').write_text(json.dumps(calibration,ensure_ascii=False,indent=2))
folder=root/'pet-pack/frames/ears';shutil.rmtree(folder);folder.mkdir();cols=math.ceil(math.sqrt(count));rows=math.ceil(count/cols);sheet=Image.new('RGBA',(cols*512,rows*512));contact=Image.new('RGB',(1536,560),'#e7e8e2');draw=ImageDraw.Draw(contact);indices=list(np.linspace(0,count-1,12).round().astype(int));hashes=[];minMargin=512
cap.set(cv2.CAP_PROP_POS_FRAMES,0)
for i in range(count):
 ok,bgr=cap.read();assert ok;im=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)).transform((512,512),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC);pixels=np.array(im);pixels[...,:3]=lut[pixels[...,:3],np.arange(3)];im=Image.fromarray(pixels);im.save(folder/f'{i:03}.png');sheet.paste(im,(i%cols*512,i//cols*512));hashes.append(hashlib.sha256(im.tobytes()).hexdigest());box=im.getchannel('A').point(lambda x:255 if x>32 else 0).getbbox();assert box and box[0]>0 and box[1]>0 and box[2]<512 and box[3]<512;minMargin=min(minMargin,box[0],box[1],512-box[2],512-box[3])
 if i in indices:
  j=indices.index(i);small=im.resize((256,256),Image.Resampling.LANCZOS);contact.paste(small,(j%6*256,j//6*280),small);draw.text((j%6*256+8,j//6*280+258),f'{i+1}/{count} {i/fps:.2f}s',fill='#304138')
 if i%24==0:print(f'New ears: {i+1}/{count}',flush=True)
cap.release();sheet.save(root/'pet-pack/clips/ears.webp',lossless=True,exact=True,method=6);contact.save(root/'动耳朵逐帧预览.jpg')
cfgp=root/'pet-pack/pet.json';cfg=json.loads(cfgp.read_text());cfg['animations']['ears'].update(frames=count,fps=int(fps) if fps.is_integer() else fps,durationMs=count/fps*1000,clip={'file':'clips/ears.webp','width':cols*512,'height':rows*512,'frameWidth':512,'frameHeight':512,'columns':cols,'rows':rows},authoredMotion=f'Original user-provided 动耳朵3.mp4, all {count} frames in original order; fixed whole-clip registration and color grade');cfgp.write_text(json.dumps(cfg,ensure_ascii=False,indent=2))
report={'sourceVideo':'/Users/renchengkunwu/Desktop/SummerTheCat/movement_video/动耳朵3.mp4','sourceSHA256':reg['sourceSHA256'],'frames':count,'fps':fps,'uniqueFrames':len(set(hashes)),'durationMs':count/fps*1000,'uniformScale':scale,'wholeFrameTransform':matrix,'perFrameScaleChanges':False,'sourceMotionAndFrameOrderUnchanged':True,'localMotionSynthesis':False,'colorCorrection':calibration,'minimumTransparentMarginPx':minMargin,'completionState':'natural_sit'};(root/'动耳朵导入记录.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('New ear video imported:',count,'frames',flush=True)
review=Image.new('RGB',(1536,548),'#e7e8e2');d=ImageDraw.Draw(review);raw=first.transform((512,512),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC)
for j,(label,im) in enumerate([('NATURAL SIT',Image.open(root/'pet-pack/frames/natural_sit/000.png')),('NEW EARS BEFORE',raw),('NEW EARS MATCHED',Image.open(folder/'000.png'))]):review.paste(im,(j*512,30),im);d.text((j*512+12,9),label,fill='black')
review.save(root/'动耳朵色调对比.jpg')
