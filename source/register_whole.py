"""Technical registration of entire RGBA drawings; never separates anatomy."""
import cv2,numpy as np
from PIL import Image

UPRIGHT_HEIGHT=166.0
UPRIGHT_GROUND=216.0

def upright_landmarks(im):
 """Measure upright sitting stature, ignoring transparent fringes and tail.

 Only for stationary upright seated actions, never a stride, crouch or stretch.
 White hind/ground paws locate the stance midpoint; a raised front paw does
 not determine the ground plane. Dense central alpha locates the ear crown.
 No facial pixels, including the nasal pigment, are edited independently.
 """
 a=np.array(im);h,w=a.shape[:2];yy,xx=np.mgrid[:h,:w]
 core=a[...,3]>180
 white=(a[...,:3].min(axis=2)>145)&core&(yy>h*.76)
 ys,xs=np.where(white)
 if not len(xs):raise ValueError('No grounded white paws in upright cat')
 # Paw extremes include the grounded hind paws on both sides. The previously
 # used rightmost component could instead be a lifted kneading front paw.
 center=(float(np.quantile(xs,.025))+float(np.quantile(xs,.975)))/2
 central=core&(np.abs(xx-center)<h*.23)
 counts=central.sum(axis=1)
 dense=np.where(counts>max(5,h*.035))[0]
 top=float(dense[0]);ground=float(np.quantile(ys,.99))
 return {'centerX':center,'groundY':ground,'crownY':top,'stature':ground-top}

def normalize_upright(im):
 """One scalar for the ENTIRE cat. Preserve every anatomical aspect ratio."""
 marks=upright_landmarks(im);s=UPRIGHT_HEIGHT/marks['stature']
 # One resampling directly from original artwork; no split parts or overlay.
 matrix=(1/s,0,marks['centerX']-144/s,
         0,1/s,marks['groundY']-UPRIGHT_GROUND/s)
 frame=im.transform((256,256),Image.Transform.AFFINE,matrix,
                    resample=Image.Resampling.BICUBIC)
 return frame,{**marks,'uniformScale':s,'scaleX':s,'scaleY':s,
               'groundTarget':UPRIGHT_GROUND,'statureTarget':UPRIGHT_HEIGHT}

def foot_anchor(im,side='right'):
 a=np.array(im);h,w=a.shape[:2];yy,xx=np.mgrid[:h,:w]
 m=(a[...,:3].min(axis=2)>145)&(a[...,3]>150)&(yy>h*.72)
 if side=='ground_right':
  ys,xs=np.where(m)
  if not len(xs):return None
  low=m&(yy>ys.max()-5);y,x=np.where(low);keep=x>=np.percentile(x,75)
  return float(x[keep].mean()),float(y[keep].mean())
 if side=='center':
  ys,xs=np.where(m)
  if not len(xs):return None
  y,x=np.where(m&(yy>ys.max()-7));return float(x.mean()),float(y.mean())
 n,l,s,c=cv2.connectedComponentsWithStats(m.astype('uint8'))
 ids=[i for i in range(1,n) if s[i,4]>10]
 if not ids:return None
 i=(max if side=='right' else min)(ids,key=lambda i:c[i,0])
 y,x=np.where((l==i)&(yy>s[i,1]+s[i,3]-7))
 return float(x.mean()),float(y.mean())

def side_nose_anchor(im):
 a=np.array(im);h,w=a.shape[:2];yy,xx=np.mgrid[:h,:w]
 r,g,b=a[...,:3].astype(float).transpose(2,0,1)
 m=(r-g>20)&(r-b>18)&(g-b<25)&(r>155)&(g>100)&(b>100)&(a[...,3]>150)&(xx<w*.35)&(yy<h*.65)
 n,l,s,c=cv2.connectedComponentsWithStats(m.astype('uint8'))
 ids=[i for i in range(1,n) if s[i,4]>=5]
 if not ids:return None
 i=min(ids,key=lambda i:c[i,0]);return c[i]
