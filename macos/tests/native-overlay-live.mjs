#!/usr/bin/env node

const port = Number(process.argv[2] || 9341);
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === "page" && item.url?.startsWith("app://") && item.webSocketDebuggerUrl);
if (!target) throw new Error("Codex page target not found");
const url = new URL(target.webSocketDebuggerUrl);
if (!["127.0.0.1", "localhost", "::1"].includes(url.hostname) || Number(url.port) !== port) {
  throw new Error("Rejected non-loopback debugger URL");
}

const socket = new WebSocket(url);
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});
let nextId = 1;
const pending = new Map();
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  const waiter = pending.get(message.id);
  if (!waiter) return;
  pending.delete(message.id);
  if (message.error) waiter.reject(new Error(message.error.message));
  else waiter.resolve(message.result);
});
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});

const buttonResponse = await send("Runtime.evaluate", { expression: `(() => {
  const chrome = document.getElementById('codex-dream-skin-chrome');
  const composer = document.querySelector('.composer-surface-chrome');
  const addButton = composer?.querySelector('button[aria-label="添加文件等内容"]');
  if (!chrome || !addButton) throw new Error('Theme chrome or native Add button missing');
  const box = addButton.getBoundingClientRect();
  const top = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
  return { x: box.left + box.width / 2, y: box.top + box.height / 2, top: top?.outerHTML?.slice(0, 300) };
})()`, returnByValue: true });
if (buttonResponse.exceptionDetails) throw new Error(buttonResponse.exceptionDetails.exception?.description || buttonResponse.exceptionDetails.text);
const point = buttonResponse.result?.value;
await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: point.x, y: point.y, button: "none" });
await send("Input.dispatchMouseEvent", { type: "mousePressed", x: point.x, y: point.y, button: "left", buttons: 1, clickCount: 1 });
await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: point.x, y: point.y, button: "left", buttons: 0, clickCount: 1 });

const expression = `(async () => {
  await new Promise((resolve) => setTimeout(resolve, 500));
  const chrome = document.getElementById('codex-dream-skin-chrome');
  const overlays = [...document.querySelectorAll('[data-radix-popper-content-wrapper], [role="menu"], [role="dialog"], div.z-50')]
    .filter((node) => {
      const box = node.getBoundingClientRect();
      const style = getComputedStyle(node);
      return box.width > 80 && box.height > 40 && style.display !== 'none' && style.visibility !== 'hidden';
    });
  const overlay = overlays.find((node) => !node.closest('#codex-dream-skin-chrome'));
  const box = overlay?.getBoundingClientRect();
  const centerTop = box ? document.elementFromPoint(box.left + box.width / 2, box.top + 24) : null;
  const cardOpacity = Math.max(0, ...[...chrome.querySelectorAll('.dream-skin-card-visual')]
    .map((node) => Number.parseFloat(getComputedStyle(node).opacity)));
  const result = {
    clickedTop: ${JSON.stringify(null)},
    addState: document.querySelector('.composer-surface-chrome button[aria-label="添加文件等内容"]')?.getAttribute('data-state'),
    overlayFound: Boolean(overlay),
    overlayText: (overlay?.innerText || '').trim().slice(0, 240),
    overlayOnTop: Boolean(overlay && centerTop && (centerTop === overlay || overlay.contains(centerTop))),
    chromeOverlayFlag: chrome.hasAttribute('data-native-overlay-open'),
    cardOpacity,
  };
  const visibleOpenNodes = [...document.querySelectorAll('[data-state="open"]')].map((node) => {
    const rect = node.getBoundingClientRect();
    return { tag: node.tagName, role: node.getAttribute('role'), cls: String(node.className).slice(0, 160), text: (node.innerText || '').trim().slice(0, 160), rect: [rect.x, rect.y, rect.width, rect.height] };
  }).filter((item) => item.rect[2] > 0 && item.rect[3] > 0);
  const positionedCandidates = [...document.body.querySelectorAll('*')].map((node) => {
    const rect = node.getBoundingClientRect();
    const style = getComputedStyle(node);
    const text = (node.innerText || '').trim().replace(/\\s+/g, ' ');
    return { tag: node.tagName, role: node.getAttribute('role'), cls: String(node.className).slice(0, 160), text: text.slice(0, 180), position: style.position, z: style.zIndex, background: style.backgroundColor, rect: [rect.x, rect.y, rect.width, rect.height] };
  }).filter((item) => item.text.length > 4 && item.rect[2] > 140 && item.rect[3] > 60 &&
    (item.position === 'fixed' || item.position === 'absolute' || (item.z !== 'auto' && Number(item.z) > 20)))
    .slice(-30);
  return { ...result, visibleOpenNodes, positionedCandidates, pass: result.overlayFound && result.overlayText.length > 8 && result.overlayOnTop && result.chromeOverlayFlag && result.cardOpacity === 0 };
})()`;
const response = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
socket.close();
if (response.exceptionDetails) throw new Error(response.exceptionDetails.exception?.description || response.exceptionDetails.text);
const result = response.result?.value;
result.clickedTop = point.top;
console.log(JSON.stringify(result, null, 2));
if (!result?.pass) process.exit(1);
