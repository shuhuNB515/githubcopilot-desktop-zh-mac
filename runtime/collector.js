// 采集页面上的可见文案，用于构建词典
(function () {
  if (window.__cnCollector) return;
  var seen = {};
  function push(s) {
    s = (s || '').replace(/\s+/g, ' ').trim();
    if (!s || s.length > 400) return;
    seen[s] = (seen[s] || 0) + 1;
  }
  function scan(root) {
    try {
      var it = document.createTreeWalker(root || document.body || document.documentElement,
        NodeFilter.SHOW_TEXT, null);
      var n;
      while ((n = it.nextNode())) {
        var p = n.parentElement; if (!p) continue;
        var tag = p.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') continue;
        push(n.nodeValue);
      }
      document.querySelectorAll('[placeholder],[title],[aria-label],[alt]').forEach(function (el) {
        ['placeholder', 'title', 'aria-label', 'alt'].forEach(function (a) {
          if (el.hasAttribute(a)) push(el.getAttribute(a));
        });
      });
    } catch (e) {}
  }
  function dump(tag) {
    scan();
    var arr = Object.keys(seen);
    try {
      window.webkit.messageHandlers.copilotcn.postMessage({
        kind: 'dump', tag: tag || 'x',
        data: JSON.stringify({ url: location.href, count: arr.length, strings: arr })
      });
    } catch (e) {}
    return arr.length;
  }
  window.__cnDump = dump;
  window.__cnScan = scan;
  window.__cnCollector = true;
  [1500, 5000, 12000].forEach(function (t) { setTimeout(function () { dump('t' + t); }, t); });
  var timer = null;
  try {
    new MutationObserver(function () {
      clearTimeout(timer); timer = setTimeout(function () { dump('mut'); }, 2500);
    }).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
  } catch (e) {}
})();
