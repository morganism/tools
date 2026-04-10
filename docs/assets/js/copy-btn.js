
// ── COPY ──────────────────────────────────────────────────────
async function copyCode(clickedId){
  const code=document.getElementById('code-display').textContent.replace(/\s/g,' ');
  if(code==='------')return;
  await navigator.clipboard.writeText(code).catch(()=>{});
  const btn=document.getElementById(clickedId);
  btn.textContent='Copied!';btn.classList.add('copied');
  setTimeout(()=>{btn.textContent='Copy';btn.classList.remove('copied');},1500);
}
