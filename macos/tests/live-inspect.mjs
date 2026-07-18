#!/usr/bin/env node

const port = Number(process.argv[2] || 9341);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("Invalid port");

const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === "page" && item.url?.startsWith("app://") && item.webSocketDebuggerUrl);
if (!target) throw new Error("Codex page target not found");
const wsURL = new URL(target.webSocketDebuggerUrl);
if (!['127.0.0.1', 'localhost', '::1'].includes(wsURL.hostname) || Number(wsURL.port) !== port) {
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

await send("Runtime.enable");
const expression = `(() => {
  const style = (element) => {
    if (!(element instanceof Element)) return null;
    const cs = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return {
      tag: element.tagName.toLowerCase(),
      id: element.id || "",
      cls: String(element.className || "").slice(0, 220),
      text: String(element.innerText || element.textContent || "").trim().replace(/\\s+/g, " ").slice(0, 120),
      color: cs.color,
      background: cs.backgroundColor,
      backgroundImage: cs.backgroundImage === "none" ? "none" : "present",
      opacity: Number(cs.opacity),
      visibility: cs.visibility,
      display: cs.display,
      position: cs.position,
      flex: [cs.flexDirection, cs.justifyContent, cs.alignItems, cs.gap],
      border: cs.border,
      rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) },
    };
  };
  const ancestors = (element, count = 7) => {
    const result = [];
    for (let node = element; node && result.length < count; node = node.parentElement) result.push(style(node));
    return result;
  };
  const visibleText = [...document.querySelectorAll('aside.app-shell-left-panel button, aside.app-shell-left-panel a, aside.app-shell-left-panel [role="button"]')]
    .filter((element) => {
      const rect = element.getBoundingClientRect();
      return rect.width > 20 && rect.height > 10;
    })
    .slice(0, 24)
    .map(style);
  const composer = document.querySelector('.composer-surface-chrome');
  const project = document.querySelector('[class~="group/project-selector"]') || document.querySelector('[class*="project-selector"]');
  const home = document.querySelector('[role="main"].dream-skin-home');
  const suggestions = home?.querySelector('[class~="group/home-suggestions"]');
  return {
    root: {
      shell: document.documentElement.getAttribute('data-dream-shell'),
      palette: document.documentElement.getAttribute('data-dream-palette'),
      theme: document.documentElement.getAttribute('data-dream-theme-id'),
      page: document.documentElement.getAttribute('data-dream-page'),
    },
    stylesheet: (() => {
      const element = document.getElementById('codex-dream-skin-style');
      let ruleCount = null;
      let readError = null;
      try { ruleCount = element?.sheet?.cssRules?.length ?? null; } catch (error) { readError = String(error); }
      return {
        present: Boolean(element),
        connected: Boolean(element?.isConnected),
        textLength: element?.textContent?.length ?? 0,
        disabled: element?.sheet?.disabled ?? null,
        ruleCount,
        readError,
        parent: element?.parentElement?.tagName ?? null,
        dataset: element ? { ...element.dataset } : {},
        start: element?.textContent?.slice(0, 160) ?? "",
        end: element?.textContent?.slice(-240) ?? "",
        firstSelectors: (() => {
          try { return [...(element?.sheet?.cssRules ?? [])].slice(0, 8).map((rule) => rule.selectorText || rule.cssText.slice(0, 100)); }
          catch { return []; }
        })(),
      };
    })(),
    runtimeState: (() => {
      const state = window.__CODEX_DREAM_SKIN_STATE__;
      return state ? {
        version: state.version,
        themeId: state.themeId,
        profile: state.profile,
        hasInstanceToken: Boolean(state.instanceToken),
        disabled: Boolean(window.__CODEX_DREAM_SKIN_DISABLED__),
      } : null;
    })(),
    sidebarControls: visibleText,
    composerAncestors: ancestors(composer),
    projectAncestors: ancestors(project),
    homeAncestors: ancestors(home, 4),
    homeFirstChildren: home ? [...home.children].map(style) : [],
    suggestions: style(suggestions),
    composerControls: composer ? [...composer.querySelectorAll('button, [role="button"], [data-state]')].map((element) => ({
      ...style(element),
      ariaLabel: element.getAttribute('aria-label'),
      title: element.getAttribute('title'),
      dataState: element.getAttribute('data-state'),
      dataSlot: element.getAttribute('data-slot'),
    })) : [],
    separators: [...document.querySelectorAll('[role="separator"], [class*="resize-handle"], [class*="resizeHandle"]')].map((element) => ({
      ...style(element),
      ariaOrientation: element.getAttribute('aria-orientation'),
      dataPanelResizeHandleId: element.getAttribute('data-panel-resize-handle-id'),
    })),
    runningAnimations: document.getAnimations({ subtree: true }).filter((animation) => animation.playState === 'running').slice(0, 40).map((animation) => ({
      target: style(animation.effect?.target),
      currentTime: animation.currentTime,
    })),
  };
})()`;
const inspection = await send("Runtime.evaluate", { expression, returnByValue: true });
if (inspection.exceptionDetails) {
  throw new Error(inspection.exceptionDetails.exception?.description || inspection.exceptionDetails.text);
}

const stabilityExpression = `(async () => {
  const counts = { total: 0, childList: 0, attributes: 0, characterData: 0, chrome: 0, style: 0 };
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      counts.total += 1;
      counts[mutation.type] += 1;
      const element = mutation.target instanceof Element ? mutation.target : mutation.target.parentElement;
      if (element?.closest?.('#codex-dream-skin-chrome')) counts.chrome += 1;
      if (element?.id === 'codex-dream-skin-style') counts.style += 1;
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, characterData: true });
  let cls = 0;
  let layoutObserver;
  try {
    layoutObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) if (!entry.hadRecentInput) cls += entry.value;
    });
    layoutObserver.observe({ type: 'layout-shift', buffered: true });
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 5000));
  observer.disconnect();
  layoutObserver?.disconnect();
  return { counts, cls, runningAnimations: document.getAnimations({ subtree: true }).filter((animation) => animation.playState === 'running').length };
})()`;
const stability = await send("Runtime.evaluate", { expression: stabilityExpression, awaitPromise: true, returnByValue: true });

console.log(JSON.stringify({ target: { id: target.id, title: target.title }, inspection: inspection.result?.value, stability: stability.result?.value }, null, 2));
ws.close();
