// Display original whole-character video frames; no motion synthesis or blending.
class SummerMotionRenderer {
 constructor(canvas=document.createElement('canvas')) {
  this.canvas=canvas;canvas.width=canvas.height=512;
  const gl=this.gl=canvas.getContext('webgl2',{alpha:true,antialias:false,premultipliedAlpha:true,preserveDrawingBuffer:true});
  if(!gl)throw Error('无法初始化 WebGL2 动画播放器');
  const vertex=`#version 300 es
  out vec2 uv;void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);uv=vec2(p.x,1.0-p.y);gl_Position=vec4(p*2.0-1.0,0.0,1.0);}`;
  const fragment=`#version 300 es
  precision highp float;uniform sampler2D artwork;uniform sampler2D previousArtwork;
  uniform vec2 atlasSize;uniform vec2 frameSize;uniform vec2 displaySize;uniform vec2 frameOffset;uniform float columns;uniform float frame;uniform float opacity;
  uniform vec2 previousAtlasSize;uniform vec2 previousFrameSize;uniform vec2 previousOffset;uniform float previousColumns;uniform float previousFrame;uniform bool blending;uniform float blendWeight;
  in vec2 uv;out vec4 color;
  vec4 sampleFrame(sampler2D tex,vec2 atlas,vec2 size,float cols,float index,vec2 offset){vec2 local=uv*displaySize-offset;if(any(lessThan(local,vec2(0)))||any(greaterThanEqual(local,size)))return vec4(0);vec2 cell=vec2(mod(index,cols),floor(index/cols));return texture(tex,(cell*size+clamp(local,vec2(.5),size-vec2(.5)))/atlas);}
  void main(){vec4 next=sampleFrame(artwork,atlasSize,frameSize,columns,frame,frameOffset);if(blending){vec4 prev=sampleFrame(previousArtwork,previousAtlasSize,previousFrameSize,previousColumns,previousFrame,previousOffset);next=mix(prev,next,blendWeight);}color=next*opacity;}`;
  const compile=(type,source)=>{const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s};
  this.program=gl.createProgram();gl.attachShader(this.program,compile(gl.VERTEX_SHADER,vertex));gl.attachShader(this.program,compile(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(this.program);if(!gl.getProgramParameter(this.program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(this.program));gl.useProgram(this.program);
  this.uniforms=Object.fromEntries(['artwork','atlasSize','frameSize','displaySize','frameOffset','columns','frame','opacity','previousAtlasSize','previousFrameSize','previousOffset','previousColumns','previousFrame','blending','blendWeight'].map(n=>[n,gl.getUniformLocation(this.program,n)]));gl.uniform1i(this.uniforms.artwork,0);gl.uniform1i(gl.getUniformLocation(this.program,'previousArtwork'),1);gl.disable(gl.BLEND);gl.viewport(0,0,512,512);this.flows={};this.clips={};
 }
 load(config,image,motionData={},clipImages={}) {
  this.config=config;const gl=this.gl;
  if(Object.keys(motionData).length)throw Error('此版本仅播放原始视频帧');
  for(const t of [this.artwork,...Object.values(this.clips)])if(t)gl.deleteTexture(t);this.clips={};
  const texture=im=>{if(Math.max(im.width,im.height)>gl.getParameter(gl.MAX_TEXTURE_SIZE))throw Error('显卡纹理尺寸不足');gl.activeTexture(gl.TEXTURE0);const t=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,t);for(const p of [gl.TEXTURE_MIN_FILTER,gl.TEXTURE_MAG_FILTER])gl.texParameteri(gl.TEXTURE_2D,p,gl.LINEAR);for(const p of [gl.TEXTURE_WRAP_S,gl.TEXTURE_WRAP_T])gl.texParameteri(gl.TEXTURE_2D,p,gl.CLAMP_TO_EDGE);gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,true);gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL,gl.NONE);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,im);return t;};
  this.artwork=texture(image);
  for(const [id,im] of Object.entries(clipImages)){const a=config.animations[id]?.clip;if(!a||im.width!==a.width||im.height!==a.height)throw Error('动作图集尺寸不匹配：'+id);this.clips[id]=texture(im);}
  this.engine='webgl2-complete-video-frames';
  // Decode/upload/first-use GPU work finishes before the playback clock starts.
  for(const id of Object.keys(this.clips))this.draw(id,0);
  gl.finish();this.clear();
 }
 clear(){const gl=this.gl;gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT);}
 draw(id,position,mirror=false,opacity=1,clear=true,transition=null){
  const a=this.config.animations[id];if(!a)return;const gl=this.gl,spec=a.clip||this.config.atlas,pos=((position%a.frames)+a.frames)%a.frames;
  const display=this.config.displayFrame||{width:spec.frameWidth,height:spec.frameHeight,paddingTop:0};if(this.canvas.width!==display.width||this.canvas.height!==display.height){this.canvas.width=display.width;this.canvas.height=display.height;gl.viewport(0,0,display.width,display.height);}if(clear)this.clear();
  gl.useProgram(this.program);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,this.clips[id]||this.artwork);
  const u=this.uniforms;gl.uniform2f(u.atlasSize,spec.width,spec.height);gl.uniform2f(u.frameSize,spec.frameWidth,spec.frameHeight);gl.uniform2f(u.displaySize,display.width,display.height);gl.uniform2f(u.frameOffset,spec.offsetX??display.paddingLeft??0,spec.offsetY??(spec.frameHeight===display.height?0:display.paddingTop||0));gl.uniform1f(u.columns,spec.columns);gl.uniform1f(u.frame,Math.floor(pos));gl.uniform1f(u.opacity,opacity);gl.uniform1i(u.blending,transition?1:0);
  if(!transition){gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,this.clips[id]||this.artwork);gl.activeTexture(gl.TEXTURE0);}
  if(transition){
   const old=this.config.animations[transition.fromState].clip||this.config.atlas;
   gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,this.clips[transition.fromState]||this.artwork);
   gl.uniform2f(u.previousAtlasSize,old.width,old.height);gl.uniform2f(u.previousFrameSize,old.frameWidth,old.frameHeight);gl.uniform2f(u.previousOffset,old.offsetX??display.paddingLeft??0,old.offsetY??(old.frameHeight===display.height?0:display.paddingTop||0));gl.uniform1f(u.previousColumns,old.columns);gl.uniform1f(u.previousFrame,transition.fromFrame);
   const x=Math.max(0,Math.min(1,transition.elapsed/transition.durationMs));gl.uniform1f(u.blendWeight,x*x*(3-2*x));gl.activeTexture(gl.TEXTURE0);
  }
  gl.drawArrays(gl.TRIANGLES,0,3);
 }
 hitRegion(x,y){const w=this.canvas.width,h=this.canvas.height,size=Math.min(128,w,h),left=Math.max(0,Math.min(w-size,Math.floor(x)-size/2)),top=Math.max(0,Math.min(h-size,Math.floor(y)-size/2));const raw=new Uint8Array(size*size*4),bits=new Uint8Array(Math.ceil(size*size/8));this.gl.readPixels(left,h-top-size,size,size,this.gl.RGBA,this.gl.UNSIGNED_BYTE,raw);for(let row=0;row<size;row++)for(let col=0;col<size;col++){const i=row*size+col;if(raw[((size-1-row)*size+col)*4+3]>=48)bits[i>>3]|=1<<(i&7);}return {x:left,y:top,size,data:btoa(String.fromCharCode(...bits))};}
 hitTest(x,y){const w=this.canvas.width,h=this.canvas.height;if(!Number.isFinite(x)||!Number.isFinite(y)||x<0||y<0||x>=w||y>=h)return false;const pixel=new Uint8Array(4);this.gl.readPixels(Math.floor(x),h-1-Math.floor(y),1,1,this.gl.RGBA,this.gl.UNSIGNED_BYTE,pixel);return pixel[3]>=48;}
 readPixels(){const w=this.canvas.width,h=this.canvas.height,raw=new Uint8Array(w*h*4),out=new Uint8ClampedArray(raw.length);this.gl.readPixels(0,0,w,h,this.gl.RGBA,this.gl.UNSIGNED_BYTE,raw);for(let y=0;y<h;y++)for(let x=0;x<w;x++){const p=(y*w+x)*4,q=((h-1-y)*w+x)*4,a=raw[q+3];out[p+3]=a;for(let c=0;c<3;c++)out[p+c]=a?Math.round(raw[q+c]*255/a):0;}return{data:out,width:w,height:h};}
}
