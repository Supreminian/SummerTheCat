import cv2,numpy as np
from PIL import Image

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
