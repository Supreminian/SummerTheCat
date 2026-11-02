"""Technical edge matting for the supplied yawn video; no motion synthesis."""
import cv2,numpy as np
from PIL import Image

def chroma_matte(rgb):
 h,w=rgb.shape[:2];c=rgb.astype(np.float32);r,g,b=c.transpose(2,0,1)
 pure=(g>80)&((g-np.maximum(r,b))>.65*g)
 values=[]
 for lo,hi in [(0,round(w*.1)),(round(w*.9),w)]:
  rows=np.array([np.median(c[y,lo:hi][pure[y,lo:hi]],axis=0) if pure[y,lo:hi].any() else [np.nan]*3 for y in range(h)],dtype=np.float32)
  for ch in range(3):
   v=rows[:,ch];valid=np.isfinite(v);rows[:,ch]=np.interp(np.arange(h),np.where(valid)[0],v[valid])
  values.append(cv2.GaussianBlur(rows,(1,9),2))
 x=np.linspace(0,1,w,dtype=np.float32)[None,:,None];bg=values[0][:,None,:]*(1-x)+values[1][:,None,:]*x
 alpha=np.clip(1-np.maximum(0,g-np.maximum(r,b))/np.maximum(bg[...,1]-np.maximum(bg[...,0],bg[...,2]),80),0,1)
 n,labels,stats,_=cv2.connectedComponentsWithStats((alpha>.2).astype('uint8'));body=1+np.argmax(stats[1:,4]);mask=(labels==body).astype('uint8');mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8));pad=np.pad(mask,1);cv2.floodFill(pad,None,(0,0),2);solid=(pad[1:-1,1:-1]!=2).astype('uint8');interior=cv2.erode(solid,np.ones((11,11),np.uint8)).astype(bool)&(alpha>.995)
 # Estimate foreground chroma from genuine opaque fur; include a white-hair
 # candidate for fine whiskers that are brighter than their nearest dark fur.
 _,nearLabels=cv2.distanceTransformWithLabels((~interior).astype('uint8'),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
 lut=np.zeros((nearLabels.max()+1,3),np.float32);lut[nearLabels[interior]]=c[interior];prior=lut[nearLabels];prior[...,1]=np.minimum(prior[...,1],(prior[...,0]+prior[...,2])*.5)
 bestAlpha=np.zeros((h,w),np.float32);bestError=np.full((h,w),np.inf,np.float32);chosen=prior.copy()
 for fg in [prior,np.full_like(prior,245)]:
  diff=fg-bg;estimate=np.clip(((c-bg)*diff).sum(axis=2)/np.maximum((diff*diff).sum(axis=2),1),0,1)
  residual=np.mean((c-(estimate[...,None]*fg+(1-estimate[...,None])*bg))**2,axis=2)
  better=residual<bestError;bestError[better]=residual[better];bestAlpha[better]=estimate[better];chosen[better]=fg[better]
 # A small codec noise floor removes empty-background remnants; no erosion of
 # the generated character and no global opaque-outline expansion.
 a=np.clip((bestAlpha-.012)/.988,0,1);a[interior]=1
 near=cv2.dilate(solid,np.ones((31,31),np.uint8)).astype(bool);a[~near]=0
 recovered=np.clip((c-(1-a[...,None])*bg)/np.maximum(a[...,None],.02),0,255)
 # Green decontamination follows neighboring fur chroma rather than clamping
 # to the larger red/blue channel, which produces yellow/magenta fringe.
 luminosity=(recovered[...,0]+recovered[...,2])*.5
 tint=chosen/np.maximum((chosen[...,0:1]+chosen[...,2:3])*.5,5)
 clean=np.clip(luminosity[...,None]*tint,0,255)
 fg=c.copy();boundary=(a>0)&~interior;fg[boundary]=clean[boundary]
 return Image.fromarray(np.dstack((np.round(fg).astype('uint8'),np.round(a*255).astype('uint8'))))
