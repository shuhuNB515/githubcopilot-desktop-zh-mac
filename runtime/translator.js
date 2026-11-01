// CopilotCN 翻译引擎：把页面里的英文 UI 文案替换为中文
(function () {
  if (window.__cnTranslatorInstalled) return;
  window.__cnTranslatorInstalled = true;

  var DICT = window.__CN_DICT || {};
  var CN_RE = /[\u3400-\u9fff\uff00-\uffef]/;
  var SKIP_TAGS = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, PRE: 1, CODE: 1, KBD: 1, SAMP: 1, TEXTAREA: 1, CANVAS: 1, SVG: 1 };
  var ATTRS = ['title', 'placeholder', 'aria-label', 'aria-description', 'alt', 'aria-valuetext'];
  var stats = { text: 0, attr: 0 };
  var busy = false;
  var TEXT_ORIG = window.__CN_TEXT_ORIG || (window.__CN_TEXT_ORIG = new WeakMap());
  var ATTR_ORIG = window.__CN_ATTR_ORIG || (window.__CN_ATTR_ORIG = new WeakMap());

  var KEYS = {
    'Command': '\u2318', 'Cmd': '\u2318', 'Control': '\u2303', 'Ctrl': '\u2303',
    'Option': '\u2325', 'Alt': '\u2325', 'Shift': '\u21e7',
    'Left Arrow': '\u2190', 'Right Arrow': '\u2192', 'Up Arrow': '\u2191', 'Down Arrow': '\u2193',
    'Return': '\u21a9', 'Enter': '\u21a9', 'Space': '空格', 'Tab': '\u21e5',
    'Comma': ',', 'Period': '.', 'Backslash': '\\', 'Backtick': '\u0060', 'Grave': '\u0060',
    'Apostrophe': "'", 'Semicolon': ';', 'Slash': '/', 'Minus': '-', 'Plus': '+', 'Equal': '=',
    'Question mark': '?', 'Left bracket': '[', 'Right bracket': ']', 'Escape': 'Esc',
    'Delete': '\u232b', 'Backspace': '\u232b', 'Percent': '%'
  };
  var MODS = { 'Command': 1, 'Cmd': 1, 'Control': 1, 'Ctrl': 1, 'Option': 1, 'Alt': 1, 'Shift': 1 };

  function isCombo(s) {
    if (s.indexOf(' + ') < 0) return false;
    var parts = s.split(' + ');
    if (parts.length < 2) return false;
    if (!MODS[parts[0].trim()]) return false;
    for (var i = 1; i < parts.length; i++) {
      var p = parts[i].trim();
      if (!p) return false;
      if (KEYS[p]) continue;
      if (p.length > 3) return false;
    }
    return true;
  }

  function combo(s) {
    var parts = s.split(' + ').map(function (p) { return p.trim(); });
    return parts.map(function (p) { return KEYS[p] || p; }).join('');
  }

  var MONTHS = { January: 1, February: 2, March: 3, April: 4, May: 5, June: 6, July: 7, August: 8, September: 9, October: 10, November: 11, December: 12 };

  function fmtDate(s) {
    var m = s.match(/^([A-Z][a-z]+) (\d{1,2}), (\d{4}),? at (\d{1,2}):(\d{2}) (AM|PM)$/);
    if (!m || !MONTHS[m[1]]) return null;
    var h = parseInt(m[4], 10);
    if (m[6] === 'PM' && h < 12) h += 12;
    if (m[6] === 'AM' && h === 12) h = 0;
    return m[3] + '年' + MONTHS[m[1]] + '月' + m[2] + '日 ' + (h < 10 ? '0' + h : h) + ':' + m[5];
  }

  function trLabel(s) { return DICT[s] || null; }

  function splitLastComma(s) {
    var i = s.lastIndexOf(', ');
    if (i < 0) return null;
    var left = s.slice(0, i), right = s.slice(i + 2);
    var lt = DICT[left], rt = DICT[right] || DICT[right.toLowerCase()];
    if (lt && rt) return lt + '\uff0c' + rt;
    if (lt && isCombo(right)) return lt + ' (' + combo(right) + ')';
    return null;
  }

  var RULES = [
    function (s) {
      var m = s.match(/^(.+?), ((?:Command|Control|Option|Shift)[^.]*)\. (.+?), ((?:Command|Control|Option|Shift)[^.]*)\.$/);
      if (m && isCombo(m[2]) && isCombo(m[4])) {
        var a = trLabel(m[1]) || m[1], b = trLabel(m[3]) || m[3];
        return a + ' ' + combo(m[2]) + '\uff0c' + b + ' ' + combo(m[4]) + '。';
      }
      return null;
    },
    function (s) {
      var m = s.match(/^Edit shortcut for (.+)$/);
      if (m) return '编辑「' + (trLabel(m[1]) || m[1]) + '」的快捷键';
      return null;
    },
    function (s) {
      var m = s.match(/^Assign shortcut for (.+)$/);
      if (m) return '为「' + (trLabel(m[1]) || m[1]) + '」分配快捷键';
      return null;
    },
    function (s) {
      var m = s.match(/^(.+?), edit shortcut for (.+)$/);
      if (m && isCombo(m[1])) return combo(m[1]) + '\uff0c编辑「' + (trLabel(m[2]) || m[2]) + '」的快捷键';
      return null;
    },
    function (s) {
      var m = s.match(/^(.+?), ((?:Command|Control|Option|Shift|Alt|Cmd|Ctrl)[^,]*)$/);
      if (m && isCombo(m[2])) {
        var base = trLabel(m[1]) || splitLastComma(m[1]);
        if (base) return base + ' (' + combo(m[2]) + ')';
      }
      return null;
    },
    function (s) {
      var m = s.match(/^(.+), edit voice dictation shortcut$/);
      if (m && isCombo(m[1])) return combo(m[1]) + '\uff0c编辑语音听写快捷键';
      return null;
    },
    function (s) {
      var m = s.match(/^Not installed \u00b7 (.+)$/);
      if (m) return '未安装 \u00b7 ' + m[1];
      return null;
    },
    function (s) {
      var m = s.match(/^Download (.+)$/);
      if (m) return '下载 ' + m[1];
      return null;
    },
    function (s) {
      var m = s.match(/^Up to date\. Last checked on (.+)\.?$/);
      if (m) { var d = fmtDate(m[1].replace(/\.$/, '')); return '已是最新版本。上次检查：' + (d || m[1]) + '。'; }
      return null;
    },
    function (s) {
      var m = s.match(/^(\d+)% quota used$/);
      if (m) return '已用配额 ' + m[1] + '%';
      return null;
    },
    function (s) {
      var m = s.match(/^Search (\d+) palettes\u2026$/);
      if (m) return '搜索 ' + m[1] + ' 个调色板\u2026';
      return null;
    },
    function (s) {
      var m = s.match(/^(\d+) seconds?$/);
      if (m) return m[1] + ' 秒';
      return null;
    },
    function (s) {
      var m = s.match(/^Testing connection, (.+)$/);
      if (m) return '正在测试连接，' + (trLabel(m[1]) || m[1]);
      return null;
    },
    function (s) {
      var m = s.match(/^(.+), (.)$/);
      if (m && '&@#/!'.indexOf(m[2]) >= 0) { var t = trLabel(m[1]); if (t) return t + '\uff08' + m[2] + '\uff09'; }
      return null;
    },
    function (s) {
      var m = s.match(/^(.+) announcements$/);
      if (m) { var t = trLabel(m[1]); if (t) return t + '播报'; }
      return null;
    },
    function (s) {
      var m = s.match(/^Mode: (.+)$/);
      if (m) return '模式：' + (trLabel(m[1]) || m[1]);
      return null;
    },
    function (s) {
      var m = s.match(/^(.+), open user menu$/);
      if (m) return (trLabel(m[1]) || m[1]) + '，打开用户菜单';
      return null;
    },
    function (s) {
      var m = s.match(/^Provided by the GitHub account (.+) on (.+)$/);
      if (m) return '由 ' + m[2] + ' 上的 GitHub 账户 ' + m[1] + ' 提供';
      return null;
    },
    function (s) {
      var m = s.match(/^(.+?), edit shortcut for (.+)$/);
      if (m && KEYS[m[1]]) return combo(m[1]) + '，编辑「' + (trLabel(m[2]) || m[2]) + '」的快捷键';
      return null;
    },
    function (s) {
      var m = s.match(/^Zoom, (\d+)%$/);
      if (m) return '缩放，' + m[1] + '%';
      return null;
    },
    function (s) {
      var m = s.match(/^Cycle agent modes with (.+)$/);
      if (m) return '循环切换智能体模式：' + (KEYS[m[1]] || m[1]);
      return null;
    },
    function (s) {
      if (isCombo(s)) return combo(s);
      return null;
    },
    function (s) { return splitLastComma(s); }
  ];

  function translate(str) {
    if (!str) return null;
    var s = str.replace(/\s+/g, ' ').trim();
    if (!s || s.length > 500) return null;
    if (DICT[s]) return DICT[s];
    if (CN_RE.test(s)) return null;
    for (var i = 0; i < RULES.length; i++) {
      var r = RULES[i](s);
      if (r) return r;
    }
    return null;
  }
  window.__cnTranslate = translate;

  function insideSkipped(el) {
    var n = el;
    while (n && n !== document.body && n.parentElement) {
      if (SKIP_TAGS[n.tagName]) return true;
      if (n.isContentEditable) return true;
      n = n.parentElement;
    }
    return false;
  }

  function doText(node) {
    var raw = node.nodeValue;
    if (!raw) return;
    var prev = TEXT_ORIG.get(node);
    if (prev && raw === prev.zh) {
      node.nodeValue = prev.en;
      raw = prev.en;
    }
    var t = translate(raw);
    if (!t) { if (prev) TEXT_ORIG.delete(node); return; }
    var lead = raw.match(/^\s*/)[0], trail = raw.match(/\s*$/)[0];
    node.nodeValue = lead + t + trail;
    TEXT_ORIG.set(node, { en: raw, zh: lead + t + trail });
    stats.text++;
  }

  function doAttrs(el) {
    if (!el.getAttribute) return;
    if (insideSkipped(el)) return;
    var rec = ATTR_ORIG.get(el) || {};
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i];
      var v = el.getAttribute(a);
      if (!v) continue;
      var p = rec[a];
      if (p && v === p.zh) { el.setAttribute(a, p.en); v = p.en; }
      var t = translate(v);
      if (t) { el.setAttribute(a, t); rec[a] = { en: v, zh: t }; stats.attr++; }
      else if (p) delete rec[a];
    }
    ATTR_ORIG.set(el, rec);
  }

  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) {
      var pp = root.parentElement;
      if (pp && !SKIP_TAGS[pp.tagName] && !pp.isContentEditable) doText(root);
      return;
    }
    if (root.nodeType !== 1) return;
    if (SKIP_TAGS[root.tagName] || root.isContentEditable) return;
    doAttrs(root);
    var tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, null);
    var n;
    while ((n = tw.nextNode())) {
      if (n.nodeType === 3) {
        var p = n.parentElement;
        if (p && !SKIP_TAGS[p.tagName] && !p.isContentEditable) doText(n);
      } else if (n.nodeType === 1) {
        doAttrs(n);
      }
    }
  }

  var pending = [];
  var scheduled = false;
  function flush() {
    scheduled = false;
    if (busy) { schedule(); return; }
    busy = true;
    var list = pending; pending = [];
    try { for (var i = 0; i < list.length; i++) walk(list[i]); } catch (e) {}
    setTimeout(function () { busy = false; }, 0);
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(flush, 60);
  }

  function start() {
    if (window.__cnReload) { try { window.__cnReload(); } catch (e) {} }
    try { document.documentElement.lang = 'zh-CN'; } catch (e) {}
    try { walk(document.body); } catch (e) {}
    try {
      var mo = new MutationObserver(function (records) {
        if (busy) return;
        for (var i = 0; i < records.length; i++) {
          var r = records[i];
          if (r.type === 'characterData') pending.push(r.target);
          else if (r.type === 'childList') {
            for (var j = 0; j < r.addedNodes.length; j++) {
              var n = r.addedNodes[j];
              if (n.nodeType === 3) { var p = n.parentElement; if (p && !SKIP_TAGS[p.tagName]) pending.push(n); }
              else if (n.nodeType === 1 && !SKIP_TAGS[n.tagName]) pending.push(n);
            }
          } else if (r.type === 'attributes') pending.push(r.target);
        }
        if (pending.length) schedule();
      });
      mo.observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS });
      window.__cnReload = function () { try { mo.disconnect(); } catch (e) {} if (window.__cnTimer) clearInterval(window.__cnTimer); };
    } catch (e) {}
    window.__cnTimer = setInterval(function () { try { walk(document.body); } catch (e) {} }, 2500);
    try { window.webkit.messageHandlers.copilotcn.postMessage({ kind: 'log', msg: 'translator active, dict=' + Object.keys(DICT).length + ' text=' + stats.text + ' attr=' + stats.attr }); } catch (e) {}
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
