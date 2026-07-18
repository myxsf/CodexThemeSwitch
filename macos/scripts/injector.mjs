import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const SKIN_VERSION = "2.2.9";
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"]);
const MAX_ART_BYTES = 16 * 1024 * 1024;

function parseArgs(argv) {
  const options = {
    port: 9341,
    mode: "watch",
    timeoutMs: 30000,
    screenshot: null,
    reload: false,
    themeDir: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--port") options.port = Number(argv[++i]);
    else if (arg === "--once") options.mode = "once";
    else if (arg === "--watch") options.mode = "watch";
    else if (arg === "--verify") options.mode = "verify";
    else if (arg === "--remove") options.mode = "remove";
    else if (arg === "--check-payload") options.mode = "check";
    else if (arg === "--window-smoke") options.mode = "window-smoke";
    else if (arg === "--timeout-ms") options.timeoutMs = Number(argv[++i]);
    else if (arg === "--screenshot") options.screenshot = path.resolve(argv[++i]);
    else if (arg === "--theme-dir") options.themeDir = path.resolve(argv[++i]);
    else if (arg === "--reload") options.reload = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!Number.isInteger(options.port) || options.port < 1024 || options.port > 65535) {
    throw new Error(`Invalid port: ${options.port}`);
  }
  if (!Number.isFinite(options.timeoutMs) || options.timeoutMs < 250 || options.timeoutMs > 120000) {
    throw new Error(`Invalid timeout: ${options.timeoutMs}`);
  }
  return options;
}

function validatedDebuggerUrl(target, port) {
  const url = new URL(target.webSocketDebuggerUrl);
  if (url.protocol !== "ws:" || !LOOPBACK_HOSTS.has(url.hostname) || Number(url.port) !== port) {
    throw new Error(`Rejected non-loopback CDP WebSocket URL: ${url.href}`);
  }
  return url.href;
}

class CdpSession {
  constructor(target, port) {
    this.target = target;
    this.port = port;
    this.ws = new WebSocket(validatedDebuggerUrl(target, port));
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    this.closed = false;
  }

  async open({ enableRuntime = true, enablePage = true } = {}) {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("CDP WebSocket open timed out")), 5000);
      this.ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      this.ws.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("CDP WebSocket open failed")); }, { once: true });
    });
    this.ws.addEventListener("message", (event) => this.onMessage(event));
    this.ws.addEventListener("close", () => {
      this.closed = true;
      for (const waiter of this.pending.values()) {
        clearTimeout(waiter.timeout);
        waiter.reject(new Error("CDP socket closed"));
      }
      this.pending.clear();
    });
    if (enableRuntime) await this.send("Runtime.enable");
    if (enablePage) await this.send("Page.enable");
    return this;
  }

  onMessage(event) {
    const message = JSON.parse(String(event.data));
    if (message.id) {
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      clearTimeout(waiter.timeout);
      this.pending.delete(message.id);
      if (message.error) waiter.reject(new Error(`${message.error.message} (${message.error.code})`));
      else waiter.resolve(message.result);
      return;
    }
    for (const listener of this.listeners.get(message.method) ?? []) listener(message.params ?? {});
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) ?? [];
    listeners.push(listener);
    this.listeners.set(method, listeners);
  }

  send(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("CDP session is closed"));
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP command timed out: ${method}`));
      }, 10000);
      this.pending.set(id, { resolve, reject, timeout });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate(expression) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
      userGesture: false,
    });
    if (result.exceptionDetails) {
      const detail = result.exceptionDetails.exception?.description ?? result.exceptionDetails.text;
      throw new Error(`Renderer evaluation failed: ${detail}`);
    }
    return result.result?.value;
  }

  close() {
    if (!this.closed) this.ws.close();
    this.closed = true;
  }
}

async function listAppTargets(port) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: controller.signal });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const targets = await response.json();
    return targets.filter((item) => {
      if (item.type !== "page" || !item.url?.startsWith("app://") || !item.webSocketDebuggerUrl) return false;
      try {
        validatedDebuggerUrl(item, port);
        return true;
      } catch {
        return false;
      }
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function connectBrowserSession(port) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetch(`http://127.0.0.1:${port}/json/version`, { signal: controller.signal });
    if (!response.ok) throw new Error(`Browser CDP HTTP ${response.status}`);
    const version = await response.json();
    const target = {
      id: "browser",
      title: "Codex Browser",
      url: `http://127.0.0.1:${port}/json/version`,
      webSocketDebuggerUrl: version.webSocketDebuggerUrl,
    };
    const session = new CdpSession(target, port);
    return session.open({ enableRuntime: false, enablePage: false });
  } finally {
    clearTimeout(timeout);
  }
}

