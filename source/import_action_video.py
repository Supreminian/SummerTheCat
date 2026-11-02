"""Import intact user videos. Key the green screen and register the whole clip once."""
from pathlib import Path
import cv2,numpy as np,json,hashlib,shutil,math,sys
from PIL import Image,ImageDraw
from video_matte_yawn import chroma_matte as detailed_matte
from video_matte import chroma_matte as seated_matte
from register_whole import upright_landmarks
ROOT=Path(__file__).resolve().parent.parent;PACK=ROOT/'pet-pack'

def import_action(action,label):
 chroma_matte=seated_matte if action=='yawn' else detailed_matte
 video=ROOT/'source/images/video'/f'{action}.mp4';cap=cv2.VideoCapture(str(video));fps=cap.get(cv2.CAP_PROP_FPS);frames=[]
 while True:
  ok,bgr=cap.read()
  if not ok:break
  frames.append(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB))
 cap.release();assert 30<=len(frames)<=600 and 0<fps<=60
 first=chroma_matte(frames[0]);box=first.getchannel('A').point(lambda v:255 if v>180 else 0).getbbox();assert box
 marks=upright_landmarks(first.crop(box));marks['centerX']+=box[0];marks['groundY']+=box[1];marks['crownY']+=box[1]
 scale=332/marks['stature'];matrix=(1/scale,0,marks['centerX']-288/scale,0,1/scale,marks['groundY']-432/scale)
 if action=='yawn':
  registration=json.loads((ROOT/'source/yawn-registration.json').read_text());assert hashlib.sha256(video.read_bytes()).hexdigest()==registration['sourceSHA256'];marks=registration['registrationLandmarks'];scale=registration['uniformScale'];matrix=tuple(registration['wholeFrameTransform'])
 folder=PACK/'frames'/action
 if folder.exists():shutil.rmtree(folder)
 folder.mkdir(parents=True);(PACK/'clips').mkdir(exist_ok=True)
 cols=math.ceil(math.sqrt(len(frames)));rows=math.ceil(len(frames)/cols);sheet=Image.new('RGBA',(cols*512,rows*512))
 contact=Image.new('RGB',(6*256,3*280),'#dce4d5');draw=ImageDraw.Draw(contact);indices=list(np.linspace(0,len(frames)-1,18).round().astype(int));hashes=[]
 for k,rgb in enumerate(frames):
  frame=chroma_matte(rgb).transform((512,512),Image.Transform.AFFINE,matrix,resample=Image.Resampling.BICUBIC)
  if action=='yawn' and (ROOT/'source/yawn-color-lut.npy').exists():
   lut=np.load(ROOT/'source/yawn-color-lut.npy');pixels=np.array(frame);pixels[...,:3]=lut[pixels[...,:3],np.arange(3)];frame=Image.fromarray(pixels)
  frame.save(folder/f'{k:03}.png');hashes.append(hashlib.sha256(frame.tobytes()).hexdigest());sheet.paste(frame,(k%cols*512,k//cols*512))
  if k in indices:
   j=indices.index(k);im=frame.resize((256,256),Image.Resampling.LANCZOS);contact.paste(im,(j%6*256,j//6*280),im);draw.text((j%6*256+8,j//6*280+259),f'{k+1}/{len(frames)} {k/fps:.2f}s',fill='#293a2e')
  if k%48==0:print(f'{action}: {k+1}/{len(frames)}',flush=True)
 sheet.save(PACK/'clips'/f'{action}.webp',lossless=True,exact=True,method=6);contact.save(ROOT/f'{action}-transparent-review.jpg')
 cfg=json.loads((PACK/'pet.json').read_text());cfg['id']='summer-the-cat-v29';cfg['animations'][action]={'label':label,'row':0,'frames':len(frames),'fps':int(fps) if fps.is_integer() else fps,'durationMs':len(frames)/fps*1000,'loop':False,'speed':0,'directional':False,'geometryLocked':True,'restState':'natural_sit','clip':{'file':f'clips/{action}.webp','width':cols*512,'height':rows*512,'frameWidth':512,'frameHeight':512,'columns':cols,'rows':rows},'authoredMotion':f'Original user-provided {label}.mp4, all frames in original order'}
 (PACK/'pet.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2))
 report={'sourceVideo':str(video),'sourceSHA256':hashlib.sha256(video.read_bytes()).hexdigest(),'frames':len(frames),'fps':fps,'uniqueFrames':len(set(hashes)),'durationMs':len(frames)/fps*1000,'registrationLandmarks':marks,'wholeFrameTransform':list(matrix),'uniformScale':scale,'frameSize':512,'perFrameScaleChanges':False,'sourceMotionAndFrameOrderUnchanged':True,'localMotionSynthesis':False,'edgeProcessing':('Same original seated-video matting: fractional alpha, opaque interior preserved, boundary-only green despill' if action=='yawn' else 'Opaque-fur color prior plus fine-white-whisker candidate, projection alpha and boundary chroma decontamination; dense interior RGB preserved'),'audio':False,'completionState':'natural_sit'}
 (ROOT/f'{action}-import.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False),flush=True)
 for k in sorted(set([0,len(frames)//3,len(frames)*2//3,len(frames)-1])):
  im=Image.open(folder/f'{k:03}.png');canvas=Image.new('RGB',(1024,512),'white')
  for j,color in enumerate(['white','#293648']):
   bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im);canvas.paste(bg.convert('RGB'),(j*512,0))
  canvas.save(ROOT/f'{action}-edge-{k:03}.png')
if __name__=='__main__':
 for action,label in [('yawn','打哈欠'),('groom','舔毛')]:import_action(action,label)
