
import Foundation

enum FindInPageScript {
    /// mode: highlight | next | prev | clear
    static func javaScript(query: String, mode: String) -> String {
        let queryJSON = jsonString(query)
        let modeJSON = jsonString(mode)

        return """
        (function(){
          var query = \(queryJSON);
          var mode = \(modeJSON);
          var STYLE_ID = 'mm-find-style';
          var CLASS = 'mm-find-hit';
          var ACTIVE = 'mm-find-active';

          function ensureStyle(){
            if (document.getElementById(STYLE_ID)) return;
            var s = document.createElement('style');
            s.id = STYLE_ID;
            s.textContent = '.'+CLASS+'{background:#ffe58f!important;color:#000!important;border-radius:2px;padding:0 1px;}'+
              '.'+ACTIVE+'{background:#ff9f1a!important;color:#000!important;outline:2px solid #ff6b00;outline-offset:1px;}';
            (document.head || document.documentElement).appendChild(s);
          }

          function clearHighlights(){
            var marks = Array.prototype.slice.call(document.querySelectorAll('mark.'+CLASS));
            marks.forEach(function(m){
              var parent = m.parentNode;
              if (!parent) return;
              while (m.firstChild) parent.insertBefore(m.firstChild, m);
              parent.removeChild(m);
              parent.normalize();
            });
            window.__mmFind = { q: '', nodes: [], index: -1 };
          }

          function collectTextNodes(root){
            var out = [];
            if (!root) return out;
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
              acceptNode: function(node){
                if (!node.nodeValue) return NodeFilter.FILTER_REJECT;
                var p = node.parentElement;
                if (!p) return NodeFilter.FILTER_REJECT;
                var tag = (p.tagName || '').toUpperCase();
                if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'TEXTAREA' || tag === 'INPUT' || tag === 'SELECT') {
                  return NodeFilter.FILTER_REJECT;
                }
                if (p.closest && p.closest('mark.'+CLASS)) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
              }
            });
            var n;
            while ((n = walker.nextNode())) out.push(n);
            return out;
          }

          function activate(i){
            var state = window.__mmFind;
            if (!state || !state.nodes || !state.nodes.length) return '0/0';
            state.nodes.forEach(function(n){ n.classList.remove(ACTIVE); });
            var len = state.nodes.length;
            state.index = ((i % len) + len) % len;
            var cur = state.nodes[state.index];
            cur.classList.add(ACTIVE);
            try { cur.scrollIntoView({behavior:'smooth', block:'center', inline:'nearest'}); }
            catch (e) { cur.scrollIntoView(true); }
            return (state.index + 1) + '/' + len;
          }

          function highlight(q){
            ensureStyle();
            clearHighlights();
            if (!q) return '0/0';
            var qLower = q.toLowerCase();
            var textNodes = collectTextNodes(document.body);
            var hits = [];
            // Snapshot first — mutating DOM invalidates live walker results.
            textNodes.forEach(function(textNode){
              var text = textNode.nodeValue;
              if (!text) return;
              var lower = text.toLowerCase();
              if (lower.indexOf(qLower) === -1) return;
              var frag = document.createDocumentFragment();
              var last = 0;
              var idx = 0;
              while ((idx = lower.indexOf(qLower, last)) !== -1) {
                if (idx > last) frag.appendChild(document.createTextNode(text.slice(last, idx)));
                var mark = document.createElement('mark');
                mark.className = CLASS;
                mark.textContent = text.slice(idx, idx + q.length);
                frag.appendChild(mark);
                hits.push(mark);
                last = idx + q.length;
              }
              if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
              if (textNode.parentNode) textNode.parentNode.replaceChild(frag, textNode);
            });
            window.__mmFind = { q: q, nodes: hits, index: hits.length ? 0 : -1 };
            if (hits.length) return activate(0);
            return '0/0';
          }

          if (mode === 'clear') {
            clearHighlights();
            var style = document.getElementById(STYLE_ID);
            if (style && style.parentNode) style.parentNode.removeChild(style);
            return '';
          }

          var state = window.__mmFind;
          if (mode === 'next' || mode === 'prev') {
            if (!state || !state.nodes || !state.nodes.length || state.q !== query) {
              return highlight(query);
            }
            return activate(state.index + (mode === 'next' ? 1 : -1));
          }

          return highlight(query);
        })();
        """
    }

    private static func jsonString(_ value: String) -> String {
        // NSJSONSerialization requires Array/Dictionary as top-level (not bare String).
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let wrapped = String(data: data, encoding: .utf8),
              wrapped.count >= 2 else {
            return "\"\""
        }
        // ["text"] -> "text"
        return String(wrapped.dropFirst().dropLast())
    }
}