async function probeSession(session) {
  return session.evaluate(`(() => {
    const markers = {
      shell: Boolean(document.querySelector('main.main-surface')),
      sidebar: Boolean(document.querySelector('aside.app-shell-left-panel')),
      composer: Boolean(document.querySelector('.composer-surface-chrome')),
      main: Boolean(document.querySelector(
        '[role="main"], main.main-surface, .app-shell-main-content-viewport, .thread-scroll-container',
      )),
    };
    return {
      title: document.title,
      href: location.href,
      markers,
      codex: markers.shell && markers.main && (markers.composer || markers.sidebar),
    };
  })()`);
}

async function connectTarget(target, port) {
  return new CdpSession(target, port).open();
}

async function connectCodexTargets(port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const targets = await listAppTargets(port);
      const connected = [];
      for (const target of targets) {
        let session;
        try {
          session = await connectTarget(target, port);
          const probe = await probeSession(session);
          if (probe?.codex) connected.push({ target, session, probe });
          else session.close();
        } catch (error) {
          session?.close();
          lastError = error;
        }
      }
      if (connected.length) return connected;
      lastError = new Error("No page matched the expected Codex shell markers");
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 350));
  }
  throw new Error(`No verified Codex renderer on 127.0.0.1:${port}: ${lastError?.message ?? "timed out"}`);
}

