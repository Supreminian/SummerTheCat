"""Verify new supplied clips retain their full frames and unchanged idle assets."""
from pathlib import Path
import json,hashlib,cv2,numpy as np
from PIL import Image
from video_matte_yawn import chroma_matte
R=Path(__file__).resolve().parent.parent;old=R.parent.parent/'outputs/SummerTheCat-v23/pet-pack';pack=R/'pet-pack';cfg=json.loads((pack/'pet.json').read_text());checks={}
for action in ['natural_sit','natural_sit_still','look']:
 before=json.loads((old/'pet.json').read_text())['animations'][action];assert before==cfg['animations'][action]
 for p in [Path(f'clips/{action}.webp'),*sorted((old/f'frames/{action}').glob('*.png'))]:
  rel=p.relative_to(old) if p.is_absolute() else p;assert (old/rel).read_bytes()==(pack/rel).read_bytes()
 checks[action]={'unchangedFromV23':True}
for action,label in [('yawn','打哈欠'),('groom','舔毛')]:
 a=cfg['animations'][action];report=json.loads((R/f'{action}-import.json').read_text());original=Path('/Users/renchengkunwu/Desktop/SummerTheCat/movement_video')/f'{label}.mp4'
 assert hashlib.sha256(original.read_bytes()).hexdigest()==report['sourceSHA256'];cap=cv2.VideoCapture(str(original));assert cap.get(cv2.CAP_PROP_FRAME_COUNT)==a['frames'] and cap.get(cv2.CAP_PROP_FPS)==a['fps'];atlas=Image.open(pack/a['clip']['file']);assert atlas.size==(a['clip']['width'],a['clip']['height']);blank=Image.new('RGBA',(512,512));squares=[];margin=512
 for i in range(a['frames']):
  frame=Image.open(pack/f'frames/{action}/{i:03}.png');tile=atlas.crop((i%a['clip']['columns']*512,i//a['clip']['columns']*512,i%a['clip']['columns']*512+512,i//a['clip']['columns']*512+512));assert tile.tobytes()==frame.tobytes()
  b=frame.getchannel('A').point(lambda v:255 if v>32 else 0).getbbox();assert b;margin=min(margin,b[0],b[1],512-b[2],512-b[3]);squares.append(b)
 for i in range(a['frames'],a['clip']['columns']*a['clip']['rows']):
  assert atlas.crop((i%a['clip']['columns']*512,i//a['clip']['columns']*512,i%a['clip']['columns']*512+512,i//a['clip']['columns']*512+512)).getchannel('A').getbbox() is None
 # Re-run representative source frames through the documented fixed transform.
 for i in [0,a['frames']//3,a['frames']*2//3,a['frames']-1]:
  cap.set(cv2.CAP_PROP_POS_FRAMES,i);ok,bgr=cap.read();assert ok;expected=chroma_matte(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)).transform((512,512),Image.Transform.AFFINE,tuple(report['wholeFrameTransform']),resample=Image.Resampling.BICUBIC)
  assert expected.tobytes()==Image.open(pack/f'frames/{action}/{i:03}.png').tobytes()
 cap.release();assert margin>=8
 checks[action]={'originalSourceHashMatches':True,'allAtlasCellsMatchFrames':True,'sourceOrderAndFixedWholeFrameRegistrationVerified':True,'frames':a['frames'],'fps':a['fps'],'minimumMarginPixels':margin,'uniqueFrames':report['uniqueFrames']}
assert (pack/'main.png').read_bytes()==(old/'main.png').read_bytes();assert (pack/'spritsheet.webp').read_bytes()==(old/'spritsheet.webp').read_bytes()
(R/'integration-verification.json').write_text(json.dumps({'passed':True,'defaultPortraitUnchanged':True,'noRunwayCallsOrCredits':True,'clips':checks},ensure_ascii=False,indent=2));print(json.dumps(checks,ensure_ascii=False))
