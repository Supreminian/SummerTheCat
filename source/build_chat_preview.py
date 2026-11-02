from pathlib import Path
import base64,json
ROOT=Path(__file__).resolve().parent.parent;S=ROOT/'source';P=ROOT/'pet-pack'
cfg=json.loads((P/'pet.json').read_text());ids=['natural_sit','natural_sit_still','thinking_enter','thinking_loop','thinking_exit']
cfg['animations']={i:cfg['animations'][i] for i in ids};cfg['randomBehavior']['enabled']=False
def uri(p):return 'data:image/webp;base64,'+base64.b64encode(p.read_bytes()).decode()
template='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Summer The Cat v30 · 和夏天聊聊</title>
<style>*{box-sizing:border-box}body{margin:0;background:#eff1e9;color:#2c4636;font-family:-apple-system,'PingFang SC',sans-serif}header{max-width:1120px;margin:36px auto 0;padding:0 32px;display:flex;justify-content:space-between;align-items:center}.overline{font-size:10px;letter-spacing:3px;color:#7a8d73}h1{font-weight:550;letter-spacing:-1px;font-size:29px;margin:10px 0}p{font-size:12px;color:#819078;line-height:1.8}.badge{font-size:11px;padding:8px 13px;border:1px solid #d1ddc7;border-radius:18px}.stage{position:relative;max-width:1120px;height:700px;margin:20px auto;background:radial-gradient(ellipse at 48% 75%,#e0e8d7,transparent 65%);overflow:hidden}#pet{position:absolute;bottom:0;left:36px;width:640px;height:400px;max-width:96%;cursor:pointer}iframe{position:absolute;width:356px;height:414px;border:0;background:transparent;z-index:2}.open{position:absolute;bottom:22px;right:32px;border:1px solid #bfd0b5;background:#f8faf3;color:#436747;border-radius:20px;padding:10px 18px;cursor:pointer;font:12px inherit}.note{max-width:1120px;margin:0 auto 25px;padding:0 32px;font-size:11px;color:#8a9782}button:focus-visible{outline:2px solid #668b59;outline-offset:3px}</style>
<header><div><div class="overline">SUMMER THE CAT / V30</div><h1>和夏天聊一会儿</h1><p>有些想法，说出来就轻了一点。</p></div><span class="badge">本地交互预览</span></header>
<main class="stage"><canvas id="pet" aria-label="夏天猫咪，点击打开对话框"></canvas><iframe id="chat" title="和夏天聊聊"></iframe><button class="open" id="open">和夏天聊聊 ↗</button></main><p class="note">Enter 发送 · Shift + Enter 换行 · Esc 收起　　当前为界面演示，消息仅保留在本次窗口中。</p>
<script>
__RENDERER__
__PLAYBACK__
__MOUSE__
__CHAT_MOTION__
const config=__CONFIG__,clipData=__CLIPS__,atlasURI=__ATLAS__,chatHTML=__CHAT_HTML__;
const canvas=document.querySelector('#pet'),frame=document.querySelector('#chat');let playback,renderer,motion,ready=false,pendingReply=false,chatReady=false,open=true,last=0;
function send(value){frame.contentWindow.postMessage({source:'summer-host',...value},'*');}
function position(){const stage=document.querySelector('.stage').getBoundingClientRect(),rect=canvas.getBoundingClientRect();let x=rect.left-stage.left+692/1024*rect.width-14;let side='right';if(x+356>stage.width){x=rect.left-stage.left+392/1024*rect.width-342;side='left'};frame.style.left=Math.max(0,x)+'px';frame.style.top=Math.max(12,rect.top-stage.top+224/640*rect.height-414+22)+'px';send({type:'layout',side});}
function show(){if(!ready)return;open=true;frame.style.display='';motion.begin();send({type:'open'});position();}
function hide(){open=false;frame.style.display='none';motion.finish();}
window.addEventListener('message',event=>{if(event.source!==frame.contentWindow||event.data?.source!=='summer-chat')return;const v=event.data;
 if(v.type==='ready'){chatReady=true;send({type:'configuration',preview:true,configured:false});frame.contentDocument.querySelector('#connection').textContent='离线预览 · 不调用 API';if(ready)show();}
 if(v.type==='begin')motion?.begin();
 if(v.type==='settings')send({type:'response-error',text:'这是离线界面预览。请打开 Summer The Cat AI.app 配置 OpenAI。',retry:false});
 if(v.type==='cancel'){pendingReply=false;motion.finish();send({type:'response-error',text:'已停止预览回复。',retry:false});}
 if(v.type==='clear'){pendingReply=false;motion.finish();send({type:'clear'});}
 if(v.type==='close')hide();
 if(v.type==='submit'){pendingReply=true;motion.finish();}
});
frame.srcdoc=chatHTML;document.querySelector('#open').onclick=show;canvas.onclick=show;window.addEventListener('resize',position);
(async()=>{renderer=new SummerMotionRenderer(canvas);const atlas=new Image();atlas.src=atlasURI;await atlas.decode();const clips={};await Promise.all(Object.entries(clipData).map(async([id,src])=>{const image=new Image();image.src=src;await image.decode();clips[id]=image;}));renderer.load(config,atlas,{},clips);
 playback=new SummerPlayback(config);playback.setRandomBehavior(false);const interaction=new SummerMouseInteraction(playback);
 motion=new SummerChatMotion(playback,interaction,value=>{send({type:'status',phase:value.phase});if(value.phase==='idle'&&pendingReply){pendingReply=false;send({type:'reply',text:'收到啦，这条消息已留在当前对话里。\\n现在是本地界面演示，等接入 AI 后，我就能认真回答你了。'});}});
 ready=true;if(chatReady)show();requestAnimationFrame(tick);
})().catch(error=>{document.querySelector('.note').textContent='素材加载失败：'+error.message;console.error(error)});
function tick(now){const dt=last?Math.min(100,now-last):0;last=now;playback.advance(dt);renderer.draw(playback.state,playback.frame,false,1,true,playback.transition);playback.markPresented();window.chatPreviewDebug={ready,state:playback.state,frame:playback.frame,phase:motion.phase,active:motion.active,pending:playback.pendingState,open};requestAnimationFrame(tick);}
</script></html>'''
for token,value in {'__RENDERER__':(S/'motion-renderer.js').read_text(),'__PLAYBACK__':(S/'playback.js').read_text(),'__MOUSE__':(S/'mouse-interaction.js').read_text(),'__CHAT_MOTION__':(S/'chat-motion.js').read_text(),'__CONFIG__':json.dumps(cfg,ensure_ascii=False),'__CLIPS__':json.dumps({i:uri(P/cfg['animations'][i]['clip']['file']) for i in ids}),'__ATLAS__':json.dumps(uri(P/'spritsheet.webp')),'__CHAT_HTML__':json.dumps((S/'chat.html').read_text(),ensure_ascii=False).replace('</script>','<\\/script>')}.items():
 template=template.replace(token,value)
(ROOT/'对话框预览.html').write_text(template)
print('Built offline conversation preview',flush=True)