async function loadTheme(themeDir) {
  const defaultAssetsRoot = path.join(root, "assets");
  let assetsRoot = defaultAssetsRoot;
  if (themeDir) {
    try {
      await fs.access(path.join(themeDir, "theme.json"));
      assetsRoot = themeDir;
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }

  const configPath = path.join(assetsRoot, "theme.json");
  const raw = JSON.parse(await fs.readFile(configPath, "utf8"));
  if (raw.schemaVersion !== 1 || !(raw.image === null || typeof raw.image === "string")) {
    throw new Error(`${configPath} has an unsupported schema or image field`);
  }
  if (typeof raw.image === "string" && (!raw.image || path.basename(raw.image) !== raw.image)) {
    throw new Error("Theme image must stay inside its theme directory");
  }
  const text = (value, fallback, max) => typeof value === "string" && value.trim()
    ? value.trim().slice(0, max) : fallback;
  const color = (value, fallback) => {
    if (typeof value !== "string") return fallback;
    const normalized = value.trim();
    return /^#[0-9a-f]{6}$/i.test(normalized) || /^rgba?\([0-9., %]+\)$/i.test(normalized)
      ? normalized
      : fallback;
  };
  const appearance = raw.appearance === "light" || raw.appearance === "dark" ? raw.appearance : "";
  const artPosition = ["center center", "center top", "center bottom", "left center", "right center", "left top", "right top"]
    .includes(raw.art?.position) ? raw.art.position : "center center";
  const artSize = raw.art?.size === "contain" ? "contain" : "cover";
  const layoutVariants = new Set(["enfp", "purple-night", "miku"]);
  const visualCards = Array.isArray(raw.visual?.cards)
    ? raw.visual.cards.slice(0, 4).map((card) => ({
        icon: text(card?.icon, "✦", 12),
        title: text(card?.title, "Codex 功能", 60),
        detail: text(card?.detail, "", 120),
        action: card?.action === "plugins" ? "plugins" : "prompt",
        prompt: text(card?.prompt, "", 240),
      }))
    : [];
  const visualNoteLines = Array.isArray(raw.visual?.note?.lines)
    ? raw.visual.note.lines.slice(0, 4).map((line) => text(line, "", 80)).filter(Boolean)
    : [];
  const theme = {
    schemaVersion: 1,
    id: text(raw.id, "custom", 80),
    profile: text(raw.profile, raw.id === "qq2007" ? "qq2007" : "inspiration-universe", 40),
    appearance,
    art: { position: artPosition, size: artSize },
    name: text(raw.name, "Codex Dream Skin", 80),
    brandSubtitle: text(raw.brandSubtitle, "CODEX DREAM SKIN", 80),
    tagline: text(raw.tagline, "Make something wonderful.", 160),
    projectPrefix: text(raw.projectPrefix, "选择项目 · ", 80),
    projectLabel: text(raw.projectLabel, "◉  选择项目", 80),
    statusText: text(raw.statusText, "DREAM SKIN ONLINE", 80),
    quote: text(raw.quote, "MAKE SOMETHING WONDERFUL", 80),
    image: raw.image,
    colors: {
      background: color(raw.colors?.background, "#071116"),
      panel: color(raw.colors?.panel, "#0b1a20"),
      panelAlt: color(raw.colors?.panelAlt, "#10272c"),
      accent: color(raw.colors?.accent, "#7cff46"),
      accentAlt: color(raw.colors?.accentAlt, "#b8ff3d"),
      secondary: color(raw.colors?.secondary, "#36d7e8"),
      highlight: color(raw.colors?.highlight, "#642a8c"),
      text: color(raw.colors?.text, "#e9fff1"),
      muted: color(raw.colors?.muted, "#9ebdb3"),
      line: color(raw.colors?.line, "rgba(124, 255, 70, .28)"),
    },
    visual: {
      layoutVariant: layoutVariants.has(raw.visual?.layoutVariant) ? raw.visual.layoutVariant : "",
      sidebar: {
        brand: text(raw.visual?.sidebar?.brand, "", 48),
        subtitle: text(raw.visual?.sidebar?.subtitle, "", 80),
        footerText: text(raw.visual?.sidebar?.footerText, "翔仔正在工作ing", 48),
      },
      cards: visualCards,
      note: {
        title: text(raw.visual?.note?.title, "", 48),
        lines: visualNoteLines,
      },
      chrome: {
        sparkles: raw.visual?.chrome?.sparkles === true,
        ribbon: raw.visual?.chrome?.ribbon === true,
        polaroid: raw.visual?.chrome?.polaroid === true,
      },
    },
  };
  let imagePath = null;
  let imageStat = null;
  if (theme.image) {
    imagePath = path.join(assetsRoot, theme.image);
    imageStat = await fs.stat(imagePath);
    if (!imageStat.isFile() || imageStat.size < 1 || imageStat.size > MAX_ART_BYTES) {
      throw new Error(`Theme image must be a non-empty file no larger than ${MAX_ART_BYTES} bytes`);
    }
    const extension = path.extname(theme.image).toLowerCase();
    if (![".png", ".jpg", ".jpeg", ".webp"].includes(extension)) {
      throw new Error(`Unsupported theme image format: ${extension || "missing"}`);
    }
  }
  return { assetsRoot, imagePath, imageStat, theme };
}

async function loadPayload(themeDir) {
  const loaded = await loadTheme(themeDir);
  const stylesheetByProfile = {
    "inspiration-universe": "dream-skin.css",
    qq2007: "qq2007.css",
  };
  const stylesheet = stylesheetByProfile[loaded.theme.profile];
  if (!stylesheet) throw new Error(`Unsupported trusted theme profile: ${loaded.theme.profile}`);
  const [css, template] = await Promise.all([
    fs.readFile(path.join(root, "assets", stylesheet), "utf8"),
    fs.readFile(path.join(root, "assets", "renderer-inject.js"), "utf8"),
  ]);
  const { imagePath, theme } = loaded;
  const art = imagePath ? await fs.readFile(imagePath) : Buffer.alloc(0);
  const extension = imagePath ? path.extname(imagePath).toLowerCase() : "";
  const mime = extension === ".jpg" || extension === ".jpeg" ? "image/jpeg"
    : extension === ".webp" ? "image/webp" : "image/png";
  const artDataUrl = imagePath ? `data:${mime};base64,${art.toString("base64")}` : "";
  const payload = template
    .replace("__DREAM_SKIN_CSS_JSON__", JSON.stringify(css))
    .replace("__DREAM_SKIN_ART_JSON__", JSON.stringify(artDataUrl))
    .replace("__DREAM_SKIN_THEME_JSON__", JSON.stringify(theme))
    .replace("__DREAM_SKIN_VERSION_JSON__", JSON.stringify(SKIN_VERSION));
  return { imageBytes: art.length, payload, theme };
}

async function applyToSession(session, payload) {
  return session.evaluate(payload);
}

async function removeFromSession(session) {
  return session.evaluate(`(() => {
    window.__CODEX_DREAM_SKIN_DISABLED__ = true;
    const state = window.__CODEX_DREAM_SKIN_STATE__;
    if (state?.cleanup) return state.cleanup();
    const root = document.documentElement;
    root?.classList.remove('codex-dream-skin');
    root?.removeAttribute('data-dream-theme');
    root?.removeAttribute('data-dream-theme-id');
    root?.removeAttribute('data-dream-palette');
    root?.removeAttribute('data-dream-shell');
    root?.style.removeProperty('--dream-skin-art');
    for (const name of [...(root?.style || [])]) {
      if (name.startsWith('--ds-') || name.startsWith('--qq-') || name.startsWith('--dream-skin-')) {
        root.style.removeProperty(name);
      }
    }
    document.querySelectorAll('.dream-skin-home').forEach((node) => node.classList.remove('dream-skin-home'));
    document.querySelectorAll('.dream-skin-home-shell').forEach((node) => node.classList.remove('dream-skin-home-shell'));
    document.getElementById('codex-dream-skin-style')?.remove();
    document.getElementById('codex-dream-skin-chrome')?.remove();
    document.getElementById('dream-skin-extra-card')?.remove();
    delete window.__CODEX_DREAM_SKIN_STATE__;
    return true;
  })()`);
}

async function verifyRemovedSession(session) {
  return session.evaluate(`(() =>
    !document.documentElement.classList.contains('codex-dream-skin') &&
    !document.documentElement.hasAttribute('data-dream-theme') &&
    !document.documentElement.hasAttribute('data-dream-theme-id') &&
    !document.documentElement.hasAttribute('data-dream-palette') &&
    !document.documentElement.hasAttribute('data-dream-shell') &&
    !document.getElementById('codex-dream-skin-style') &&
    !document.getElementById('codex-dream-skin-chrome') &&
    !window.__CODEX_DREAM_SKIN_STATE__
  )()`);
}

async function verifySession(session) {
  return session.evaluate(`(() => {
    const box = (node) => {
      if (!node) return null;
      const r = node.getBoundingClientRect();
      const style = getComputedStyle(node);
      let effectiveOpacity = 1;
      for (let current = node; current && current.nodeType === 1; current = current.parentElement) {
        const opacity = Number.parseFloat(getComputedStyle(current).opacity);
        if (Number.isFinite(opacity)) effectiveOpacity *= opacity;
      }
      return {
        x: Math.round(r.x), y: Math.round(r.y),
        width: Math.round(r.width), height: Math.round(r.height),
        display: style.display,
        visibility: style.visibility,
        opacity: Number.parseFloat(style.opacity) || 0,
        effectiveOpacity: Math.round(effectiveOpacity * 1000) / 1000,
        color: style.color,
        backgroundColor: style.backgroundColor,
        backgroundImage: style.backgroundImage === 'none' ? 'none' : 'present',
        visible: r.width > 0 && r.height > 0 && style.display !== 'none' && style.visibility !== 'hidden' && effectiveOpacity > 0.05,
      };
    };
    const homeIndicator = document.querySelector('[data-testid="home-icon"]');
    const homeSignal = homeIndicator ?? document.querySelector('[data-feature="game-source"]');
    const homeRoute = homeSignal?.closest('[role="main"]') ?? null;
    const home = document.querySelector('[role="main"].dream-skin-home');
    const suggestions = home?.querySelector('[class~="group/home-suggestions"]') ?? null;
    const suggestionsBox = box(suggestions);
    const cardBoxes = suggestions ? [...suggestions.querySelectorAll('button')].map(box) : [];
    const visibleCards = cardBoxes.filter((item) => item?.visible);
    const hero = box(home?.firstElementChild?.firstElementChild?.firstElementChild);
    const projectButton = box(home?.querySelector('[class~="group/project-selector"] > button'));
    const composer = box(document.querySelector('.composer-surface-chrome'));
    const sidebar = box(document.querySelector('aside.app-shell-left-panel'));
    const chrome = document.getElementById('codex-dream-skin-chrome');
    const profile = document.documentElement.getAttribute('data-dream-theme');
    const dragRegion = profile === 'qq2007'
      ? document.querySelector('.qq2007-titlebar')
      : document.querySelector('main.main-surface > header.app-header-tint');
    const windowControls = [...document.querySelectorAll('.qq2007-window-buttons > i')];
    const rootStyle = getComputedStyle(document.documentElement);
    const themeId = document.documentElement.getAttribute('data-dream-theme-id');
    const cardBottom = visibleCards.length
      ? Math.max(...visibleCards.map((item) => item.y + item.height))
      : null;
    const cardComposerGap = cardBottom === null || !composer ? null : composer.y - cardBottom;
    const cardProjectGap = cardBottom === null || !projectButton ? null : projectButton.y - cardBottom;
    const projectComposerGap = !projectButton || !composer
      ? null
      : composer.y - (projectButton.y + projectButton.height);
    const trailingWhitespaceRatio = composer
      ? Math.max(0, innerHeight - (composer.y + composer.height)) / innerHeight
      : null;
    const qqCanvas = profile === 'qq2007' ? {
      left: Number.parseFloat(rootStyle.getPropertyValue('--qq-canvas-left')) || 0,
      width: Number.parseFloat(rootStyle.getPropertyValue('--qq-canvas-width')) || innerWidth,
      height: Number.parseFloat(rootStyle.getPropertyValue('--qq-canvas-height')) || innerHeight,
      sidebarWidth: Number.parseFloat(rootStyle.getPropertyValue('--qq-left')) || 0,
      gutter: Number.parseFloat(rootStyle.getPropertyValue('--qq-gutter')) || 0,
      buddy: box(document.querySelector('.qq2007-buddy-panel')),
      main: box(document.querySelector('main.main-surface')),
    } : null;
    const result = {
      installed: document.documentElement.classList.contains('codex-dream-skin'),
      version: window.__CODEX_DREAM_SKIN_STATE__?.version ?? null,
      stylePresent: Boolean(document.getElementById('codex-dream-skin-style')),
      chromePresent: Boolean(chrome),
      chromePointerEvents: getComputedStyle(chrome || document.body).pointerEvents,
      profile,
      themeId,
      dragRegionAppRegion: dragRegion ? getComputedStyle(dragRegion).webkitAppRegion : null,
      windowControlCount: windowControls.length,
      qqCanvas,
      homeRoute: Boolean(homeRoute),
      homePresent: Boolean(home),
      suggestions: suggestionsBox,
      hero,
      cards: cardBoxes,
      visibleCardCount: visibleCards.length,
      projectButton,
      composer,
      sidebar,
      viewport: { width: innerWidth, height: innerHeight },
      documentOverflow: {
        x: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        y: document.documentElement.scrollHeight > document.documentElement.clientHeight,
      },
      cardComposerGap,
      cardProjectGap,
      projectComposerGap,
      trailingWhitespaceRatio,
    };
    const basePass = result.installed && result.version === ${JSON.stringify(SKIN_VERSION)} &&
      result.stylePresent && result.chromePresent && result.chromePointerEvents === 'none' &&
      result.dragRegionAppRegion === 'drag' &&
      (result.profile !== 'qq2007' || result.windowControlCount === 3) &&
      Boolean(result.composer?.visible) && !result.documentOverflow.x;
    const qqResponsivePass = result.profile !== 'qq2007' || (
      result.qqCanvas && result.qqCanvas.width <= innerWidth + 1 && result.qqCanvas.height <= innerHeight + 1 &&
      Math.abs((result.qqCanvas.width / result.qqCanvas.height) - (4 / 3)) < 0.02 &&
      (!result.sidebar || result.sidebar.x >= result.qqCanvas.left) &&
      result.qqCanvas.main?.visible && result.qqCanvas.buddy?.visible &&
      result.qqCanvas.main.x + result.qqCanvas.main.width <= result.qqCanvas.left + result.qqCanvas.width + 1
    );
    const qqSidebarWidthSynced = result.profile !== 'qq2007' || !result.sidebar?.visible ||
      Math.abs(result.qqCanvas.sidebarWidth - result.sidebar.width) <= 2;
    const qqSidebarGapSynced = result.profile !== 'qq2007' || !result.sidebar?.visible ||
      Math.abs(result.qqCanvas.main.x - (result.sidebar.x + result.sidebar.width) - result.qqCanvas.gutter) <= 2;
    // Project selector markup varies across Codex builds — soft requirement.
    const qqSuggestionsPass = !result.suggestions || (result.suggestions.visible &&
      result.visibleCardCount >= 1 && result.visibleCardCount <= 6 &&
      result.suggestions.y + result.suggestions.height <= result.composer.y + 2);
    const galleryFlowPass = !result.themeId?.startsWith('skin-') || !result.homeRoute || (
      Number.isFinite(result.cardProjectGap) && result.cardProjectGap >= 8 && result.cardProjectGap <= 72 &&
      Number.isFinite(result.projectComposerGap) && result.projectComposerGap >= 6 && result.projectComposerGap <= 20 &&
      Number.isFinite(result.trailingWhitespaceRatio) && result.trailingWhitespaceRatio <= 0.12 &&
      result.composer.height <= 132 &&
      result.projectButton?.visible &&
      result.projectButton.y + result.projectButton.height <= result.composer.y - 6 &&
      !result.documentOverflow.y &&
      result.composer.y + result.composer.height <= result.viewport.height + 2
    );
    const homePass = !result.homeRoute || (result.profile === 'qq2007'
      ? result.homePresent && result.qqCanvas?.main?.visible && qqSuggestionsPass &&
        result.composer?.visible &&
        result.composer.y + result.composer.height <= result.qqCanvas.main.y + result.qqCanvas.main.height + 2
      : result.homePresent && result.hero?.visible && result.hero.width >= 280 && result.hero.height >= 120 &&
        result.visibleCardCount >= 1 && result.visibleCardCount <= 6 && galleryFlowPass);
    result.pass = Boolean(basePass && homePass && qqResponsivePass && qqSidebarWidthSynced && qqSidebarGapSynced);
    result.softNotes = {
      projectButtonOptional: !result.projectButton?.visible,
      sidebarOptional: !result.sidebar?.visible,
      qqResponsivePass,
      qqSidebarWidthSynced,
      qqSidebarGapSynced,
      galleryFlowPass,
    };
    return result;
  })()`);
}

async function waitForVerifiedSession(session, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastResult;
  while (Date.now() < deadline) {
    lastResult = await verifySession(session);
    if (lastResult.pass) return lastResult;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return lastResult;
}

async function capture(session, outputPath) {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await session.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
  await session.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
  const viewport = await session.evaluate("({ width: innerWidth, height: innerHeight })");
  await session.send("Input.dispatchMouseEvent", {
    type: "mouseMoved",
    x: Math.round(viewport.width * 0.64),
    y: Math.round(viewport.height * 0.62),
    button: "none",
  });
  await new Promise((resolve) => setTimeout(resolve, 300));
  const result = await session.send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false,
  });
  await fs.writeFile(outputPath, Buffer.from(result.data, "base64"));
}

