#!/usr/bin/env node
/**
 * ChatGPT 外链路由器
 * --------------------------------------------
 * 作用：
 * 1) 连接已经打开 CDP 调试端口的 Chrome；
 * 2) 监听 Chrome 新建的 page target；
 * 3) 只处理“opener 是 ChatGPT 页面”的新页面；
 * 4) 如果新页面 URL 是非 chatgpt.com 的 http/https 外链，就交给 Firefox 打开；
 * 5) Firefox 打开成功后，关闭 Chrome 里那个新 target，避免 app 模式下出现找不到的窗口/标签。
 *
 * 为什么不写成 Chrome 扩展：
 * - 扩展可以更细，但要安装扩展、声明权限、再接 native messaging；
 * - 这里优先做一个可以被 AHK 托盘菜单启动/停止的轻量脚本，便于调试和回滚。
 *
 * 为什么必须通过 openerId 限定：
 * - 同一个 Chrome-CDP profile 里可能还有普通 Chrome 窗口；
 * - 如果看到“非 ChatGPT URL”就关闭，会误伤正常浏览；
 * - openerId 能把“ChatGPT 浮窗点出来的新页”和“用户自己打开的新页”区分开。
 */

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

const DEFAULT_BROWSER_URL = "http://127.0.0.1:9222";
const DEFAULT_CHATGPT_ORIGIN = "https://chatgpt.com";
const DEFAULT_FIREFOX_PATHS = [
  "C:\\Program Files\\Mozilla Firefox\\firefox.exe",
  "C:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe",
  "firefox.exe",
];

/**
 * 把 `--key=value` 风格参数解析成 Map。
 * @param {string[]} argv Node 传入的命令行参数，不包含 node 和脚本路径。
 * @returns {Map<string, string>} 参数名到参数值的映射。
 */
function parseArgs(argv) {
  const args = new Map();

  for (const rawArg of argv) {
    if (!rawArg.startsWith("--")) {
      continue;
    }

    const equalIndex = rawArg.indexOf("=");
    if (equalIndex === -1) {
      args.set(rawArg.slice(2), "1");
      continue;
    }

    const key = rawArg.slice(2, equalIndex);
    const value = rawArg.slice(equalIndex + 1);
    args.set(key, value);
  }

  return args;
}

/**
 * 移除 URL 末尾的 `/`，用于稳定比较 origin。
 * @param {string} value 原始 URL 字符串。
 * @returns {string} 归一化后的 URL 字符串。
 */
function trimTrailingSlash(value) {
  return value.replace(/\/+$/u, "");
}

/**
 * 判断一个 URL 是否属于 ChatGPT 站点。
 * @param {string} urlText CDP targetInfo.url。
 * @param {string} chatgptOrigin ChatGPT origin，例如 https://chatgpt.com。
 * @returns {boolean} true 表示是 ChatGPT 自己的页面。
 */
function isChatGptUrl(urlText, chatgptOrigin) {
  try {
    const url = new URL(urlText);
    const origin = trimTrailingSlash(chatgptOrigin);
    return url.origin === origin || url.hostname === "chatgpt.com";
  } catch {
    return false;
  }
}

/**
 * 判断一个 URL 是否是适合转给浏览器打开的普通网页。
 * @param {string} urlText CDP targetInfo.url。
 * @returns {boolean} true 表示是 http/https URL。
 */
