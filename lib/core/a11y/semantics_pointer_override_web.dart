import 'package:web/web.dart' as web;

bool _injected = false;

/// Globally disable pointer-events on all Flutter semantics DOM nodes.
///
/// Injects an unconditional CSS rule that forces `pointer-events: none
/// !important` on `flt-semantics-host` and all its descendants. This overrides
/// the engine's inline `pointer-events: auto/all` on individual
/// `flt-semantics` nodes, preventing them from intercepting clicks at
/// positions that may be stale after scrolling or layout changes
/// (flutter/flutter#175119, songloft-org/songloft#378).
///
/// Called once during startup on desktop Web. Screen readers use accessibility
/// APIs (not DOM pointer events) to activate elements, so this does not affect
/// assistive technology.
void injectSemanticsPointerOverride() {
  if (_injected) return;
  _injected = true;
  final style = web.document.createElement('style') as web.HTMLStyleElement;
  style.textContent =
      'flt-semantics-host,'
      'flt-semantics-host *'
      '{pointer-events:none !important}';
  web.document.head?.append(style);
}