async function runOneShot(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs);
  const loaded = (options.mode === "once" || options.reload) ? await loadPayload(options.themeDir) : null;
  const payload = loaded?.payload ?? null;
  const results = [];
  let screenshotCaptured = false;

  for (const { target, session, probe } of connected) {
    try {
      if (options.mode === "remove") await removeFromSession(session);
      else if (options.mode === "once") await applyToSession(session, payload);

      if (options.reload) {
        await session.send("Page.reload", { ignoreCache: true });
        await new Promise((resolve) => setTimeout(resolve, 1600));
        if (options.mode !== "remove") await applyToSession(session, payload);
      }

      const result = options.mode === "remove"
        ? await verifyRemovedSession(session)
        : await waitForVerifiedSession(session, options.timeoutMs);
      results.push({ targetId: target.id, title: target.title, url: target.url, probe, result });

      if (options.screenshot && !screenshotCaptured) {
        await capture(session, options.screenshot);
        screenshotCaptured = true;
      }
    } finally {
      session.close();
    }
  }

  console.log(JSON.stringify({ mode: options.mode, version: SKIN_VERSION, port: options.port, targets: results }, null, 2));
  const failed = results.length === 0 || results.some((item) => options.mode === "remove" ? item.result !== true : !item.result?.pass);
  if (failed) process.exitCode = 2;
}

