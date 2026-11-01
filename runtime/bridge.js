// 命令通道：向原生轮询指令（JSON），在页面内执行受支持的 DOM 操作（不使用 eval，规避 CSP）
(function () {
  if (window.__cnBridge) return;
  window.__cnBridge = true;
  var api = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copilotcn;
  if (!api) return;

  function visible(el) {
    try {
      var r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return false;
      var s = getComputedStyle(el);
      return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
    } catch (e) { return false; }
  }
  function label(el) {
    return ((el.getAttribute && (el.getAttribute('aria-label') || '')) + ' ' +
            (el.getAttribute && (el.getAttribute('title') || '')) + ' ' +
            (el.textContent || '')).replace(/\s+/g, ' ').trim();
  }
  function candidates(scope) {
    var root = document;
    if (scope) { try { root = document.querySelector(scope) || document; } catch (e) {} }
    return [].slice.call(root.querySelectorAll(
      'button,a,[role="button"],[role="menuitem"],[role="tab"],[role="option"],[role="switch"],[role="checkbox"],li,span,div,label,p,h1,h2,h3'));
  }
  function find(text, opts) {
    opts = opts || {};
    var t = String(text).toLowerCase();
    var all = candidates(opts.scope);
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (opts.visibleOnly && !visible(el)) continue;
      var s = label(el).toLowerCase();
      if (s.indexOf(t) < 0) continue;
      var score = s === t ? 0 : (s.indexOf(t) === 0 ? 1 : 2) * 1000 + s.length;
      if (el.tagName === 'DIV' || el.tagName === 'SPAN') score += 5000;
      out.push({ el: el, score: score });
    }
    out.sort(function (a, b) { return a.score - b.score; });
    return out.map(function (o) { return o.el; });
  }

  var ops = {
    ping: function () { return 'pong ' + location.href; },
    click: function (a) {
      var hits = find(a.text, a);
      if (!hits.length) return 'NOT FOUND: ' + a.text;
      var el = hits[1] || hits[0];
      try { el.click(); } catch (e) { return 'CLICK ERROR: ' + e; }
      return 'CLICKED: ' + label(el).slice(0, 120);
    },
    find: function (a) {
      return find(a.text, a).slice(0, a.limit || 10).map(function (e) {
        return e.tagName + ' | ' + label(e).slice(0, 120);
      }).join('\n');
    },
    dump: function (a) { if (window.__cnDump) window.__cnDump(a.tag || 'cmd'); return 'dumped'; },
    text: function (a) { return ((document.body.innerText || '')).slice(0, a.limit || 6000); },
    html: function (a) { var el = document.querySelector(a.selector || 'body'); return el ? el.outerHTML.slice(0, a.limit || 20000) : 'null'; },
    attrs: function (a) {
      var el = document.querySelector(a.selector); if (!el) return 'null';
      return [].slice.call(el.attributes).map(function (x) { return x.name + '=' + x.value; }).join('\n');
    },
    input: function (a) {
      var el = document.querySelector(a.selector) || document.querySelector('textarea,[contenteditable="true"],input[type="text"]');
      if (!el) return 'no input';
      el.focus();
      if (el.isContentEditable) { el.textContent = a.text || ''; }
      else { el.value = a.text || ''; }
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return 'input set: ' + (a.text || '').slice(0, 60);
    },
    key: function (a) {
      var target = document.activeElement || document.body;
      var init = { bubbles: true, cancelable: true, key: a.key, code: a.code || a.key, metaKey: !!a.meta, shiftKey: !!a.shift, altKey: !!a.alt, ctrlKey: !!a.ctrl };
      target.dispatchEvent(new KeyboardEvent('keydown', init));
      target.dispatchEvent(new KeyboardEvent('keyup', init));
      return 'key sent: ' + a.key;
    },
    back: function () { history.back(); return 'back'; },
    count: function () { return String(document.querySelectorAll('*').length); }
  };

  function poll() {
    var p;
    try { p = api.postMessage({ kind: 'poll' }); } catch (e) { return; }
    if (!p || !p.then) return;
    p.then(function (cmd) {
      if (!cmd || !cmd.op) return;
      var out;
      try {
        var fn = ops[cmd.op];
        var v = fn ? fn(cmd.args || {}) : ('UNKNOWN OP: ' + cmd.op);
        out = { kind: 'cmdresult', id: cmd.id, ok: true, value: String(v) };
      } catch (e) {
        out = { kind: 'cmdresult', id: cmd.id, ok: false, value: String(e && e.message || e) };
      }
      try { api.postMessage(out); } catch (e) {}
    }).catch(function () {});
  }
  setInterval(poll, 200);
  setTimeout(poll, 80);
})();
