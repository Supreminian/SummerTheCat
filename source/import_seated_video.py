"""Chroma matte user-provided whole-cat footage; no generated or altered motion."""
from pathlib import Path
import cv2,numpy as np,json,hashlib,shutil
from PIL import Image,ImageDraw
import sys
ROOT=Path(__file__).resolve().parent.parent;sys.path.insert(0,str(ROOT/'source'))
from register_whole import upright_landmarks
VIDEO=ROOT/'source/images/video/natural_sit.mp4';PACK=ROOT/'pet-pack'
cap=cv2.VideoCapture(str(VIDEO));fps=round(cap.get(cv2.CAP_PROP_FPS));source=[]
while True:
 ok,bgr=cap.read()
 if not ok:break
 source.append(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB))
assert len(source)==145 and fps==24
def chroma_matte(rgb):
 h,w=rgb.shape[:2];c=rgb.astype(float);r,g,b=c.transpose(2,0,1)
 pure=(g>80)&((g-np.maximum(r,b))>.65*g)
 # Estimate the green plate from visible background at both sides for each row.
 values=[]
 for lo,hi in [(0,round(w*.10)),(round(w*.90),w)]:
  rows=np.array([np.median(c[y,lo:hi][pure[y,lo:hi]],axis=0) if pure[y,lo:hi].any() else [np.nan]*3 for y in range(h)])
  for channel in range(3):
   v=rows[:,channel];valid=np.isfinite(v)
   assert valid.any(), 'No green plate samples'
   rows[:,channel]=np.interp(np.arange(h),np.where(valid)[0],v[valid])
  values.append(cv2.GaussianBlur(rows,(1,9),2))
 x=np.linspace(0,1,w)[None,:,None];background=values[0][:,None,:]*(1-x)+values[1][:,None,:]*x
 plate=background[...,1]-np.maximum(background[...,0],background[...,2])
 dominance=np.maximum(0,g-np.maximum(r,b))
 alpha=np.clip(1-dominance/np.maximum(plate,80),0,1)
 # Codec background noise is not a hair; suppress only near-empty alpha.
 alpha=np.clip((alpha-.025)/.975,0,1)
 rough=(alpha>.20).astype('uint8')
 n,labels,stats,_=cv2.connectedComponentsWithStats(rough)
 body=1+np.argmax(stats[1:,4]);mask=(labels==body).astype('uint8')
 mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
 pad=np.pad(mask,1);cv2.floodFill(pad,None,(0,0),2);solid=(pad[1:-1,1:-1]!=2).astype('uint8')
 interior=cv2.erode(solid,np.ones((9,9),np.uint8)).astype(bool)&(alpha>.94)
 # Preserve all interior colors exactly, including green eyes and black nasal skin.
 alpha[interior]=1
 # Keep fractional fine hairs connected to, or near, the full-cat silhouette.
 near=cv2.dilate(solid,np.ones((31,31),np.uint8)).astype(bool)
 alpha[~near]=0
 fg=c.copy();a=alpha[...,None]
 boundary=(alpha>0)&~interior
 recovered=(c-(1-a)*background)/np.maximum(a,.025)
 fg[boundary]=np.clip(recovered[boundary],0,255)
 # Remove residual green screen spill only at the keyed boundary.
 fg[...,1][boundary]=np.minimum(fg[...,1][boundary],np.maximum(fg[...,0],fg[...,2])[boundary])
 return Image.fromarray(np.dstack((np.round(fg).astype('uint8'),np.round(alpha*255).astype('uint8'))))
first=chroma_matte(source[0])
# The final source has generous green-screen padding. Measure the first cat
# silhouette in its own bounding box, then convert anchors to source space.
box=first.getchannel('A').point(lambda v:255 if v>180 else 0).getbbox()
assert box is not None
marks=upright_landmarks(first.crop(box))
marks['centerX']+=box[0];marks['groundY']+=box[1];marks['crownY']+=box[1]
scale=332/marks['stature']
matrix=(1/scale,0,marks['centerX']-288/scale,0,1/scale,marks['groundY']-432/scale)
(PACK/'clips').mkdir(exist_ok=True)
folder=PACK/'frames/natural_sit'
if folder.exists():shutil.rmtree(folder)
folder.mkdir(parents=True);sheet=Image.new('RGBA',(6656,6144));contact=Image.new('RGB',(7*256,3*280),'#dce4d5');draw=ImageDraw.Draw(contact)
indices=list(np.linspace(0,144,21).round().astype(int));hashes=[];rgbs=[];display=[]
for k,rgb in enumerate(source):
 whole=chroma_matte(rgb)
 frame=whole.transform((512,512),Image.Transform.AFFINE,matrix,resample=Image.Resampling.BICUBIC)
 frame.save(folder/f'{k:03}.png');hashes.append(hashlib.sha256(frame.tobytes()).hexdigest());sheet.paste(frame,(k%13*512,k//13*512))
 if k in indices:
  j=indices.index(k);small=frame.resize((256,256),Image.Resampling.LANCZOS);contact.paste(small,(j%7*256,j//7*280),small);draw.text((j%7*256+8,j//7*280+258),f'{k+1}/145  {k/fps:.2f}s',fill='#293a2e')
 display.append(np.array(frame))
sheet.save(PACK/'clips/natural_sit.webp',lossless=True,exact=True,method=6)
Image.open(folder/'000.png').save(PACK/'main.png')
Image.open(folder/'000.png').save(PACK/'spritsheet.webp',lossless=True,exact=True)
cfg=json.loads((PACK/'pet.json').read_text());cfg['id']='summer-the-cat-v29';a=cfg['animations']['natural_sit'];a.update(label='自然静坐',frames=145,fps=24,durationMs=145/24*1000,clip={'file':'clips/natural_sit.webp','width':6656,'height':6144,'frameWidth':512,'frameHeight':512,'columns':13,'rows':12},authoredMotion='User-supplied complete-character green-screen video, all original frames in original order')
(PACK/'pet.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2));contact.save(ROOT/'natural-sit-transparent-review.jpg')
def premul(v):return v[...,:3].astype(float)*(v[...,3:4]/255)
loop=np.abs(premul(display[-1])-premul(display[0])).mean()
neighbor=np.mean([np.abs(premul(display[i])-premul(display[i-1])).mean() for i in range(1,len(display))])
report={'sourceVideo':str(VIDEO),'sourceSHA256':hashlib.sha256(VIDEO.read_bytes()).hexdigest(),'sourceFrames':145,'fps':24,'uniqueFrames':len(set(hashes)),'frameSize':512,'alphaProcessing':'Green-plate chroma matting with fractional hair alpha; green despill only at boundary; interior RGB retained','wholeFrameTransform':list(matrix),'uniformScale':scale,'perFrameScaleChanges':False,'localMotionConstruction':False,'sourceMotionAndFrameOrderUnchanged':True,'loopBoundaryMeanPremulDifference':float(loop),'meanAdjacentDifference':float(neighbor),'audio':False}
(ROOT/'natural-sit-import.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(report)
for k in [0,48,96,144]:
 im=Image.open(folder/f'{k:03}.png');canvas=Image.new('RGB',(1024,512),'#fff');bg=Image.new('RGBA',im.size,'#fff');bg.alpha_composite(im);canvas.paste(bg.convert('RGB'),(0,0));bg=Image.new('RGBA',im.size,'#293648');bg.alpha_composite(im);canvas.paste(bg.convert('RGB'),(512,0));canvas.save(ROOT/f'edge-review-{k:03}.png')
