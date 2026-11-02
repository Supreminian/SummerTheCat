const {chromium}=require('/Users/renchengkunwu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const {pathToFileURL}=require('url'),path=require('path'),fs=require('fs'),assert=require('assert');
(async()=>{const root=path.resolve(__dirname,'..'),b=await chromium.launch({channel:'chrome',headless:true});try{
 const p=await b.newPage({viewport:{width:1500,height:1700}}),errors=[];p.on('pageerror',e=>errors.push(e.message));await p.goto(pathToFileURL(path.join(root,'动画预览.html')).href);await p.waitForFunction(()=>previewDebug?.ready,{timeout:60000});assert(await p.locator('#mouse-interaction').isChecked());
 const rect=await p.locator('#hero').boundingBox(),directions=['up','up_right','right','down_right','down','down_left','left','up_left'],results=[];
 for(let i=0;i<8;i++){
  await p.evaluate(()=>{playback.setRandomBehavior(false);playback.setTailMode('moving');playback.setState('natural_sit',true);playback.setPaused(false);interaction.setEnabled(true);interaction.latched=false;interaction.lastTriggerPoint=null;interaction.cooldownUntil=0;interaction.clearPointer();});
  const angle=i*Math.PI/4,x=288+Math.sin(angle)*160,y=386-Math.cos(angle)*160;
  await p.mouse.move(rect.x+x/512*rect.width,rect.y+y/640*rect.height);await p.waitForFunction(id=>previewDebug.active===id,'paw_'+directions[i],{timeout:2000});
  results.push({direction:directions[i],state:await p.evaluate(()=>previewDebug.active)});await p.evaluate(()=>playback.setPaused(true));
 }
 // The visual hand appears over the cat and its nearby interaction area.
 await p.evaluate(()=>{playback.setPaused(false);interaction.setEnabled(true);});
 await p.mouse.move(rect.x+288/512*rect.width,rect.y+386/640*rect.height);await p.waitForTimeout(80);
 assert((await p.evaluate(()=>getComputedStyle(document.documentElement).cursor)).includes('data:image/svg+xml'),'Nearby body shows petting hand');
 await p.mouse.move(2,2);await p.waitForTimeout(80);assert.equal(await p.evaluate(()=>document.documentElement.style.cursor),'','Leaving restores cursor');
 await p.mouse.move(rect.x+288/512*rect.width,rect.y+386/640*rect.height);await p.evaluate(()=>playback.setPaused(true));await p.waitForTimeout(80);assert.equal(await p.evaluate(()=>document.documentElement.style.cursor),'','Pause restores cursor');
 await p.locator('#frame').evaluate(e=>{e.value=40;e.dispatchEvent(new Event('input'))});await p.screenshot({path:path.join(root,'网页互动截图.png')});
 await p.evaluate(()=>{playback.setState('natural_sit',true);playback.setPaused(false);interaction.cooldownUntil=0;interaction.latched=false;interaction.lastTriggerPoint=null;interaction.clearPointer();});await p.locator('#mouse-interaction').uncheck();
 await p.mouse.move(rect.x+448/512*rect.width,rect.y+386/640*rect.height);await p.waitForTimeout(300);assert.equal(await p.evaluate(()=>previewDebug.active),'natural_sit');
 await p.evaluate(()=>{interaction.setEnabled(true);playback.setState('yawn',true);playback.setPaused(false);interaction.clearPointer();});await p.mouse.move(rect.x+288/512*rect.width,rect.y+206/640*rect.height);await p.waitForTimeout(350);assert.equal(await p.evaluate(()=>previewDebug.active),'yawn');

 await p.evaluate(()=>{playback.setState('paw_up',true);playback.setPaused(true);playback.seek(25);});await p.waitForTimeout(80);
 const bounds=await p.evaluate(()=>{const {data,width,height}=renderer.readPixels();let top=height,left=width,right=0,bottom=0;for(let y=0;y<height;y++)for(let x=0;x<width;x++)if(data[(y*width+x)*4+3]>32){top=Math.min(top,y);left=Math.min(left,x);right=Math.max(right,x);bottom=Math.max(bottom,y);}return{top,left,right,bottom,width,height};});
 assert.equal(bounds.height,640);assert(bounds.top>8&&bounds.left>8&&bounds.right<504&&bounds.bottom<632,'GPU-rendered upward paw has transparent margin on all sides');
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'网页鼠标互动验证.json'),JSON.stringify({passed:true,actualBrowserMouseDirectionResults:results,disableSuppressesHover:true,existingActionNotInterrupted:true,upwardPawUnclippedOnGPU:true,gpuBounds:bounds,pettingHandNearCat:true,ordinaryCursorOnExitAndPause:true,pageErrors:errors},null,2));console.log('Actual browser mouse movements trigger all eight original gestures; disable and busy-action guards passed');
}finally{await b.close();}})().catch(e=>{console.error(e);process.exit(1)});
