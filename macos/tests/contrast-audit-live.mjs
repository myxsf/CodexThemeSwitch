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

const expression = `(() => {
  const root = document.documentElement;
  const parseColor = (value) => {
    const hex = String(value).trim().match(/^#([\\da-f]{3}|[\\da-f]{6}|[\\da-f]{8})$/i);
    if (hex) {
      const raw = hex[1].length === 3 ? [...hex[1]].map((item) => item + item).join("") : hex[1];
      return {
        r: Number.parseInt(raw.slice(0, 2), 16),
        g: Number.parseInt(raw.slice(2, 4), 16),
        b: Number.parseInt(raw.slice(4, 6), 16),
        a: raw.length === 8 ? Number.parseInt(raw.slice(6, 8), 16) / 255 : 1,
      };
    }
    const srgb = String(value).match(/color\\(srgb\\s+([\\d.]+)\\s+([\\d.]+)\\s+([\\d.]+)(?:\\s*\\/\\s*([\\d.]+))?\\)/);
    if (srgb) {
      return { r: Number(srgb[1]) * 255, g: Number(srgb[2]) * 255, b: Number(srgb[3]) * 255, a: Number(srgb[4] ?? 1) };
    }
    const match = String(value).match(/rgba?\\(([^)]+)\\)/);
    if (!match) return null;
    const parts = match[1].split(/[ ,/]+/).filter(Boolean).map(Number);
    return { r: parts[0], g: parts[1], b: parts[2], a: parts[3] ?? 1 };
  };
  const luminance = ({ r, g, b }) => {
    const channel = (value) => {
      const normalized = value / 255;
      return normalized <= .04045 ? normalized / 12.92 : ((normalized + .055) / 1.055) ** 2.4;
    };
    return .2126 * channel(r) + .7152 * channel(g) + .0722 * channel(b);
  };
  const contrast = (foreground, background) => {
    const lighter = Math.max(luminance(foreground), luminance(background));
    const darker = Math.min(luminance(foreground), luminance(background));
    return (lighter + .05) / (darker + .05);
  };
  const style = (element) => {
    if (!(element instanceof Element)) return null;
    const computed = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    const pseudo = (name) => {
      const value = getComputedStyle(element, name);
      return {
        content: value.content,
        display: value.display,
        background: value.backgroundColor,
        backgroundImage: value.backgroundImage === "none" ? "none" : value.backgroundImage.slice(0, 140),
        boxShadow: value.boxShadow,
        inset: [value.top, value.right, value.bottom, value.left],
      };
    };
    return {
      tag: element.tagName.toLowerCase(),
      id: element.id || "",
      cls: String(element.className || "").slice(0, 260),
      role: element.getAttribute("role"),
      text: String(element.innerText || element.textContent || "").trim().replace(/\\s+/g, " ").slice(0, 180),
      color: computed.color,
      background: computed.backgroundColor,
      backgroundImage: computed.backgroundImage === "none" ? "none" : computed.backgroundImage.slice(0, 140),
      boxShadow: computed.boxShadow,
      filter: computed.filter,
      backdropFilter: computed.backdropFilter,
      maskImage: computed.maskImage,
      clipPath: computed.clipPath,
      mixBlendMode: computed.mixBlendMode,
      opacity: Number(computed.opacity),
      position: computed.position,
      zIndex: computed.zIndex,
      pointerEvents: computed.pointerEvents,
      transform: computed.transform,
      isolation: computed.isolation,
      overflow: [computed.overflowX, computed.overflowY],
      padding: computed.padding,
      before: pseudo("::before"),
      after: pseudo("::after"),
      rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) },
    };
  };
  const ancestors = (element, count = 12) => {
    const result = [];
    for (let node = element; node && result.length < count; node = node.parentElement) result.push(style(node));
    return result;
  };
  const selectorPath = (element) => {
    if (!(element instanceof Element)) return "";
    const parts = [];
    for (let node = element; node && node !== document.body && parts.length < 12; node = node.parentElement) {
      let part = node.tagName.toLowerCase();
      if (node.id) {
        parts.unshift(part + "#" + CSS.escape(node.id));
        break;
      }
      const siblings = node.parentElement ? [...node.parentElement.children].filter((item) => item.tagName === node.tagName) : [];
      if (siblings.length > 1) part += ":nth-of-type(" + (siblings.indexOf(node) + 1) + ")";
      parts.unshift(part);
    }
    return "body > " + parts.join(" > ");
  };
  const visible = (element) => {
    const rect = element.getBoundingClientRect();
    const computed = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && computed.display !== "none" && computed.visibility !== "hidden" && Number(computed.opacity) > .05;
  };
  const effectiveBackground = (element) => {
    for (let node = element; node; node = node.parentElement) {
      const color = parseColor(getComputedStyle(node).backgroundColor);
      if (color && color.a >= .92) return { element: style(node), color };
    }
    return { element: style(document.body), color: { r: 255, g: 255, b: 255, a: 1 } };
  };

  const outputCandidates = [...document.querySelectorAll("body *")].filter((element) => {
    if (!visible(element)) return false;
    const text = String(element.innerText || "").trim().replace(/\\s+/g, " ");
    return text.includes("输出") && text.includes("创建文件或站点");
  }).sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });
  const outputPanel = outputCandidates[0] || null;
  const outputLeaves = outputPanel ? [...outputPanel.querySelectorAll("*")].filter((element) => {
    if (!visible(element)) return false;
    return [...element.children].every((child) => !String(child.innerText || "").trim());
  }).map((element) => {
    const foreground = parseColor(getComputedStyle(element).color);
    const background = effectiveBackground(element);
    return { ...style(element), contrast: foreground ? Number(contrast(foreground, background.color).toFixed(2)) : null, backgroundOwner: background.element };
  }).filter((item) => item.text) : [];

  const taskMain = document.querySelector('main.main-surface');
  const brightTaskText = taskMain ? [...taskMain.querySelectorAll("p, li, span")].filter((element) => {
    if (!visible(element) || element.closest('.composer-surface-chrome, #codex-dream-skin-chrome')) return false;
    const text = String(element.innerText || "").trim().replace(/\\s+/g, " ");
    if (text.length < 2 || text.length > 180) return false;
    const foreground = parseColor(getComputedStyle(element).color);
    if (!foreground) return false;
    return foreground.a > .5 && luminance(foreground) > .78;
  }).slice(0, 30).map((element) => {
    return style(element);
  }) : [];

  const composer = document.querySelector('.composer-surface-chrome');
  const sendButton = composer?.querySelector('button[class~="bg-token-foreground"]') || null;
  const sendForeground = sendButton ? parseColor(getComputedStyle(sendButton).color) : null;
  const sendAccent = parseColor(
    getComputedStyle(root).getPropertyValue('--ds-green').trim() ||
    getComputedStyle(root).getPropertyValue('--dream-theme-accent').trim()
  );
  const sendContrast = sendForeground && sendAccent ? Number(contrast(sendForeground, sendAccent).toFixed(2)) : null;
  const sendPass = !sendButton || sendContrast === null || sendContrast >= 3;
  const composerRect = composer?.getBoundingClientRect();
  const samplePoint = (x, y) => {
    const element = document.elementFromPoint(Math.max(0, Math.min(innerWidth - 1, x)), Math.max(0, Math.min(innerHeight - 1, y)));
    return { x: Math.round(x), y: Math.round(y), element: style(element), ancestors: ancestors(element, 5) };
  };
  const composerSurround = composerRect ? {
    left: samplePoint(composerRect.left - 10, composerRect.top + composerRect.height / 2),
    right: samplePoint(composerRect.right + 10, composerRect.top + composerRect.height / 2),
    below: samplePoint(composerRect.left + composerRect.width / 2, composerRect.bottom + 8),
  } : null;
  const composerExpanded = composerRect ? {
    left: composerRect.left - 48,
    top: composerRect.top - 48,
    right: composerRect.right + 48,
    bottom: composerRect.bottom + 48,
  } : null;
  const stickyComposer = composer?.closest('.sticky.bottom-0') || composer?.parentElement?.closest('.sticky.bottom-0');
  const relationToComposer = (element) => {
    if (!composer || !(element instanceof Element)) return null;
    const parent = element.parentElement;
    const composerParent = composer.parentElement;
    const siblings = parent ? [...parent.children] : [];
    return {
      containsComposer: element.contains(composer),
      composerContains: composer.contains(element),
      sameParent: parent === composerParent,
      siblingIndex: siblings.indexOf(element),
      siblingCount: siblings.length,
      composerSiblingIndex: parent === composerParent ? siblings.indexOf(composer) : null,
      parent: parent ? style(parent) : null,
    };
  };
  const composerNearbyElements = composerExpanded ? [...document.body.querySelectorAll("*")].filter((element) => {
    if (!visible(element) || element === composer || composer.contains(element)) return false;
    const rect = element.getBoundingClientRect();
    const intersects = rect.right > composerExpanded.left && rect.left < composerExpanded.right &&
      rect.bottom > composerExpanded.top && rect.top < composerExpanded.bottom;
    if (!intersects || rect.width < 120 || rect.height < 40) return false;
    const computed = getComputedStyle(element);
    const color = parseColor(computed.backgroundColor);
    const darkBackground = color && color.a > .2 && luminance(color) < .3;
    const darkEffect = /rgba?\\(0,\\s*0,\\s*0|rgb\\((?:[0-6]?\\d),/.test(computed.boxShadow) ||
      (computed.backgroundImage !== "none" && /rgb\\((?:[0-6]?\\d),/.test(computed.backgroundImage));
    return darkBackground || darkEffect || computed.backdropFilter !== 'none' || computed.filter !== 'none';
  }) : [];
  const composerNearby = composerNearbyElements.map((element) => ({ ...style(element), path: selectorPath(element), relation: relationToComposer(element) }));
  const composerDarkLayers = composerNearbyElements.filter((element) => (
    stickyComposer?.contains(element) && !element.contains(composer)
  )).map((element) => ({ ...style(element), path: selectorPath(element), relation: relationToComposer(element) }));
  const composerParent = composer?.parentElement || null;
  const composerFamily = {
    composer: composer ? { ...style(composer), path: selectorPath(composer) } : null,
    parent: composerParent ? { ...style(composerParent), path: selectorPath(composerParent) } : null,
    parentChildren: composerParent ? [...composerParent.children].map((element) => ({ ...style(element), path: selectorPath(element) })) : [],
    sticky: stickyComposer ? { ...style(stickyComposer), path: selectorPath(stickyComposer) } : null,
    stickyChildren: stickyComposer ? [...stickyComposer.children].map((element) => ({ ...style(element), path: selectorPath(element) })) : [],
  };
  const outputPass = !outputPanel || outputLeaves.every((item) => item.contrast === null || item.contrast >= 4.5);
  const taskPass = root.getAttribute('data-dream-palette') !== 'light' || brightTaskText.length === 0;
  const stickyComposerStyle = stickyComposer ? getComputedStyle(stickyComposer) : null;
  const composerPass = root.getAttribute('data-dream-palette') !== 'light' || Boolean(
    stickyComposerStyle && stickyComposerStyle.backgroundImage !== 'none' && composerDarkLayers.length === 0
  );
  const topBar = document.querySelector('main.main-surface > header.app-header-tint') || document.elementFromPoint(innerWidth * .55, 20);
  const topBarStyle = getComputedStyle(topBar);
  const topBarColor = parseColor(topBarStyle.backgroundColor);
  const topBarPass = root.getAttribute('data-dream-palette') !== 'light' || Boolean(
    topBarStyle.backgroundImage === 'none' && topBarColor && topBarColor.a >= .9 && luminance(topBarColor) >= .62
  );
  return {
    root: {
      shell: root.getAttribute('data-dream-shell'),
      palette: root.getAttribute('data-dream-palette'),
      themeId: root.getAttribute('data-dream-theme-id'),
      page: root.getAttribute('data-dream-page'),
      tokens: Object.fromEntries(
        [...getComputedStyle(root)]
          .filter((name) => name.startsWith('--color-token-'))
          .map((name) => [name, getComputedStyle(root).getPropertyValue(name).trim()])
      ),
    },
    output: { panel: style(outputPanel), ancestors: ancestors(outputPanel), leaves: outputLeaves, pass: outputPass },
    task: { brightText: brightTaskText, pass: taskPass },
    composer: {
      family: composerFamily,
      ancestors: ancestors(composer, 15),
      surround: composerSurround,
      nearby: composerNearby,
      darkLayers: composerDarkLayers,
      sendButton: style(sendButton),
      sendContrast,
      sendPass,
      pass: composerPass && sendPass,
    },
    topBar: { element: style(topBar), ancestors: ancestors(topBar), pass: topBarPass },
    pass: outputPass && taskPass && composerPass && sendPass && topBarPass,
  };
})()`;

const response = await send("Runtime.evaluate", { expression, returnByValue: true });
socket.close();
if (response.exceptionDetails) throw new Error(response.exceptionDetails.exception?.description || response.exceptionDetails.text);
const result = response.result?.value;
console.log(JSON.stringify(result, null, 2));
if (!result?.pass) process.exit(1);