async function runWindowSmoke(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs);
  const results = [];
  for (const { target, session } of connected) {
    try {
      const result = await session.evaluate(`(() => ({
        dragRegion: getComputedStyle(document.querySelector('.qq2007-titlebar')).webkitAppRegion,
        syntheticWindowButtons: document.querySelectorAll('[data-dream-window-action]').length,
        decorativeWindowButtons: document.querySelectorAll('.qq2007-window-buttons > i').length
      }))()`);
      const pass = result.dragRegion === 'drag' && result.syntheticWindowButtons === 0 && result.decorativeWindowButtons === 3;
      results.push({ targetId: target.id, ...result, nativeWindowControlsRequired: true, pass });
    } finally {
      session.close();
    }
  }
  console.log(JSON.stringify({ mode: "window-smoke", version: SKIN_VERSION, port: options.port, targets: results }, null, 2));
  if (results.length === 0 || results.some((result) => !result.pass)) process.exitCode = 2;
}

async function runWatch(options) {
  const { payload } = await loadPayload(options.themeDir);
  const sessions = new Map();
  const rejected = new Set();
  let stopping = false;
  const stop = () => { stopping = true; };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);

  while (!stopping) {
    let targets = [];
    try {
      targets = await listAppTargets(options.port);
    } catch (error) {
      console.error(`[dream-skin] ${new Date().toISOString()} ${error.message}`);
      await new Promise((resolve) => setTimeout(resolve, 1000));
      continue;
    }

    const activeIds = new Set(targets.map((target) => target.id));
    for (const [id, session] of sessions) {
      if (!activeIds.has(id) || session.closed) {
        session.close();
        sessions.delete(id);
      }
    }

    for (const target of targets) {
      if (sessions.has(target.id)) continue;
      let session;
      try {
        session = await connectTarget(target, options.port);
        const probe = await probeSession(session);
        if (!probe?.codex) {
          session.close();
          if (!rejected.has(target.id)) {
            // A shared Chromium debug port may expose utility/devtools pages.
            // Ignoring those is expected and must not dirty the error log.
            console.log(`[dream-skin] ignored non-Codex app target ${target.id}`);
            rejected.add(target.id);
          }
          continue;
        }
        rejected.delete(target.id);
        session.on("Page.loadEventFired", () => {
          setTimeout(() => applyToSession(session, payload).catch((error) => {
            console.error(`[dream-skin] reinject failed: ${error.message}`);
          }), 250);
        });
        await applyToSession(session, payload);
        sessions.set(target.id, session);
        console.log(`[dream-skin] injected verified Codex target ${target.id} (${target.title || target.url})`);
      } catch (error) {
        session?.close();
        console.error(`[dream-skin] inject failed for ${target.id}: ${error.message}`);
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 900));
  }

  for (const session of sessions.values()) session.close();
}

try {
  const options = parseArgs(process.argv.slice(2));
  if (options.mode === "check") {
    const loaded = await loadPayload(options.themeDir);
    console.log(JSON.stringify({
      pass: true,
      version: SKIN_VERSION,
      themeId: loaded.theme.id,
      themeName: loaded.theme.name,
      profile: loaded.theme.profile,
      appearance: loaded.theme.appearance,
      art: loaded.theme.art,
      visual: loaded.theme.visual,
      imageBytes: loaded.imageBytes,
      payloadBytes: Buffer.byteLength(loaded.payload),
    }, null, 2));
  } else if (options.mode === "watch") await runWatch(options);
  else if (options.mode === "window-smoke") await runWindowSmoke(options);
  else await runOneShot(options);
} catch (error) {
  console.error(`[dream-skin] ${error.stack || error.message}`);
  process.exitCode = 1;
}
