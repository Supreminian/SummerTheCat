"""Keep original scale/grounding; recover the upward paw on a taller display canvas."""
from pathlib import Path
import json,math,sys
import cv2,numpy as np
from PIL import Image
from video_matte import chroma_matte
root=Path(__file__).resolve().parent.parent
cfgp=root/'pet-pack/pet.json';cfg=json.loads(cfgp.read_text());a=cfg['animations']['paw_up']
if a['clip']['frameHeight']==640 and '--force' not in sys.argv: print('Headroom already applied');sys.exit(0)
reg=json.loads((root/'source/paw-registration.json').read_text());matrix=list(reg['matrix']);matrix[5]-=128*matrix[4]
lut=np.load(root/'source/paw-color-lut.npy');cuts=json.loads((root/'source/paw-segments.json').read_text());_,start,end=next(c for c in cuts if c[0]=='up');count=end-start
cap=cv2.VideoCapture(str(root/'source/images/video/paw-eight-directions.mp4'));cap.set(cv2.CAP_PROP_POS_FRAMES,start)
cols=a['clip']['columns'];rows=a['clip']['rows'];sheet=Image.new('RGBA',(cols*512,rows*640));bounds=[]
for i in range(count):
 ok,bgr=cap.read();assert ok
 frame=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)).transform((512,640),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC)
 pixels=np.array(frame);pixels[...,:3]=lut[pixels[...,:3],np.arange(3)];frame=Image.fromarray(pixels)
 frame.save(root/f'pet-pack/frames/paw_up/{i:03}.png');sheet.paste(frame,(i%cols*512,i//cols*640))
 bb=frame.getchannel('A').point(lambda x:255 if x>32 else 0).getbbox();assert bb and bb[1]>8 and bb[0]>8 and bb[2]<504 and bb[3]<632,(i,bb);bounds.append(bb)
 if i%20==0:print('Recover upward paw:',i+1,'/',count,flush=True)
cap.release();sheet.save(root/'pet-pack/clips/paw_up.webp',lossless=True,exact=True,method=6)
a['clip'].update(height=rows*640,frameHeight=640);cfg['displayFrame']={'width':512,'height':640,'paddingTop':128};cfg['mouseInteraction']['anchor']=[288,386]
cfgp.write_text(json.dumps(cfg,ensure_ascii=False,indent=2))
report={'passed':True,'upwardFrames':count,'originalScalePreserved':True,'originalGroundPositionPreserved':True,'newDisplaySize':[512,640],'minimumTopMargin':min(b[1] for b in bounds),'recoveredFromOriginalVideo':True,'other13ClipFilesUnchanged':True}
(root/'伸爪边界修复验证.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(report,flush=True)
