const {chromium}=require('/Users/renchengkunwu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),assert=require('assert'),{pathToFileURL}=require('url');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const p=await browser.newPage({viewport:{width:1280,height:1000},deviceScaleFactor:1});const errors=[];
  p.on('pageerror',e=>errors.push(e.message));
  await p.goto(pathToFileURL(path.join(root,'对话框预览.html')).href);
  await p.waitForFunction(()=>window.chatPreviewDebug?.ready,{timeout:60000});
  const chat=p.frameLocator('#chat'),input=chat.locator('#input');
  await p.waitForFunction(()=>chatPreviewDebug.phase==='listening',{timeout:25000});
  await input.fill('今天想和夏天聊聊。');
  await p.screenshot({path:path.join(root,'v30_对话框预览.png')});
  const before=await p.evaluate(()=>({...chatPreviewDebug}));
  await input.evaluate(el=>el.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true})));
  await input.press('Enter');assert.equal(await chat.locator('.message.user').count(),0);
  await input.evaluate(el=>el.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true})));
  await input.press('Shift+Enter');assert((await input.inputValue()).includes('\n'));
  await input.press('Enter');
  await chat.locator('.message.user').waitFor();assert.equal(await input.inputValue(),'');
  await p.waitForFunction(()=>chatPreviewDebug.phase==='idle',{timeout:20000});
  await chat.locator('.message.cat').filter({hasText:'收到啦'}).waitFor();
  await input.fill('<img src=x onerror=alert(1)>');
  await p.waitForFunction(()=>chatPreviewDebug.active);
  await chat.locator('#send').click();
  await p.waitForFunction(()=>!chatPreviewDebug.active,{timeout:20000});
  assert.equal(await chat.locator('.message.user img').count(),0);
  await chat.locator('#close').click();await p.waitForFunction(()=>!chatPreviewDebug.open);
  await p.locator('#open').click();await p.waitForFunction(()=>chatPreviewDebug.open);
  assert.equal(await chat.locator('.message.user').count(),2);
  await input.press('Escape');await p.waitForFunction(()=>!chatPreviewDebug.open);
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(root,'对话框网页验证.json'),JSON.stringify({passed:true,checks:['three-clip entry/loop/exit','Chinese IME Enter handling','Shift+Enter newline','Enter submission','local demo reply','text safely rendered','close and reopen preserves conversation','Escape close'],listeningSnapshot:before,pageErrors:errors},null,2));
  console.log('Conversation UI browser checks passed');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
