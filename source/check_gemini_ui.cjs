const {chromium}=require('/Users/renchengkunwu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),assert=require('assert'),{pathToFileURL}=require('url');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const p=await browser.newPage({viewport:{width:356,height:414},deviceScaleFactor:2});const errors=[];p.on('pageerror',e=>errors.push(e.message));
  await p.addInitScript(()=>{window.outbox=[];window.webkit={messageHandlers:{chat:{postMessage:value=>window.outbox.push(value)}}};});
  await p.goto(pathToFileURL(path.join(__dirname,'chat.html')).href);
  await p.evaluate(()=>chatReceive({type:'configuration',configured:true,provider:'Google Gemini',model:'gemini-3.5-flash-lite'}));
  assert((await p.locator('#connection').textContent()).includes('Google Gemini'));
  await p.locator('#settings').click();assert.equal(await p.evaluate(()=>outbox.at(-1).type),'settings');
  assert.equal(await p.locator('input[type=password]').count(),0);
  const input=p.locator('#input');await input.fill('你好，夏天。');
  await input.evaluate(el=>el.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true})));await input.press('Enter');assert.equal(await p.locator('.user').count(),0);
  await input.evaluate(el=>el.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true})));await input.press('Shift+Enter');assert((await input.inputValue()).includes('\n'));
  await input.press('Enter');assert.equal(await p.locator('.user').count(),1);assert.equal(await p.evaluate(()=>outbox.at(-1).type),'submit');
  await p.evaluate(()=>{chatReceive({type:'response-start'});chatReceive({type:'response-delta',text:'你好！'});chatReceive({type:'response-delta',text:'今天想聊些什么？🐈'});});
  assert((await p.locator('.streaming').textContent()).includes('🐈'));
  await p.locator('#send').click();assert.equal(await p.evaluate(()=>outbox.at(-1).type),'cancel');
  await p.evaluate(()=>chatReceive({type:'response-error',text:'已停止回复，可以重试。',retry:true}));assert.equal(await p.locator('.streaming').count(),0);assert.equal(await p.locator('.retry').count(),1);
  await p.locator('.retry').click();assert.equal(await p.evaluate(()=>outbox.at(-1).type),'retry');
  await p.evaluate(()=>{chatReceive({type:'response-start'});chatReceive({type:'response-delta',text:'<img src=x onerror=alert(1)>'});chatReceive({type:'response-done',text:'你好，我是夏天。今天有什么想和我分享的吗？'});});
  assert.equal(await p.locator('.message img').count(),0);assert.equal(await p.locator('.user').count(),1);
  assert((await p.locator('.cat').last().textContent()).includes('我是夏天'));
  await p.screenshot({path:path.join(root,'Gemini对话界面.png')});
  await p.locator('#new-chat').click();assert.equal(await p.evaluate(()=>outbox.at(-1).type),'clear');await p.evaluate(()=>chatReceive({type:'clear'}));assert.equal(await p.locator('.user').count(),0);
  await p.locator('#close').click();assert.equal(await p.evaluate(()=>outbox.at(-1).type),'close');
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(root,'Gemini界面验证.json'),JSON.stringify({passed:true,liveAPIRequest:false,checks:['native-only key entry','settings action','Chinese IME','Shift+Enter newline','submit','streaming Unicode','stop','retry without duplicate user turn','plain text output','new conversation','close'],pageErrors:errors},null,2));
  console.log('Gemini conversation UI checks passed');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
