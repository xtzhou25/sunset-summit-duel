/* Native mobile-friendly account/room form. The Godot canvas owns gameplay;
 * this HTML layer only handles text entry so phone keyboards work reliably. */
(function () {
  'use strict';
  const overlay = document.createElement('div');
  overlay.id = 'duel-auth-overlay';
  overlay.hidden = true;
  overlay.innerHTML = `
    <form id="duel-auth-form" autocomplete="off">
      <h2 id="duel-auth-title">设置账号</h2>
      <p id="duel-auth-hint"></p>
      <label id="duel-auth-name-row">用户名
        <input id="duel-auth-name" maxlength="16" autocapitalize="off" autocorrect="off" />
      </label>
      <label id="duel-auth-question-row">登录问题
        <input id="duel-auth-question" maxlength="40" />
      </label>
      <label id="duel-auth-room-row">房间名
        <input id="duel-auth-room" maxlength="32" />
      </label>
      <div id="duel-auth-question-text" hidden></div>
      <label id="duel-auth-answer-row">答案
        <input id="duel-auth-answer" maxlength="40" />
      </label>
      <div id="duel-auth-error"></div>
      <div id="duel-auth-actions">
        <button type="submit" id="duel-auth-submit">注册并进入</button>
        <button type="button" id="duel-auth-switch">已有账号登录</button>
        <button type="button" id="duel-auth-cancel">取消</button>
      </div>
    </form>`;
  document.addEventListener('DOMContentLoaded', () => document.body.appendChild(overlay));
  if (document.body) document.body.appendChild(overlay);

  const form = overlay.querySelector('#duel-auth-form');
  const title = overlay.querySelector('#duel-auth-title');
  const hint = overlay.querySelector('#duel-auth-hint');
  const nameRow = overlay.querySelector('#duel-auth-name-row');
  const nameInput = overlay.querySelector('#duel-auth-name');
  const questionRow = overlay.querySelector('#duel-auth-question-row');
  const questionInput = overlay.querySelector('#duel-auth-question');
  const roomRow = overlay.querySelector('#duel-auth-room-row');
  const roomInput = overlay.querySelector('#duel-auth-room');
  const questionText = overlay.querySelector('#duel-auth-question-text');
  const answerRow = overlay.querySelector('#duel-auth-answer-row');
  const answerInput = overlay.querySelector('#duel-auth-answer');
  const errorBox = overlay.querySelector('#duel-auth-error');
  const submit = overlay.querySelector('#duel-auth-submit');
  const switchButton = overlay.querySelector('#duel-auth-switch');
  const cancel = overlay.querySelector('#duel-auth-cancel');

  let mode = 'register';
  let questionReady = false;

  function native(action, payload) {
    const fn = window.__duelAuthNative;
    if (typeof fn !== 'function') return;
    try { fn(action, JSON.stringify(payload || {})); } catch (_) {}
  }
  function error(message) { errorBox.textContent = message || ''; }
  function setSubmit(text, disabled) {
    submit.textContent = text;
    submit.disabled = !!disabled;
  }
  function configure(nextMode) {
    mode = nextMode || 'register';
    questionReady = false;
    error('');
    questionText.hidden = true;
    answerRow.style.display = 'none';
    nameRow.style.display = '';
    questionRow.style.display = '';
    roomRow.style.display = '';
    switchButton.style.display = '';
    if (mode === 'room') {
      title.textContent = '修改房间名';
      hint.textContent = '房间名会保存在本机，下次进入自动使用';
      nameRow.style.display = 'none';
      questionRow.style.display = 'none';
      roomRow.style.display = '';
      switchButton.style.display = 'none';
      setSubmit('保存房间名', false);
    } else if (mode === 'login') {
      title.textContent = '登录账号';
      hint.textContent = '输入用户名获取登录问题，答对后恢复昵称和积分';
      questionRow.style.display = 'none';
      setSubmit('获取登录问题', false);
      switchButton.style.display = 'none';
    } else {
      title.textContent = '设置账号';
      hint.textContent = '首次进入请设置用户名和登录问题；以后忘记本机信息可用答案找回';
      answerRow.style.display = '';
      setSubmit('注册并进入', false);
      switchButton.style.display = '';
    }
    setTimeout(() => {
      if (mode === 'room') roomInput.focus();
      else nameInput.focus();
    }, 40);
  }
  function open(options) {
    options = options || {};
    nameInput.value = options.name || '';
    roomInput.value = options.room || '';
    questionInput.value = options.question || '';
    answerInput.value = '';
    overlay.hidden = false;
    configure(options.mode || 'register');
  }
  function close() {
    overlay.hidden = true;
    error('');
  }
  function setQuestion(question) {
    questionReady = true;
    questionText.textContent = '登录问题：' + question;
    questionText.hidden = false;
    answerRow.style.display = '';
    setSubmit('登录并进入', false);
    setTimeout(() => answerInput.focus(), 40);
  }
  function payload() {
    return {
      name: nameInput.value.trim(),
      question: questionInput.value.trim(),
      room: roomInput.value.trim(),
      answer: answerInput.value.trim(),
    };
  }
  function submitForm(event) {
    event.preventDefault();
    const data = payload();
    if (mode === 'room') {
      if (!data.room) { error('房间名不能为空'); return; }
      native('room', data);
      close();
      return;
    }
    if (!data.name) { error('请输入用户名'); return; }
    if (mode === 'register') {
      if (!data.question) { error('请填写登录问题'); return; }
      if (!data.answer) { error('请填写答案'); return; }
      native('register', data);
      return;
    }
    if (!questionReady) {
      native('login_begin', data);
      return;
    }
    if (!data.answer) { error('请填写答案'); return; }
    native('login_answer', data);
  }
  form.addEventListener('submit', submitForm);
  switchButton.addEventListener('click', () => configure('login'));
  cancel.addEventListener('click', () => { close(); native('close', {}); });
  overlay.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') { close(); native('close', {}); }
  });

  window.DuelAuth = Object.freeze({ open, close, setQuestion, error });
  window.duelAuthInstall = function (callback) { window.__duelAuthNative = callback; };
}());
