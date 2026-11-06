// Test-runner transport only. Uses Node HTTPS rather than the global undici
// pool; TLS certificate verification remains enabled. Never logs requests.
import https from 'node:https';
import dns from 'node:dns';
const agent = new https.Agent({keepAlive:true,maxSockets:8,lookup:(hostname,options,callback)=>{
  const ip=process.env.LIVE_SUPABASE_IP;
  if(ip&&hostname==='bqoyfytmrtvjwrpshuhh.supabase.co') {
    if(options.all) callback(null,[{address:ip,family:4}]);else callback(null,ip,4);
  } else dns.lookup(hostname,options,callback);
}});
export function createLiveResponse(response,chunks) {
  // Fetch forbids a body for these statuses, including an empty Buffer.
  const body=[204,205,304].includes(response.statusCode)?null:Buffer.concat(chunks);
  return new Response(body,{status:response.statusCode,headers:response.headers});
}
export function liveFetch(url,options={}) {
  return new Promise((resolve,reject)=>{
    const request=https.request(url,{method:options.method??'GET',headers:options.headers,
      signal:options.signal??AbortSignal.timeout(20000),agent},response=>{
      const chunks=[];
      response.on('data',chunk=>chunks.push(chunk));
      response.on('error',reject);
      response.on('end',()=>{
        try {
          resolve(createLiveResponse(response,chunks));
        } catch(error) {
          reject(error);
        }
      });
    });
    request.on('error',reject);
    request.end(options.body);
  });
}
export function closeLiveTransport(){agent.destroy();}