function isHttpUrl(urlText) {
  try {
    const url = new URL(urlText);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

/**
 * 解析 Firefox 可执行文件路径。
 * @param {string | undefined} configuredPath 配置文件传入的 Firefox 路径。
 * @returns {string} 可传给 spawn 的命令。
 */
function resolveFirefoxPath(configuredPath) {
  if (configuredPath && configuredPath.trim() !== "") {
    return configuredPath.trim();
  }

  for (const candidate of DEFAULT_FIREFOX_PATHS) {
    if (candidate === "firefox.exe" || existsSync(candidate)) {
      return candidate;
    }
  }

  return "firefox.exe";
}

/**
 * 让 Firefox 打开目标 URL。
 * @param {string} firefoxPath Firefox 可执行文件路径。
 * @param {string} url 要打开的网页地址。
 */
function openInFirefox(firefoxPath, url) {
  const child = spawn(firefoxPath, [url], {
    detached: true,
    stdio: "ignore",
    windowsHide: false,
  });

  child.unref();
}

/**
 * 请求 Chrome `/json/version`，拿到 browser websocket 地址。
 * @param {string} browserUrl 例如 http://127.0.0.1:9222。
 * @returns {Promise<string>} browser 级 CDP websocket URL。
 */
async function fetchBrowserWebSocketUrl(browserUrl) {
  const response = await fetch(`${trimTrailingSlash(browserUrl)}/json/version`);
  if (!response.ok) {
    throw new Error(`读取 /json/version 失败：HTTP ${response.status}`);
  }

  const payload = await response.json();
  if (!payload.webSocketDebuggerUrl) {
    throw new Error("/json/version 没有返回 webSocketDebuggerUrl");
  }

  return payload.webSocketDebuggerUrl;
}

/**
 * 创建一个带自增 id 的 CDP 发送函数。
 * @param {WebSocket} ws browser websocket。
 * @returns {(method: string, params?: object) => void} CDP 发送函数。
 */
function createCdpSender(ws) {
  let nextId = 1;

  return (method, params = {}) => {
    ws.send(JSON.stringify({
      id: nextId,
      method,
      params,
    }));
    nextId += 1;
  };
}

/**
 * 根据 targetInfo 更新 ChatGPT target 集合，并在必要时执行外链转发。
 * @param {object} context 运行状态。
 * @param {object} targetInfo CDP Target.targetInfo。
 */
function handleTargetInfo(context, targetInfo) {
  if (!targetInfo || targetInfo.type !== "page") {
    return;
  }

  const targetId = targetInfo.targetId;
  const openerId = targetInfo.openerId || context.pendingOpeners.get(targetId) || "";
  const url = targetInfo.url || "";

  if (openerId) {
    context.pendingOpeners.set(targetId, openerId);
  }

  if (isChatGptUrl(url, context.chatgptOrigin)) {
    context.chatgptTargets.add(targetId);
    return;
  }

  if (!openerId || !context.chatgptTargets.has(openerId)) {
    return;
  }
  if (!isHttpUrl(url)) {
    return;
  }
  if (context.routedTargets.has(targetId)) {
    return;
  }

  context.routedTargets.add(targetId);
  openInFirefox(context.firefoxPath, url);
  context.send("Target.closeTarget", { targetId });
  console.log(`[router] 已转发到 Firefox：${url}`);
}

/**
 * 主流程：连接 Chrome browser websocket 并订阅 target 事件。
 */
async function main() {
  const args = parseArgs(process.argv.slice(2));
  const browserUrl = args.get("browser-url") || DEFAULT_BROWSER_URL;
  const chatgptOrigin = args.get("chatgpt-origin") || DEFAULT_CHATGPT_ORIGIN;
  const firefoxPath = resolveFirefoxPath(args.get("firefox-path"));
  const browserWebSocketUrl = await fetchBrowserWebSocketUrl(browserUrl);
  const ws = new WebSocket(browserWebSocketUrl);

  const context = {
    chatgptOrigin,
    firefoxPath,
    chatgptTargets: new Set(),
    pendingOpeners: new Map(),
    routedTargets: new Set(),
    send: null,
  };

  ws.addEventListener("open", () => {
    context.send = createCdpSender(ws);
    context.send("Target.setDiscoverTargets", { discover: true });
    context.send("Target.getTargets");
    console.log(`[router] 已连接 Chrome CDP：${browserUrl}`);
    console.log(`[router] Firefox 路径：${firefoxPath}`);
  });

  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);

    if (message.id && Array.isArray(message.result?.targetInfos)) {
      for (const targetInfo of message.result.targetInfos) {
        handleTargetInfo(context, targetInfo);
      }
      return;
    }

    if (message.method === "Target.targetCreated" || message.method === "Target.targetInfoChanged") {
      handleTargetInfo(context, message.params?.targetInfo);
    }
  });

  ws.addEventListener("close", () => {
    console.log("[router] Chrome CDP 连接已关闭。");
    process.exit(0);
  });

  ws.addEventListener("error", (error) => {
    console.error("[router] WebSocket 错误：", error.message || error);
    process.exit(1);
  });
}

main().catch((error) => {
  console.error(`[router] 启动失败：${error.message}`);
  process.exit(1);
});
