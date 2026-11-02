"""Reimport the provided eight-gesture video using saved full-video registration and grade. No motion synthesis."""
from pathlib import Path
import cv2,numpy as np,json,sys,math,hashlib,shutil
from PIL import Image,ImageDraw
O=Path(__file__).resolve().parent.parent;R=O/'source';from video_matte import chroma_matte
reg=json.loads((R/'paw-registration.json').read_text());lut=np.load(R/'paw-color-lut.npy');cuts=json.loads((R/'paw-segments.json').read_text());video=O/'source/images/video/paw-eight-directions.mp4';cap=cv2.VideoCapture(str(video));fps=cap.get(5);cfg=json.loads((O/'pet-pack/pet.json').read_text());labels=['上','右上','右','右下','下','左下','左','左上'];report=[]
contact=Image.new('RGB',(1536,1080),'#e7e8e2');draw=ImageDraw.Draw(contact)
for j,((direction,start,end),label) in enumerate(zip(cuts,labels)):
 state='paw_'+direction;count=end-start;cols=math.ceil(math.sqrt(count));rows=math.ceil(count/cols);sheet=Image.new('RGBA',(cols*512,rows*512));folder=O/'pet-pack/frames'/state;folder.mkdir(parents=True,exist_ok=True);hashes=[];cap.set(cv2.CAP_PROP_POS_FRAMES,start)
 for k in range(count):
  ok,bgr=cap.read();assert ok
  frame=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)).transform((512,512),Image.Transform.AFFINE,reg['matrix'],Image.Resampling.BICUBIC);a=np.array(frame);a[...,:3]=lut[a[...,:3],np.arange(3)];frame=Image.fromarray(a);frame.save(folder/f'{k:03}.png');sheet.paste(frame,(k%cols*512,k//cols*512));hashes.append(hashlib.sha256(frame.tobytes()).hexdigest())
  if k==count//2:
   im=frame.resize((384,384),Image.Resampling.LANCZOS);contact.paste(im,(j%4*384,j//4*540),im);draw.text((j%4*384+8,j//4*540+405),f'{direction}: {start/24:.2f}-{end/24:.2f}s / {count} frames',fill='#304138')
 sheet.save(O/'pet-pack/clips'/f'{state}.webp',lossless=True,exact=True,method=6)
 cfg['animations'][state]={'label':'扒拉 · '+label,'row':0,'frames':count,'fps':int(fps),'durationMs':count/fps*1000,'loop':False,'speed':0,'directional':False,'geometryLocked':True,'restState':'natural_sit','interactionOnly':True,'clip':{'file':f'clips/{state}.webp','width':cols*512,'height':rows*512,'frameWidth':512,'frameHeight':512,'columns':cols,'rows':rows},'authoredMotion':f'Original intact source frames {start}..{end-1} from user 8方向扒拉.mp4; shared whole-video registration and fixed color grade; never mirrored'}
 report.append({'state':state,'direction':direction,'sourceStartFrame':start,'sourceEndFrameExclusive':end,'frames':count,'fps':fps,'uniqueFrames':len(set(hashes)),'startSeconds':start/fps,'endSeconds':end/fps});print(state,count,flush=True)
cap.release();contact.save(O/'八方向互动预览.jpg');
cfg['mouseInteraction']={'enabled':True,'anchor':[288,258],'reach':[260,280],'innerRadius':42,'dwellMs':180,'cooldownMs':1800,'returnRestMs':300,'rearmMovement':48,'exitRatio':1.15,'exitDwellMs':160,'sectorHysteresisDegrees':7,'directions':{d:'paw_'+d for d,_,_ in cuts}}
(O/'pet-pack/pet.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2));report={'sourceVideo':'/Users/renchengkunwu/Desktop/SummerTheCat/movement_video/8方向扒拉.mp4','sourceSHA256':hashlib.sha256(video.read_bytes()).hexdigest(),'sourceFrames':721,'sourceFPS':fps,'segments':report,'wholeVideoRegistration':reg,'colorGrade':json.loads((R/'paw-color-calibration.json').read_text()),'perFrameScaleChanges':False,'sourceFrameOrderUnchanged':True,'localMotionSynthesis':False,'mirrored':False,'cutsBasedOnActualRestPoses':True}
(O/'八方向素材导入记录.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
scores=json.loads((R/'paw-motion-scores.json').read_text())['scores']
for seg in report['segments']:
 trailing=0
 for score in reversed(scores[seg['sourceStartFrame']:seg['sourceEndFrameExclusive']]):
  if score>=.08:break
  trailing+=1
 hold=300;a=cfg['animations'][seg['state']];a['holdLastFrameMs']=hold;a['durationMs']=a['frames']/a['fps']*1000+hold
 seg.update(recordedTrailingRestFrames=trailing,additionalOriginalLastFrameHoldMs=hold,minimumReturnRestMs=trailing/24*1000+hold)
(O/'pet-pack/pet.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2));(O/'八方向素材导入记录.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
