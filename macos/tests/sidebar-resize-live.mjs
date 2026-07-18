#!/usr/bin/env node

const port = Number(process.argv[2] || 9341);
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === "page" && item.url?.startsWith("app://") && item.webSocketDebuggerUrl);
if (!target) throw new Error("Codex page target not found");
const wsURL = new URL(target.webSocketDebuggerUrl);
if (!["127.0.0.1", "localhost", "::1"].includes(wsURL.hostname) || Number(wsURL.port) !== port) {
  throw new Error("Rejected non-loopback debugger URL");
}

const ws = new WebSocket(wsURL);
await new Promise((resolve, reject) => {
  ws.addEventListener("open", resolve, { once: true });
  ws.addEventListener("error", reject, { once: true });
});
let nextId = 1;
const pending = new Map();
ws.addEventListener("message", (event) => {
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
  ws.send(JSON.stringify({ id, method, params }));
});

const setupExpression = `(() => {
  const aside = document.querySelector('aside.app-shell-left-panel');
  const home = document.querySelector('[role="main"].dream-skin-home');
  const chrome = document.getElementById('codex-dream-skin-chrome');
  const separator = document.querySelector('aside.app-shell-left-panel > [role="separator"][aria-orientation="vertical"]');
  if (!(aside instanceof HTMLElement) || !home || !chrome || !(separator instanceof HTMLElement)) {
    throw new Error('Required themed home or sidebar separator nodes are missing');
  }
  const separatorBox = separator.getBoundingClientRect();
  return { originalWidth: aside.getBoundingClientRect().width, x: separatorBox.left + separatorBox.width / 2, y: Math.max(100, Math.min(innerHeight - 100, separatorBox.top + separatorBox.height / 2)) };
})()`;
const setup = await send("Runtime.evaluate", { expression: setupExpression, returnByValue: true });
if (setup.exceptionDetails) throw new Error(setup.exceptionDetails.exception?.description || setup.exceptionDetails.text);
const origin = setup.result?.value;

const sampleExpression = `(() => {
      const aside = document.querySelector('aside.app-shell-left-panel');
      const home = document.querySelector('[role="main"].dream-skin-home');
      const chrome = document.getElementById('codex-dream-skin-chrome');
      const main = document.querySelector('main.main-surface') || document.querySelector('main');
      const mainBox = main.getBoundingClientRect();
      const nativeCards = [...home.querySelectorAll('[class~="group/home-suggestions"] button')].slice(0, 4);
      const errors = nativeCards.map((button, index) => {
        const nativeBox = button.getBoundingClientRect();
        const visualBox = chrome.querySelector('.dream-skin-card-visual[data-card-index="' + (index + 1) + '"]')?.getBoundingClientRect();
        if (!visualBox) return 999;
        return Math.max(
          Math.abs(nativeBox.x - visualBox.x), Math.abs(nativeBox.y - visualBox.y),
          Math.abs(nativeBox.width - visualBox.width), Math.abs(nativeBox.height - visualBox.height),
        );
      });
      const chromeBox = chrome.getBoundingClientRect();
      return {
        width: aside.getBoundingClientRect().width,
        maxCardError: Math.max(...errors),
        chromeMainError: Math.max(Math.abs(chromeBox.x - mainBox.x), Math.abs(chromeBox.width - mainBox.width)),
        crossesMain: [...chrome.querySelectorAll('.dream-skin-card-visual')].some((node) => {
          const box = node.getBoundingClientRect();
          return box.left < mainBox.left - 2 || box.right > mainBox.right + 2;
        }),
        documentOverflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth,
      };
})()`;

const samples = [];
for (const width of [240, 420, origin.originalWidth]) {
  const startX = origin.x;
  await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: origin.x, y: origin.y, button: "none" });
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: origin.x, y: origin.y, button: "left", buttons: 1, clickCount: 1 });
  for (let step = 1; step <= 12; step += 1) {
    const x = startX + ((width - startX) * step / 12);
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y: origin.y, button: "left", buttons: 1 });
    await new Promise((resolve) => setTimeout(resolve, 18));
  }
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: width, y: origin.y, button: "left", buttons: 0, clickCount: 1 });
  await new Promise((resolve) => setTimeout(resolve, 350));
  const response = await send("Runtime.evaluate", { expression: sampleExpression, returnByValue: true });
  samples.push(response.result?.value);
  const separator = await send("Runtime.evaluate", { expression: `(() => { const box = document.querySelector('aside.app-shell-left-panel > [role="separator"][aria-orientation="vertical"]')?.getBoundingClientRect(); return box ? { x: box.left + box.width / 2, y: ${origin.y} } : null; })()`, returnByValue: true });
  if (separator.result?.value) origin.x = separator.result.value.x;
}
const targetWidths = [240, 420, origin.originalWidth];
const value = { samples, pass: samples.every((sample, index) => Math.abs(sample?.width - targetWidths[index]) <= 4 && sample?.maxCardError <= 2 && sample?.chromeMainError <= 2 && !sample?.crossesMain && !sample?.documentOverflowX) };
ws.close();
console.log(JSON.stringify(value, null, 2));
if (!value?.pass) process.exit(1);
