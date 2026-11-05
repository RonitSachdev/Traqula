// Keeps one WebSocket to the Traqula app and forwards meeting snapshots from the content scripts.
// Content scripts cannot open the socket themselves: meeting pages forbid connections to other origins.

const TRAQULA_URL = "ws://127.0.0.1:48213";
let socket = null;
let latest = null;

function connect() {
  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) return;
  socket = new WebSocket(TRAQULA_URL);
  socket.onopen = () => { if (latest) socket.send(JSON.stringify(latest)); };
  socket.onclose = () => { socket = null; setTimeout(connect, 3000); };
  socket.onerror = () => { try { socket.close(); } catch (_) {} };
}

chrome.runtime.onMessage.addListener((message) => {
  if (!message || message.type !== "snapshot") return;
  latest = message.snapshot;
  connect();
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(latest));
});

// A ping every 20 s keeps the service worker, and with it the socket, alive while a meeting is open.
chrome.alarms.create("keepalive", { periodInMinutes: 0.34 });
chrome.alarms.onAlarm.addListener(() => {
  connect();
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: "ping" }));
});
connect();
