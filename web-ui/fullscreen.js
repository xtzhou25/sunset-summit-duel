/* v5.1 page-landscape shell. Game payload, sound and system orientation unchanged. */
(function () {
  'use strict';
  const shell = document.getElementById('game-shell');
  const frame = document.getElementById('canvas-frame');
  const canvas = document.getElementById('canvas');
  const button = document.getElementById('fullscreen-button');
  const pageButton = document.getElementById('page-landscape-button');
  const status = document.getElementById('display-status');
  let pageMode = false;
  let rotated = false;
  let revision = 0;
  let layoutKey = '';
  let layoutFrame = 0;
  let generation = 0;
  let entering = false;
  let exiting = false;
  let observedFullscreen = false;
  let entryTimer = 0;

  function fullscreenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
  }
  function isFullscreen() { return fullscreenElement() === shell; }
  function say(message) { status.textContent = message; status.title = message; }
  function cancelInput() {
    // The engine bridge releases real held contacts before their coordinate system changes.
    if (typeof canvas.__livehouseCancelInput === 'function') canvas.__livehouseCancelInput();
  }
  function focusGame() {
    if (!document.hidden) canvas.focus({ preventScroll: true });
  }
  function modeDescription() {
    if (isFullscreen()) {
      if (!pageMode) return '正常布局；当前处于系统全屏，可单独退出。';
      return rotated
        ? '页面内横屏已开启；当前另处于系统全屏，可分别退出。'
        : '页面内横屏已开启；设备已横向，系统全屏可单独退出。';
    }
    if (!pageMode) return '正常显示；可选择页面内横屏，浏览器地址栏会保留。';
    return rotated
      ? '页面内横屏已开启；这不是系统全屏，浏览器地址栏会保留。'
      : '页面内横屏已开启；设备已横向，页面无需旋转。';
  }
  function syncButtons() {
    button.textContent = isFullscreen() ? '退出系统全屏' : '系统全屏';
    button.setAttribute('aria-pressed', String(isFullscreen()));
    button.disabled = entering || exiting;
    pageButton.textContent = pageMode ? (rotated ? '返回竖屏' : '退出页面横屏') : '页面内横屏';
    pageButton.setAttribute('aria-pressed', String(pageMode));
    // The reversible page-mode control never depends on a fullscreen promise.
    pageButton.disabled = false;
  }
  function viewport() {
    const vv = window.visualViewport;
    return {
      width: Math.max(1, Math.floor(vv && vv.width > 0 ? vv.width : window.innerWidth)),
      height: Math.max(1, Math.floor(vv && vv.height > 0 ? vv.height : window.innerHeight)),
      left: vv && Number.isFinite(vv.offsetLeft) ? vv.offsetLeft : 0,
      top: vv && Number.isFinite(vv.offsetTop) ? vv.offsetTop : 0
    };
  }
  function fitCanvas(alreadyCanceled) {
    // CSS transforms exchange getBoundingClientRect axes; use UNTRANSFORMED client sizes.
    if (frame.clientWidth < 1 || frame.clientHeight < 1) return;
    // 按物理像素渲染，HiDPI 屏幕才不糊；布局尺寸仍以 CSS 像素为准，
    // 由 main.gd 的 Window.content_scale_size 保持。
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const width = Math.max(1, Math.round(frame.clientWidth * dpr));
    const height = Math.max(1, Math.round(frame.clientHeight * dpr));
    if (canvas.width === width && canvas.height === height) return;
    if (!alreadyCanceled) { cancelInput(); ++revision; }
    canvas.width = width;
    canvas.height = height;
  }
  function layout(nextMode, forceCancel) {
    const view = viewport();
    const nextRotated = nextMode && view.height > view.width;
    const key = [nextMode, nextRotated, view.width, view.height, view.left, view.top].join(':');
    const changed = key !== layoutKey;
    if (changed || forceCancel) {
      cancelInput();
      ++revision;
    }
    const rotationChanged = nextRotated !== rotated;
    pageMode = nextMode;
    rotated = nextRotated;
    if (changed) {
      layoutKey = key;
      shell.setAttribute('data-page-mode', pageMode ? 'landscape' : 'normal');
      shell.setAttribute('data-page-rotated', String(rotated));
      shell.style.left = view.left + 'px';
      shell.style.top = view.top + 'px';
      shell.style.width = (rotated ? view.height : view.width) + 'px';
      shell.style.height = (rotated ? view.width : view.height) + 'px';
      shell.style.transform = rotated ? 'translateX(' + view.width + 'px) rotate(90deg)' : 'none';
    }
    fitCanvas(changed || forceCancel);
    syncButtons();
    if (rotationChanged && pageMode) say(modeDescription());
  }
  function queueLayout() {
    if (!layoutFrame) layoutFrame = window.requestAnimationFrame(function () {
      layoutFrame = 0;
      layout(pageMode, false);
    });
  }
  // The engine asks this adapter before its standard position/movement conversion.
  // Returning null delegates unchanged landscape/normal behavior to Godot.
  window.LivehouseCanvasInput = Object.freeze({
    position: function (target, event, rect) {
      if (target !== canvas || !rotated || rect.width <= 0 || rect.height <= 0) return null;
      return [
        (event.clientY - rect.top) * canvas.width / rect.height,
        (rect.right - event.clientX) * canvas.height / rect.width
      ];
    },
    movement: function (target, event, rect) {
      if (target !== canvas || !rotated || rect.width <= 0 || rect.height <= 0) return null;
      return [
        (event.movementY || 0) * canvas.width / rect.height,
        -(event.movementX || 0) * canvas.height / rect.width
      ];
    }
  });
  window.LivehouseDisplay = Object.freeze({
    get mode() { return pageMode ? 'page-landscape' : 'normal'; },
    get rotated() { return rotated; },
    get revision() { return revision; }
  });
  pageButton.addEventListener('click', function () {
    layout(!pageMode, true);
    say(modeDescription());
    focusGame();
  });

  function clearEntryTimer() { window.clearTimeout(entryTimer); entryTimer = 0; }
  function enterSucceeded(token) {
    if (token !== generation || !isFullscreen() || !entering) return;
    clearEntryTimer();
    entering = false;
    observedFullscreen = true;
    layout(pageMode, true);
    say('已进入系统全屏；不锁定设备方向，页面内横屏可单独开关。');
    focusGame();
  }
  function enterFailed(token) {
    if (token !== generation || !entering) return;
    if (isFullscreen()) { enterSucceeded(token); return; }
    clearEntryTimer();
    entering = false;
    say('未能进入系统全屏，可能受浏览器或嵌入页面限制。可直接使用页面内横屏。');
    syncButtons();
    queueLayout();
    focusGame();
  }
  function restoreAfterExit() {
    ++generation;
    clearEntryTimer();
    entering = false;
    exiting = false;
    observedFullscreen = false;
    layout(pageMode, true);
    say(pageMode ? '已退出系统全屏；页面内横屏仍开启，可用返回按钮退出。' : '已退出系统全屏，恢复正常页面显示。');
    focusGame();
  }
  function onFullscreenChange() {
    if (isFullscreen()) {
      if (entering) enterSucceeded(generation);
      else {
        if (!observedFullscreen) say('已进入系统全屏；页面内横屏可单独开关。');
        observedFullscreen = true;
        layout(pageMode, true);
      }
    } else if (observedFullscreen || exiting) restoreAfterExit();
    else queueLayout();
  }
  button.addEventListener('click', function () {
    if (entering || exiting) return;
    if (isFullscreen()) {
      const exit = document.exitFullscreen || document.webkitExitFullscreen;
      if (typeof exit !== 'function') { say('请使用浏览器退出全屏控件，或按 Esc 退出系统全屏。'); return; }
      const token = ++generation;
      exiting = true;
      syncButtons();
      let request;
      try { request = exit.call(document); }
      catch (_) { request = Promise.reject(new Error('exit rejected')); }
      Promise.resolve(request).then(function () {
        if (token !== generation) return;
        if (!isFullscreen()) restoreAfterExit();
        else { exiting = false; syncButtons(); }
      }, function () {
        if (token !== generation) return;
        exiting = false;
        say('未能退出系统全屏；请使用浏览器退出控件或 Esc。页面横屏仍可单独关闭。');
        syncButtons();
      });
      return;
    }
    const request = shell.requestFullscreen || shell.webkitRequestFullscreen;
    if (typeof request !== 'function') {
      say('当前浏览器不支持系统全屏；可直接选择页面内横屏，浏览器地址栏会保留。');
      focusGame(); return;
    }
    const enabled = shell.requestFullscreen ? document.fullscreenEnabled : document.webkitFullscreenEnabled;
    if (enabled === false) {
      say('当前页面未获系统全屏权限；页面内横屏仍可使用，无需更改权限。');
      focusGame(); return;
    }
    if (fullscreenElement()) { say('请先退出其他系统全屏内容；页面内横屏可独立使用。'); return; }
    const token = ++generation;
    entering = true;
    syncButtons();
    say('正在请求系统全屏…页面内横屏也可独立使用。');
    let result;
    try { result = request.call(shell); } // Synchronous in the real user gesture.
    catch (_) { enterFailed(token); return; }
    if (result && typeof result.then === 'function') {
      result.then(function () {
        if (isFullscreen()) enterSucceeded(token); else enterFailed(token);
      }, function () { enterFailed(token); });
    }
    if (entering) entryTimer = window.setTimeout(function () {
      if (token !== generation || !entering) return;
      if (isFullscreen()) enterSucceeded(token); else enterFailed(token);
    }, 5000);
  });
  for (const control of [pageButton, button]) {
    control.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape') event.stopPropagation();
    });
  }
  for (const event of ['fullscreenchange', 'webkitfullscreenchange']) document.addEventListener(event, onFullscreenChange);
  for (const event of ['fullscreenerror', 'webkitfullscreenerror']) document.addEventListener(event, function () { enterFailed(generation); });
  window.addEventListener('resize', queueLayout);
  window.addEventListener('orientationchange', queueLayout);
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', queueLayout);
    window.visualViewport.addEventListener('scroll', queueLayout);
  }
  if (typeof ResizeObserver === 'function') new ResizeObserver(queueLayout).observe(frame);
  window.addEventListener('blur', cancelInput);
  window.addEventListener('pagehide', cancelInput);
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) cancelInput(); else queueLayout();
  });
  window.addEventListener('pageshow', queueLayout);
  say(modeDescription());
  layout(false, false);
}());
