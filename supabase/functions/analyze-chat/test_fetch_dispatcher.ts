// 測試專用（正式程式不 import）：streaming_fallback.ts 在模組載入時就抓住當下的
// fetch，測試之後再換 globalThis.fetch 也攔不到串流請求。測試檔把這支放在第一個
// import，串流層抓到的就是這個轉接器；它每次都轉給「當下的」globalThis.fetch。
const realFetch = globalThis.fetch;
const dispatcher: typeof fetch = (input, init) =>
  (globalThis.fetch === dispatcher ? realFetch : globalThis.fetch)(input, init);
globalThis.fetch = dispatcher;
