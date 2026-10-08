'use strict';

// 与 iOS 版 PlanSettings.swift 保持一致
const PLAN = {
  totalDays: 180,
  phaseOneDays: 30,
  readAloudTimes: 3,
  readingPassScore: 0.75,
  examPassRate: 0.8,
  ownSentenceMinWords: 5,
  examAnswerSeconds: 6,
  phaseExamPassRate: 0.9,
  examExtraOld: 5,
  phases: [[1, 30, '生活情境语块'], [31, 60, '第一人称自言自语'], [61, 120, '单句影子跟读'], [121, 180, '提问与接茬']],
};
const INTERVALS = [0, 1, 2, 4, 7, 15, 30, 60];
const MASTERED_BOX = 5;
const DAY_MS = 86400000;
const STORE_KEY = 'studyen-prototype-v1';

let CHUNKS = [], BYID = {}, ORDER = [];
let DRILLS = [], DRILL_BYID = {};
let store = loadStore();
let tab = 'today';
let S = null; // 当前训练会话
let libKind = 'phrasal', libQuery = '';

// ---------- 存储 ----------
function defaultStore() {
  return {
    progress: {},
    drills: {}, // 语序造句：id -> { date, firstTry }
    days: {},
    phaseExam: { passed: false, bestScore: 0, attempts: 0, lastAttemptDay: null },
    dev: { offsetDays: 0, typeMode: false },
  };
}
function loadStore() {
  try {
    const s = JSON.parse(localStorage.getItem(STORE_KEY));
    if (s && s.progress) return Object.assign(defaultStore(), s);
  } catch (e) { /* 无痕模式等情况下读不到，用空数据 */ }
  return defaultStore();
}
function saveStore() {
  try { localStorage.setItem(STORE_KEY, JSON.stringify(store)); } catch (e) { /* ignore */ }
}

// ---------- 时间（测试工具可以快进） ----------
const now = () => Date.now() + store.dev.offsetDays * DAY_MS;
const pad = n => String(n).padStart(2, '0');
function dayKey(t) { const d = new Date(t); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }
function startOfDay(t) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
const isToday = t => t != null && dayKey(t) === dayKey(now());
function studyDay() {
  const k = dayKey(now());
  return store.days[k] || (store.days[k] = { reviews: 0, newLearned: 0, checkedIn: false, examScore: 0, examAttempts: 0 });
}

// ---------- 间隔复习 ----------
function applySRS(rating, p) {
  const t = now();
  if (rating === 'again') {
    p.box = 0; p.lapseCount++; p.due = t;
  } else {
    p.box = Math.min(p.box + 1, INTERVALS.length - 1);
    p.due = startOfDay(t) + INTERVALS[p.box] * DAY_MS;
  }
  p.reviewCount++;
  p.lastReviewed = t;
}

// ---------- 语音比对（与 SpeechChecker.swift 的 PhraseMatcher 一致） ----------
const EXPANSIONS = { gonna: ['going', 'to'], wanna: ['want', 'to'], gotta: ['got', 'to'], kinda: ['kind', 'of'], sorta: ['sort', 'of'], ya: ['you'], im: ['i', 'am'], ill: ['i', 'will'], ive: ['i', 'have'], theres: ['there', 'is'] };
const NUMBERS = { 0: 'zero', 1: 'one', 2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six', 7: 'seven', 8: 'eight', 9: 'nine', 10: 'ten', 11: 'eleven', 12: 'twelve' };
const IRREGULAR = {
  get: ['got', 'gotten'], run: ['ran'], come: ['came'], give: ['gave', 'given'], make: ['made'], sell: ['sold'],
  catch: ['caught'], throw: ['threw', 'thrown'], take: ['took', 'taken'], go: ['went', 'gone'], have: ['had', 'has'],
  hang: ['hung'], burn: ['burnt'], wake: ['woke'], be: ['am', 'is', 'are', 'was', 'were'],
};
function words(text) {
  return text.toLowerCase().replace(/[’']/g, '').split(/[^a-z0-9]+/).filter(Boolean)
    .flatMap(w => EXPANSIONS[w] || (NUMBERS[w] ? [NUMBERS[w]] : [w]));
}
function wordMatches(t, h) {
  return h === t || (t.length >= 3 && h.startsWith(t)) || (IRREGULAR[t] || []).includes(h);
}
function matchesPhrase(phrase, text) {
  const heard = words(text);
  return phrase.split('/').some(alt => {
    const target = words(alt);
    if (!target.length) return false;
    let i = 0;
    for (const w of heard) if (i < target.length && wordMatches(target[i], w)) i++;
    return i === target.length;
  });
}
function readingScore(sentence, text) {
  const a = words(sentence), b = words(text);
  if (!a.length || !b.length) return 0;
  const dp = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = 1; i <= a.length; i++)
    for (let j = 1; j <= b.length; j++)
      dp[i][j] = wordMatches(a[i - 1], b[j - 1]) ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
  return dp[a.length][b.length] / a.length;
}
function isOwnSentence(text, c) {
  return matchesPhrase(c.phrase, text) && words(text).length >= PLAN.ownSentenceMinWords && readingScore(c.example, text) < 0.7;
}

// ---------- 语序判定：主 → 谓 → 宾 → 方式 → 地点 → 时间 ----------
const ROLE_ZH = {
  S: '主语', V: '谓语', O: '宾语', M: '方式', P: '地点', T: '时间',
  Q: '疑问词', A: '助动词', F: '频率副词', L: '引导句', E: '存在句', W: '伴随', R: '原因/目的',
};
const ORDER_RULE = '中文状语往前挤，英文状语往后退';
const PATTERN_TIP = {
  question: '特殊疑问句：疑问词 + 助动词 + 主语 + 动词（不说 Where you are going）',
  yesno: '一般疑问句：助动词或 be 动词放在句首',
  frequency: '频率副词（always / usually / never…）放在实义动词前、be 动词后',
  indirect: '间接疑问句用陈述语序：Do you know where he is，不说 where is he',
  there: '“某处有某物”说 There is + 东西 + 地点',
  extra: `伴随、方式、原因、目的都往句尾放：${ORDER_RULE}`,
};
const patternHint = d => PATTERN_TIP[d.pattern] || '主 → 谓 → 宾 → 方式 → 地点 → 时间';

// 在识别结果里找某个成分的起始位置（允许中间夹 1 个多余的词）
function findSegment(heard, seg) {
  for (let i = 0; i < heard.length; i++) {
    if (!wordMatches(seg[0], heard[i])) continue;
    let j = i + 1, k = 1;
    while (k < seg.length && j < heard.length && j <= i + k + 1) {
      if (wordMatches(seg[k], heard[j])) k++;
      j++;
    }
    if (k === seg.length) return i;
  }
  return -1;
}
function checkOrder(drill, text) {
  const heard = words(text);
  const pos = {};
  for (const s of drill.segments) {
    const p = findSegment(heard, words(s.en));
    if (p < 0) return { ok: false, msg: `缺少${ROLE_ZH[s.role]}「${s.en}」` };
    pos[s.role] = p;
  }
  if (drill.pattern && drill.pattern !== 'basic') return checkPatternOrder(drill, pos);
  if (pos.V < pos.S) return { ok: false, msg: '谓语要紧跟在主语后面' };
  for (const r of ['O', 'P', 'T']) {
    if (pos[r] != null && pos[r] > pos.S && pos[r] < pos.V) {
      return { ok: false, msg: `${ROLE_ZH[r]}不能夹在主语和谓语中间：${ORDER_RULE}` };
    }
  }
  if (pos.O != null && pos.O < pos.V) return { ok: false, msg: '宾语要放在谓语后面' };
  // 时间可以放句首；放句尾时必须在地点后面
  if (pos.P != null && pos.T != null && pos.T > pos.S && pos.T < pos.P) {
    return { ok: false, msg: '英文里地点在前、时间在后' };
  }
  return { ok: true };
}
// 疑问句、间接疑问句等：主干成分按标准顺序逐个检查。
// 时间、地点、方式、伴随、原因目的这类状语，放在标准位置或整句句首都是正确英语。
const FLEXIBLE = new Set(['T', 'P', 'M', 'W', 'R']);
function checkPatternOrder(drill, pos) {
  const tip = PATTERN_TIP[drill.pattern] || '';
  const core = drill.segments.filter(s => !FLEXIBLE.has(s.role));
  for (let i = 1; i < core.length; i++) {
    if (pos[core[i].role] < pos[core[i - 1].role]) {
      return { ok: false, msg: `「${core[i - 1].en}」要放在「${core[i].en}」前面。${tip}` };
    }
  }
  const coreStart = Math.min(...core.map(s => pos[s.role]));
  for (let i = 1; i < drill.segments.length; i++) {
    const seg = drill.segments[i], prev = drill.segments[i - 1];
    if (!FLEXIBLE.has(seg.role) || pos[seg.role] < coreStart) continue; // 放句首可以
    if (pos[seg.role] < pos[prev.role]) {
      return { ok: false, msg: `${ROLE_ZH[seg.role]}「${seg.en}」要放在「${prev.en}」后面，或者放句首。${tip}` };
    }
  }
  return { ok: true };
}
const drillSentence = d => {
  const s = d.segments.map(x => x.en).join(' ');
  const isQuestion = ['question', 'yesno'].includes(d.pattern) || (d.pattern === 'indirect' && /^(do|can|could|would) /.test(s));
  return s.charAt(0).toUpperCase() + s.slice(1) + (isQuestion ? '?' : '.');
};
const segsHTML = d => `<div class="segs">${d.segments.map(x => `<span class="r-${x.role}">${esc(x.en)}<small>${ROLE_ZH[x.role]}</small></span>`).join('')}</div>`;
function orderLessonHTML() {
  const ex = DRILLS[0];
  return `<h2>单词都会却说不对？问题在语序</h2>
    <div class="formula">主 → 谓 → 宾 → 方式 → 地点 → 时间</div>
    <div class="formula muted small">谁 → 做 → 什么 → 怎么做 → 在哪 → 何时</div>
    <p class="small muted">中文语序：我 / 上周日 / 在图书馆 / 安静地 / 看 / 书<br>（主 / 时间 / 地点 / 方式 / 谓 / 宾）</p>
    <p class="small muted">英文语序：</p>${ex ? segsHTML(ex) : ''}
    <p style="font-weight:700">口诀：${ORDER_RULE}。</p>
    <p class="small muted">时间也可以放在句首（Last Sunday, I read…），但时间、地点绝不能夹在主语和谓语中间。</p>`;
}

// ---------- 朗读 ----------
function speak(text, slow) {
  try {
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = 'en-US';
    u.rate = slow ? 0.7 : 1;
    const v = speechSynthesis.getVoices().find(v => v.lang === 'en-US');
    if (v) u.voice = v;
    speechSynthesis.speak(u);
  } catch (e) { /* 浏览器不支持朗读 */ }
}

// ---------- 今日状态（与 TodayView.swift 的 DailyState 一致） ----------
function shuffle(arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}
function dailyState() {
  const t = now();
  const today = store.days[dayKey(t)];
  const checkedIn = !!(today && today.checkedIn);
  const checkedInDays = Object.values(store.days).filter(d => d.checkedIn).length;
  const progs = Object.entries(store.progress);
  const known = new Set(progs.map(([id]) => id));
  const introducedToday = progs.filter(([, p]) => isToday(p.introduced)).map(([id]) => id);

  const unlearnedAtDayStart = CHUNKS.length - known.size + introducedToday.length;
  const daysLeft = Math.max(1, PLAN.phaseOneDays - (checkedInDays - (checkedIn ? 1 : 0)));
  const quota = Math.ceil(unlearnedAtDayStart / daysLeft);
  const newChunks = ORDER.filter(c => !known.has(c.id)).slice(0, Math.max(0, quota - introducedToday.length));

  const doneDrills = Object.entries(store.drills);
  const drillsDoneToday = doneDrills.filter(([, d]) => isToday(d.date)).length;
  const drillQuota = Math.ceil((DRILLS.length - doneDrills.length + drillsDoneToday) / daysLeft);
  const doneSet = new Set(doneDrills.map(([id]) => id));
  const newDrills = DRILLS.filter(d => !doneSet.has(d.id)).slice(0, Math.max(0, drillQuota - drillsDoneToday));

  const due = progs.filter(([, p]) => p.due <= t).sort((a, b) => a[1].due - b[1].due).map(([id]) => BYID[id]).filter(Boolean);
  const learnedToday = introducedToday.map(id => BYID[id]).filter(Boolean);
  const olderLearned = progs.filter(([, p]) => !isToday(p.introduced)).map(([id]) => BYID[id]).filter(Boolean);

  let streak = 0;
  let cursor = startOfDay(t);
  if (!(store.days[dayKey(cursor)] || {}).checkedIn) cursor -= DAY_MS;
  while ((store.days[dayKey(cursor)] || {}).checkedIn) { streak++; cursor -= DAY_MS; }

  const pe = store.phaseExam;
  const phase1Passed = pe.passed;
  let trainingDay = checkedIn ? checkedInDays : checkedInDays + 1;
  if (!phase1Passed) trainingDay = Math.min(trainingDay, PLAN.phaseOneDays);

  const s = {
    t, today, checkedIn, checkedInDays, quota, newChunks, newDrills, drillsDoneToday, due, learnedToday, olderLearned, streak, trainingDay,
    phaseExam: pe, phase1Passed,
    phaseGate: checkedInDays >= PLAN.phaseOneDays && !phase1Passed,
    allLearned: learnedToday.concat(olderLearned),
  };
  s.learnDone = s.newChunks.length === 0;
  s.drillDone = s.newDrills.length === 0;
  s.reviewDone = s.due.length === 0;
  s.examReady = s.learnDone && s.drillDone && s.reviewDone && s.allLearned.length > 0;
  s.phaseAttemptedToday = isToday(pe.lastAttemptDay);
  return s;
}

// ---------- 渲染工具 ----------
const $app = document.getElementById('app');
const $tabs = document.getElementById('tabs');
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
const pct = x => Math.round(x * 100);
const kindTag = c => `<span class="tag ${c.kind}">${c.kind === 'phrasal' ? '短语' : '支架'}</span>`;
const speakBtn = (text, slow) => `<button class="icon-btn" data-action="speak" data-text="${esc(text)}" ${slow ? 'data-slow="1"' : ''} title="${slow ? '慢速朗读' : '朗读'}">${slow ? '🐢' : '🔊'}</button>`;

function render() {
  if (S) { $tabs.innerHTML = ''; renderSession(); return; }
  $tabs.innerHTML = [['today', '今天'], ['library', '语块库'], ['stats', '进度'], ['dev', '测试工具']]
    .map(([k, label]) => `<button data-action="tab" data-tab="${k}" class="${tab === k ? 'on' : ''}">${label}</button>`).join('');
  if (tab === 'today') renderToday();
  else if (tab === 'library') renderLibrary();
  else if (tab === 'stats') renderStats();
  else renderDev();
}

// ---------- 今天 ----------
function phaseTitle(day) {
  const i = PLAN.phases.findIndex(([a, b]) => day >= a && day <= b);
  return i < 0 ? '180 天训练已完成' : `第 ${i + 1} 阶段 · ${PLAN.phases[i][2]}`;
}
function stepHTML(n, title, detail, state, mode) {
  const icon = state === 'done' ? '✅' : state === 'locked' ? '🔒' : `${n}️⃣`;
  return `<button class="step" ${state === 'active' ? `data-action="start" data-mode="${mode}"` : 'disabled'}>
    <span class="icon">${icon}</span>
    <span class="grow"><b>第 ${n} 步 · ${esc(title)}</b><span class="muted small">${esc(detail)}</span></span>
    ${state === 'active' ? '<span class="muted">›</span>' : ''}
  </button>`;
}
function renderToday() {
  const s = dailyState();
  const ok = s.checkedIn || s.phase1Passed;
  const badge = s.phase1Passed ? '第一阶段通关' : s.phaseGate ? '阶段总考' : s.checkedIn ? '今日已达标' : '今日未打卡';

  const learnDetail = s.learnDone
    ? (s.learnedToday.length ? `已完成 · 今天学了 ${s.learnedToday.length} 个` : '今日无新语块')
    : `${s.newChunks.length} 个 · 跟读 ${PLAN.readAloudTimes} 遍 + 用它说一句自己的话`;
  const reviewDetail = s.reviewDone ? '已完成' : `${s.due.length} 个 · 必须用英文说对，错了本轮重来`;
  const drillDetail = s.drillDone
    ? (s.drillsDoneToday ? `已完成 · 今天练了 ${s.drillsDoneToday} 句` : '今日无语序练习')
    : `${s.newDrills.length} 句 · 看中文，按「主谓宾方地时」说出英文`;

  let step3;
  if (s.phase1Passed) {
    step3 = `<div class="card"><h2>🏆 第一阶段通关</h2><p class="muted small">第二阶段开放前，每天完成复习，保持语块不生疏。这段时间不计入 180 天。</p></div>`;
  } else if (s.phaseGate) {
    const pe = s.phaseExam;
    const rule = `全部 ${s.allLearned.length} 个语块限时回想，≥ ${pct(PLAN.phaseExamPassRate)}% 通关`;
    const best = pe.attempts ? ` · 已考 ${pe.attempts} 次，最高 ${pct(pe.bestScore)}%` : '';
    const detail = (s.reviewDone ? rule : `先复习错题 · ${rule}`) + best;
    step3 = stepHTML(4, '第一阶段总考', detail, s.reviewDone ? 'active' : 'locked', 'phaseExam');
  } else {
    const line = `正确率 ≥ ${pct(PLAN.examPassRate)}% 才能打卡`;
    const today = s.today || {};
    const detail = s.checkedIn ? `已打卡 · 正确率 ${pct(today.examScore)}%`
      : today.examAttempts ? `${line} · 已挑战 ${today.examAttempts} 次，最高 ${pct(today.examScore)}%` : line;
    step3 = stepHTML(4, '每日闯关', detail, s.checkedIn ? 'done' : s.examReady ? 'active' : 'locked', 'exam');
  }

  const roadmap = PLAN.phases.map(([a, b, title]) => {
    const active = s.trainingDay >= a && s.trainingDay <= b, done = s.trainingDay > b;
    return `<div class="row small" style="margin:4px 0"><span>${done ? '✅' : active ? '🔵' : '⚪'}</span>
      <span class="muted" style="width:96px">第 ${a}–${b} 天</span><span style="${active ? 'font-weight:700' : 'color:var(--muted)'}">${title}</span></div>`;
  }).join('');

  const today = s.today || {};
  const attempted = s.phaseGate ? s.phaseAttemptedToday : today.examAttempts > 0;
  const encourage = !s.checkedIn && !s.phase1Passed && attempted
    ? `<div class="card" style="background:color-mix(in srgb, var(--orange) 14%, var(--card))"><h2>🔥 今天还没达标，别放弃！</h2>
       <p class="small muted" style="margin:0">最高 ${pct(s.phaseGate ? s.phaseExam.bestScore : today.examScore)}%，达标线 ${pct(s.phaseGate ? PLAN.phaseExamPassRate : PLAN.examPassRate)}%。先把错题复习完，再重新闯关，今天就把打卡拿下。</p></div>`
    : '';

  $app.innerHTML = `
    <p class="muted small" style="margin:0">${esc(phaseTitle(s.trainingDay))} · 模拟日期 ${dayKey(s.t)}</p>
    <div class="row"><h1 class="grow">第 ${Math.min(s.trainingDay, PLAN.totalDays)} / ${PLAN.totalDays} 天</h1>
      <span class="badge ${ok ? 'ok' : 'no'}">${badge}</span></div>
    <div class="bar"><i style="width:${(s.checkedInDays / PLAN.totalDays) * 100}%"></i></div>
    <div class="tiles">
      <div class="tile"><b style="color:var(--green)">${s.checkedInDays}</b><span class="muted small">达标天数</span></div>
      <div class="tile"><b style="color:var(--orange)">${s.streak}</b><span class="muted small">连续达标</span></div>
      <div class="tile"><b style="color:var(--blue)">${s.quota}</b><span class="muted small">今日新语块</span></div>
    </div>
    ${encourage}
    ${stepHTML(1, '学新语块', learnDetail, s.learnDone ? 'done' : 'active', 'learn')}
    ${stepHTML(2, '语序造句', drillDetail, s.drillDone ? 'done' : s.learnDone ? 'active' : 'locked', 'order')}
    ${stepHTML(3, '开口复习', reviewDetail, s.reviewDone ? 'done' : s.learnDone && s.drillDone ? 'active' : 'locked', 'review')}
    ${step3}
    <div class="card"><h2>180 天路线</h2><p class="muted small">只算达标打卡的天数。没达标的日子不算，计划不会往前走。</p>${roadmap}</div>
    <div class="card"><h2>达标规则</h2><ul class="rules">
      <li>四步必须按顺序完成，前一步没过，后一步锁定</li>
      <li>语序造句：按「主 → 谓 → 宾 → 方式 → 地点 → 时间」说，${ORDER_RULE}</li>
      <li>全程开口说，由语音识别判定，不能自己点“会了”</li>
      <li>闯关每题限时 ${PLAN.examAnswerSeconds} 秒；正确率低于 ${pct(PLAN.examPassRate)}%：错题打回复习，复习完重考</li>
      <li>当天没达标就当天练到达标：错题复习完马上重考，不推到明天</li>
      <li>第 30 天后必须通过阶段总考（≥ ${pct(PLAN.phaseExamPassRate)}%，没过就复习错题后当天重考）才能进入下一阶段</li>
    </ul></div>`;
}

// ---------- 训练会话（与 TrainingSessionView.swift 一致） ----------
const isExamMode = m => m === 'exam' || m === 'phaseExam';
const MODE_TITLE = { learn: '学新语块', order: '语序造句', review: '开口复习', exam: '每日闯关', phaseExam: '第一阶段总考' };

function startSession(mode) {
  const s = dailyState();
  let chunks;
  if (mode === 'learn') chunks = s.newChunks;
  else if (mode === 'order') chunks = s.newDrills;
  else if (mode === 'review') chunks = s.due;
  else if (mode === 'exam') chunks = s.learnedToday.concat(shuffle(s.olderLearned).slice(0, PLAN.examExtraOld));
  else chunks = s.allLearned;
  if (!chunks.length) return;

  if (mode === 'phaseExam') recordPhaseAttempt();
  S = { mode, queue: isExamMode(mode) ? shuffle(chunks) : chunks.slice(), index: 0, wrong: [], result: null,
    examChunks: chunks, retryExam: null,
    lesson: mode === 'order' && Object.keys(store.drills).length === 0 };
  resetCard();
  render();
  onCardShown();
}
function recordPhaseAttempt() {
  store.phaseExam.attempts++;
  store.phaseExam.lastAttemptDay = now();
  saveStore();
}
// 没达标：当场复习错题，复习完马上重考，不推到明天
function startRetryReview() {
  stopListening(false);
  S.retryExam = S.mode;
  S.mode = 'review';
  S.queue = S.result.wrong.slice();
  S.wrong = [];
  S.result = null;
  S.index = 0;
  resetCard();
  render();
  onCardShown();
}
function retake() {
  S.mode = S.retryExam;
  S.retryExam = null;
  if (S.mode === 'phaseExam') recordPhaseAttempt();
  S.queue = shuffle(S.examChunks);
  S.wrong = [];
  S.result = null;
  S.index = 0;
  resetCard();
  render();
  onCardShown();
}
function resetCard() {
  Object.assign(S, { readPasses: 0, ownDone: false, failed: 0, revealed: false, correct: false, feedback: null, transcript: '', recording: false, itemDone: false, lastCheck: null });
}
const current = () => (S && S.index < S.queue.length ? S.queue[S.index] : null);
const maxAttempts = () => (isExamMode(S.mode) ? 2 : 3);
const passRate = () => (S.mode === 'phaseExam' ? PLAN.phaseExamPassRate : PLAN.examPassRate);

function onCardShown() {
  const c = current();
  if (!c || S.lesson) return;
  S.shownAt = Date.now();
  if (S.mode === 'learn') speak(c.example);
  if (isExamMode(S.mode) && !store.dev.typeMode) startListening();
}

// 当前这一步要判定什么
function evaluate(text) {
  const c = current();
  if (S.mode === 'order') {
    if (S.revealed) return readingScore(drillSentence(c), text) >= 0.8;
    S.lastCheck = checkOrder(c, text);
    return S.lastCheck.ok;
  }
  if (S.mode === 'learn') {
    return S.readPasses >= PLAN.readAloudTimes ? isOwnSentence(text, c) : readingScore(c.example, text) >= PLAN.readingPassScore;
  }
  return matchesPhrase(c.phrase, text);
}
function onPass() {
  const c = current();
  if (S.mode === 'order') {
    store.drills[c.id] = { date: now(), firstTry: !S.revealed && S.failed === 0 };
    saveStore();
    S.itemDone = true;
    S.feedback = null;
    if (!S.revealed) { S.revealed = true; S.correct = true; }
    render();
    return;
  }
  if (S.mode === 'learn') {
    if (S.readPasses >= PLAN.readAloudTimes) { S.ownDone = true; S.feedback = '这句是你自己的了'; }
    else {
      S.readPasses++;
      S.feedback = S.readPasses >= PLAN.readAloudTimes ? '三遍全部达标！现在用它说一句你自己的话' : '很好，再读一遍';
    }
    render();
  } else {
    markResult(c, true);
  }
}
function attemptFailed() {
  const c = current();
  if (!c) return;
  if (S.mode === 'order') {
    if (S.revealed) { S.feedback = '没读对，照着正确语序再读一遍'; render(); return; }
    S.failed++;
    const why = (S.lastCheck && S.lastCheck.msg) || '没听清，再说一遍';
    if (S.failed >= 3) {
      S.revealed = true; S.correct = false;
      S.feedback = `${why}。看正确语序，大声读一遍才能过`;
      speak(drillSentence(c));
    } else {
      S.feedback = `${why}（还有 ${3 - S.failed} 次机会）`;
    }
    render();
    return;
  }
  if (S.mode === 'learn') {
    S.feedback = S.readPasses >= PLAN.readAloudTimes
      ? `没达标：句子里要有 ${c.phrase}，至少 ${PLAN.ownSentenceMinWords} 个词，而且不能照读例句`
      : `没达标：要读对例句中 ${pct(PLAN.readingPassScore)}% 的词，再来一遍`;
    render();
    return;
  }
  S.failed++;
  if (S.failed >= maxAttempts()) markResult(c, false);
  else { S.feedback = `${isExamMode(S.mode) ? '超时或不对' : '不对'}，还有 ${maxAttempts() - S.failed} 次机会`; render(); }
}
function markResult(c, ok) {
  S.revealed = true; S.correct = ok; S.feedback = null;
  speak(c.phrase);
  const p = store.progress[c.id];
  if (ok && p) p.lastLatency = (Date.now() - S.shownAt) / 1000;
  if (S.mode === 'review') {
    if (p) applySRS(ok ? 'good' : 'again', p);
    studyDay().reviews++;
    if (!ok) S.queue.push(c);
  } else if (isExamMode(S.mode) && !ok) {
    S.wrong.push(c);
  }
  saveStore();
  render();
}
function completeLearning() {
  const c = current();
  const t = now();
  store.progress[c.id] = store.progress[c.id] || { box: 0, due: t, introduced: t, lastReviewed: null, reviewCount: 0, lapseCount: 0, lastLatency: null };
  store.progress[c.id].due = startOfDay(t) + DAY_MS; // 今天由闯关检验，明天进入复习
  studyDay().newLearned++;
  saveStore();
  next();
}
function next() {
  stopListening(false);
  if (isExamMode(S.mode) && S.index + 1 >= S.queue.length) finishExam();
  S.index++;
  resetCard();
  render();
  onCardShown();
}
function finishExam() {
  const total = S.queue.length;
  const score = total ? (total - S.wrong.length) / total : 0;
  const passed = score >= passRate();
  S.wrong.forEach(c => { if (store.progress[c.id]) applySRS('again', store.progress[c.id]); });
  if (S.mode === 'phaseExam') {
    store.phaseExam.bestScore = Math.max(store.phaseExam.bestScore, score);
    if (passed) { store.phaseExam.passed = true; store.phaseExam.passedDate = now(); }
  } else {
    const d = studyDay();
    d.examAttempts++;
    d.examScore = Math.max(d.examScore, score);
    if (passed) d.checkedIn = true;
  }
  saveStore();
  S.result = { score, passed, wrong: S.wrong.slice() };
}

// ---------- 语音识别（Web Speech API） ----------
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
let rec = null, recTimer = null;

function startListening() {
  if (!SR) { S.feedback = '这个浏览器不支持语音识别。请用 Edge 或 Chrome，或者在「测试工具」里打开“键盘代替说话”。'; render(); return; }
  stopListening(false);
  try { speechSynthesis.cancel(); } catch (e) { /* ignore */ }
  const r = new SR();
  r.lang = 'en-US';
  r.interimResults = true;
  r.continuous = true;
  rec = r;
  S.transcript = '';
  S.recording = true;
  S.feedback = null;
  r.onresult = e => {
    if (rec !== r) return;
    let text = '';
    for (let i = 0; i < e.results.length; i++) text += e.results[i][0].transcript + ' ';
    S.transcript = text.trim();
    if (evaluate(S.transcript)) { stopListening(false); onPass(); } else renderSession();
  };
  r.onerror = e => {
    if (rec !== r) return;
    const msg = {
      'not-allowed': '麦克风权限被拒绝：点地址栏左侧的图标允许麦克风。',
      'network': '语音识别服务连不上。Chrome 的识别依赖 Google 服务器，国内网络建议改用 Edge，或在「测试工具」里打开“键盘代替说话”。',
      'audio-capture': '没有检测到麦克风。',
    }[e.error];
    if (msg) { S.feedback = msg; stopListening(false); render(); }
  };
  r.onend = () => { if (rec === r) stopListening(true); };
  r.start();
  const timeout = isExamMode(S.mode) ? PLAN.examAnswerSeconds : 8;
  recTimer = setTimeout(() => { if (rec === r) stopListening(true); }, timeout * 1000);
  render();
}
// notify=true：没判定达标就结束，算一次失败
function stopListening(notify) {
  clearTimeout(recTimer);
  const r = rec;
  rec = null;
  if (r) { try { r.abort(); } catch (e) { /* ignore */ } }
  if (S && S.recording) {
    S.recording = false;
    if (notify) attemptFailed(); else renderSession();
  }
}

function renderOrderCard(c, top) {
  let controls;
  const answerInput = label => store.dev.typeMode
    ? `<input type="text" id="typed" placeholder="键盘代替说话：输入英文，回车提交" autocomplete="off">
       <button class="primary" data-action="submit-typed">${label}</button>`
    : `<button class="record ${S.recording ? 'on' : ''}" data-action="record">${S.recording ? '🎙 正在听…点我结束' : `🎤 ${label}`}</button>`;
  if (S.itemDone) controls = `<button class="primary" data-action="next">${S.index + 1 >= S.queue.length ? '完成' : '下一句'}</button>`;
  else if (S.revealed) controls = answerInput('照着正确语序读一遍');
  else controls = answerInput('用英文说出这句话');

  let extra = '';
  if (S.revealed) {
    extra += `<p class="${S.correct ? 'result-ok' : 'result-no'}">${S.correct ? '✔ 语序正确' : '✘ 语序没过'}</p>${segsHTML(c)}
      <div class="row"><b class="grow">${esc(drillSentence(c))}</b>${speakBtn(drillSentence(c))}</div>`;
  }
  if (S.recording || S.transcript) extra += `<div class="small muted" style="margin-top:8px">听到的：</div><div class="heard">${esc(S.transcript || '…')}</div>`;
  if (S.feedback) extra += `<div class="feedback">${esc(S.feedback)}</div>`;

  $app.innerHTML = `${top}
    <div class="card"><div class="formula small">${esc(patternHint(c))}</div>
      <div class="big" style="font-size:24px;margin-top:8px">${esc(c.zh)}</div>${extra}</div>
    <div class="controls">${controls}</div>`;
  const typed = document.getElementById('typed');
  if (typed) typed.focus();
}

function renderSession() {
  if (!S) return;
  const c = current();
  const top = `<div class="topbar"><button class="ghost" data-action="exit">退出</button>
    <b>${MODE_TITLE[S.mode]}</b><span class="muted small">${c ? `${S.index + 1} / ${S.queue.length}` : ''}</span></div>
    <div class="bar"><i style="width:${(Math.min(S.index, S.queue.length) / S.queue.length) * 100}%"></i></div>`;

  if (S.result) {
    const r = S.result, phase = S.mode === 'phaseExam';
    const title = phase ? (r.passed ? '第一阶段通关' : '总考还差一点') : (r.passed ? '打卡成功' : '差一点！今天还没达标');
    const msg = phase ? (r.passed ? '全部语块都能脱口而出了。' : '错题复习完马上可以重考，今天就把它拿下。')
      : (r.passed ? '今天的训练达标了，明天继续。' : '今天的打卡还在等你。复习错题后马上重考，练到达标为止。');
    const gap = Math.max(1, Math.ceil(Math.round((passRate() - r.score) * 1000) / 10));
    $app.innerHTML = `${top}
      <div class="center" style="margin-top:32px"><div style="font-size:56px">${r.passed ? '✅' : '❌'}</div><h1>${title}</h1>
      <p class="muted">正确率 ${pct(r.score)}%（达标线 ${pct(passRate())}%）</p>
      ${r.passed ? '' : `<p class="feedback">只差 ${gap}%，复习完这 ${r.wrong.length} 个错题就能再冲一次</p>`}</div>
      ${r.wrong.length ? `<div class="card"><h2>错题</h2>${r.wrong.map(c => `<div class="row small"><b class="grow">${esc(c.phrase)}</b><span class="muted">${esc(c.meaning)}</span></div>`).join('')}</div>` : ''}
      <p class="muted center small">${msg}</p>
      <div class="controls">${r.passed ? '<button class="primary" data-action="exit">完成</button>'
        : '<button class="primary" data-action="retry-review">复习错题，马上重考</button>'}</div>`;
    return;
  }
  if (!c && S.retryExam) {
    $app.innerHTML = `${top}<div class="center" style="margin-top:48px"><div style="font-size:56px">🔥</div><h1>错题都说对了！</h1>
      <p class="muted">趁热重新闯关，今天就把打卡拿下。</p></div>
      <div class="controls"><button class="primary" data-action="retake">重新闯关</button></div>`;
    return;
  }
  if (!c) {
    $app.innerHTML = `${top}<div class="center" style="margin-top:48px"><div style="font-size:56px">✅</div><h1>这一步完成了</h1>
      <p class="muted">${S.mode === 'learn' ? '下一步：语序造句' : `下一步：每日闯关，正确率 ≥ ${pct(PLAN.examPassRate)}% 才能打卡`}</p></div>
      <div class="controls"><button class="primary" data-action="exit">返回</button></div>`;
    return;
  }

  if (S.lesson) {
    $app.innerHTML = `${top}<div class="card">${orderLessonHTML()}</div>
      <div class="controls"><button class="primary" data-action="lesson-done">懂了，开始练</button></div>`;
    return;
  }
  if (S.mode === 'order') { renderOrderCard(c, top); return; }

  const showAnswer = S.mode === 'learn' || S.revealed;
  const body = showAnswer ? `
      <div class="row"><span class="big grow">${esc(c.phrase)}</span>${speakBtn(c.phrase)}</div>
      <div style="font-size:18px">${esc(c.meaning)} ${c.replaces ? `<span class="strike">≈ ${esc(c.replaces)}</span>` : ''}</div>
      <div class="example"><div class="row"><b class="grow">${esc(c.example)}</b>${speakBtn(c.example, true)}</div>
        <div class="muted">${esc(c.exampleZh)}</div></div>
      ${c.tip ? `<div class="muted small">💡 ${esc(c.tip)}</div>` : ''}`
    : `
      <div class="big">${esc(c.meaning)}</div>
      ${c.replaces ? `<p class="warn">⛔ 别说 ${esc(c.replaces)}，用口语怎么说？</p>` : ''}
      ${isExamMode(S.mode) ? '' : `<p class="muted">${esc(c.exampleZh)}</p>`}`;

  let extra = '';
  if (S.revealed) extra += `<p class="${S.correct ? 'result-ok' : 'result-no'}">${S.correct ? '✔ 说对了' : isExamMode(S.mode) ? '✘ 答错，计入错题' : '✘ 没过，本轮末尾再来一次'}</p>`;
  if (S.mode === 'learn') {
    extra += `<p class="small muted">跟读例句达标 <span class="dots">${Array.from({ length: PLAN.readAloudTimes }, (_, i) => `<i class="${i < S.readPasses ? 'on' : ''}"></i>`).join('')}</span></p>`;
    if (S.readPasses >= PLAN.readAloudTimes) {
      extra += `<p class="${S.ownDone ? 'result-ok' : ''}" style="${S.ownDone ? '' : 'color:var(--blue);font-weight:700'}">${S.ownDone ? '✔ 造句达标' : `💬 用 ${esc(c.phrase)} 说一句你自己的话（≥${PLAN.ownSentenceMinWords} 个词，不能照读例句）`}</p>`;
      if (!S.ownDone) extra += `<p class="small muted">语序提示：主 → 谓 → 宾 → 方式 → 地点 → 时间</p>`;
    }
  }
  if (isExamMode(S.mode) && !S.revealed) extra += `<p class="muted small">⏱ 限时 ${PLAN.examAnswerSeconds} 秒，脱口而出才算${store.dev.typeMode ? '（键盘模式不计时）' : ''}</p>`;
  if (S.recording || S.transcript) extra += `<div class="small muted">听到的：</div><div class="heard">${esc(S.transcript || '…')}</div>`;
  if (S.feedback) extra += `<div class="feedback">${esc(S.feedback)}</div>`;

  let controls;
  const answerInput = (label) => store.dev.typeMode
    ? `<input type="text" id="typed" placeholder="键盘代替说话：输入你要说的英文，回车提交" autocomplete="off">
       <button class="primary" data-action="submit-typed">${label}</button>`
    : `<button class="record ${S.recording ? 'on' : ''}" data-action="record">${S.recording ? '🎙 正在听…点我结束' : `🎤 ${label}`}</button>`;
  if (S.mode === 'learn') {
    if (S.ownDone) controls = `<button class="primary" data-action="learn-next">达标，下一个</button>`;
    else if (S.readPasses >= PLAN.readAloudTimes) controls = answerInput('说一句自己的话');
    else controls = answerInput(`大声读例句（${S.readPasses}/${PLAN.readAloudTimes}）`);
  } else if (S.revealed) {
    controls = `<button class="primary" data-action="next">${S.index + 1 >= S.queue.length ? '完成' : '下一个'}</button>`;
  } else {
    controls = answerInput('说出英文') + `<button class="link" data-action="giveup">想不起来，看答案</button>`;
  }

  $app.innerHTML = `${top}
    <div class="card"><div class="row small">${kindTag(c)}<span class="muted">${esc(c.scene)}</span></div>
      <div style="margin-top:12px">${body}</div>${extra}</div>
    <div class="controls">${controls}</div>`;
  const typed = document.getElementById('typed');
  if (typed) typed.focus();
}

function submitTyped() {
  const input = document.getElementById('typed');
  if (!input || !input.value.trim()) return;
  S.transcript = input.value.trim();
  if (evaluate(S.transcript)) onPass(); else attemptFailed();
}

// ---------- 语块库 ----------
function statusBadge(id) {
  const p = store.progress[id];
  if (!p) return '<span class="badge off">未学</span>';
  return p.box >= MASTERED_BOX ? '<span class="badge ok">已掌握</span>' : '<span class="badge mid">学习中</span>';
}
function renderLibrary() {
  if (libKind === 'order') {
    $app.innerHTML = `<h1>语块库</h1>${libSegHTML()}
      <div class="card">${orderLessonHTML()}</div>
      <p class="muted small">语序造句库共 ${DRILLS.length} 句，已练 ${Object.keys(store.drills).length} 句</p>
      <div class="list">${DRILLS.map(d => `<div class="item"><div class="small">${esc(d.zh)}</div>
        <div class="row"><b class="grow small">${store.drills[d.id] ? esc(drillSentence(d)) : '<span class="muted">（练过后显示答案）</span>'}</b>
        ${store.drills[d.id] ? speakBtn(drillSentence(d)) : ''}</div></div>`).join('')}</div>`;
    return;
  }
  const q = libQuery.trim().toLowerCase();
  const items = CHUNKS.filter(c => c.kind === libKind &&
    (!q || c.phrase.toLowerCase().includes(q) || c.meaning.includes(q) || (c.replaces || '').toLowerCase().includes(q)));
  const scenes = [...new Set(items.map(c => c.scene))];
  const total = CHUNKS.filter(c => c.kind === libKind).length;
  const listHTML = scenes.map(scene => `<div class="scene">${esc(scene)}</div><div class="list">${items.filter(c => c.scene === scene).map(c => `
      <div class="item row"><div class="grow"><b>${esc(c.phrase)}</b>
        <div class="muted small">${esc(c.meaning)} ${c.replaces ? `<span class="strike">${esc(c.replaces)}</span>` : ''}</div>
        <div class="small" style="margin-top:4px">${esc(c.example)}</div></div>
        ${speakBtn(c.example)}${statusBadge(c.id)}</div>`).join('')}</div>`).join('');

  if (!document.getElementById('lib-search')) {
    $app.innerHTML = `<h1>语块库</h1>${libSegHTML()}
      <input type="search" id="lib-search" placeholder="搜英文、中文或被替代的大词">
      <p class="muted small" id="lib-count"></p><div id="lib-list"></div>`;
    document.getElementById('lib-search').addEventListener('input', e => { libQuery = e.target.value; renderLibrary(); });
  }
  document.getElementById('lib-search').value = libQuery;
  document.querySelectorAll('[data-action="lib-kind"]').forEach(b => b.classList.toggle('on', b.dataset.kind === libKind));
  document.getElementById('lib-count').textContent = `共 ${total} 个，显示 ${items.length} 个`;
  document.getElementById('lib-list').innerHTML = listHTML || '<p class="muted center">没有匹配的语块</p>';
}

function libSegHTML() {
  return `<div class="seg three">${[['phrasal', '短语动词'], ['filler', '谈话润滑剂'], ['order', '语序规则']]
    .map(([k, label]) => `<button data-action="lib-kind" data-kind="${k}" class="${libKind === k ? 'on' : ''}">${label}</button>`).join('')}</div>`;
}

// ---------- 进度 ----------
function renderStats() {
  const days = Object.entries(store.days).sort((a, b) => a[0].localeCompare(b[0]));
  const checked = days.filter(([, d]) => d.checkedIn);
  const progs = Object.entries(store.progress);
  const mastered = progs.filter(([, p]) => p.box >= MASTERED_BOX).length;
  const avg = checked.length ? checked.reduce((a, [, d]) => a + d.examScore, 0) / checked.length : 0;
  const colors = ['var(--blue)', 'var(--purple)', 'var(--orange)', 'var(--green)'];
  const grid = Array.from({ length: PLAN.totalDays }, (_, i) => {
    const phase = PLAN.phases.findIndex(([a, b]) => i + 1 >= a && i + 1 <= b);
    return `<i style="${i < checked.length ? `background:${colors[phase]}` : ''}"></i>`;
  }).join('');
  const weakest = progs.filter(([, p]) => p.lapseCount > 0).sort((a, b) => b[1].lapseCount - a[1].lapseCount).slice(0, 8);

  $app.innerHTML = `<h1>进度</h1>
    <div class="tiles">
      <div class="tile"><b style="color:var(--blue)">${progs.length}</b><span class="muted small">已学 / ${CHUNKS.length}</span></div>
      <div class="tile"><b style="color:var(--green)">${mastered}</b><span class="muted small">已掌握</span></div>
      <div class="tile"><b style="color:var(--orange)">${pct(avg)}%</b><span class="muted small">闯关均分</span></div>
    </div>
    <div class="card"><h2>语序造句</h2><p class="muted small">已练 ${Object.keys(store.drills).length} / ${DRILLS.length} 句，
      一次说对 ${Object.values(store.drills).filter(d => d.firstTry).length} 句。一次说对的比例越高，说明语序越成为本能。</p></div>
    <div class="card"><h2>180 天达标进度 · ${checked.length} / ${PLAN.totalDays}</h2><div class="grid180">${grid}</div>
      <p class="muted small">每一格代表一个达标日。没达标的日子不占格子。</p></div>
    ${weakest.length ? `<div class="card"><h2>最薄弱的语块</h2>${weakest.map(([id, p]) => `
      <div class="row small" style="margin:6px 0"><b class="grow">${esc((BYID[id] || {}).phrase || id)}</b>
      <span class="warn">忘了 ${p.lapseCount} 次</span><span class="muted">${p.lastLatency != null ? p.lastLatency.toFixed(1) + ' 秒' : ''}</span></div>`).join('')}
      <p class="muted small">秒数是最近一次答对的反应时间，越短越接近脱口而出。</p></div>` : ''}
    <div class="card"><h2>最近记录</h2>${days.slice(-14).reverse().map(([k, d]) => `
      <div class="row small" style="margin:6px 0"><span class="grow">${k}</span>
      ${d.checkedIn ? `<span class="result-ok">达标 ${pct(d.examScore)}%</span>` : `<span class="warn">${d.examAttempts ? `未达标（挑战 ${d.examAttempts} 次）` : '未打卡'}</span>`}</div>`).join('') || '<p class="muted small">还没有记录</p>'}</div>
    <button class="ghost" data-action="export" style="width:100%">导出训练数据（JSON）</button>`;
}

// ---------- 测试工具（只在原型里有，用来快速验证 30 天流程） ----------
function renderDev() {
  const s = dailyState();
  $app.innerHTML = `<h1>测试工具</h1>
    <div class="card"><h2>模拟时间</h2>
      <p class="muted small">当前模拟日期：<b>${dayKey(s.t)}</b>（真实日期偏移 ${store.dev.offsetDays} 天）</p>
      <div class="row"><button class="ghost grow" data-action="dev-next-day">跳到明天</button>
        <button class="ghost grow" data-action="dev-auto-day">自动完成今天并跳到明天</button></div>
      <p class="muted small">“自动完成”会直接把今天的新语块记为学会、复习全部记为答对、闯关记为 100% 打卡，用来快速走到第 30 天，检查阶段总考的规则。</p></div>
    <div class="card"><h2>输入方式</h2>
      <label class="row"><input type="checkbox" data-action="dev-type" ${store.dev.typeMode ? 'checked' : ''}>
      <span class="grow">键盘代替说话（没有麦克风，或语音识别连不上时用；闯关不计时）</span></label></div>
    <div class="card"><h2>语音识别自测</h2>
      <p class="muted small">先在这里确认浏览器能识别你的英语：点按钮说一句英文，看识别结果是否准确。</p>
      <button class="ghost" data-action="dev-mic" style="width:100%">🎤 测试麦克风</button>
      <p id="mic-result" class="heard"></p></div>
    <div class="card"><h2>数据</h2>
      <button class="ghost" data-action="dev-reset" style="width:100%;color:var(--red)">清空所有训练数据</button></div>`;
}
function devAutoDay() {
  const s = dailyState();
  const t = now();
  s.newChunks.forEach(c => {
    store.progress[c.id] = { box: 0, due: startOfDay(t) + DAY_MS, introduced: t, lastReviewed: null, reviewCount: 0, lapseCount: 0, lastLatency: null };
  });
  s.due.forEach(c => applySRS('good', store.progress[c.id]));
  s.newDrills.forEach(d => { store.drills[d.id] = { date: t, firstTry: true }; });
  const d = studyDay();
  d.newLearned += s.newChunks.length;
  d.reviews += s.due.length;
  if (!s.phaseGate && !s.phase1Passed) { d.checkedIn = true; d.examScore = 1; d.examAttempts++; }
  store.dev.offsetDays++;
  saveStore();
}
function devMicTest() {
  const out = document.getElementById('mic-result');
  if (!SR) { out.textContent = '这个浏览器不支持语音识别，请用 Edge 或 Chrome。'; return; }
  const r = new SR();
  r.lang = 'en-US';
  r.interimResults = true;
  out.textContent = '正在听，请说一句英文…';
  r.onresult = e => { out.textContent = Array.from(e.results).map(x => x[0].transcript).join(' '); };
  r.onerror = e => { out.textContent = `识别失败：${e.error}${e.error === 'network' ? '（连不上识别服务，建议换 Edge）' : ''}`; };
  r.start();
}

// ---------- 事件 ----------
document.addEventListener('click', e => {
  const el = e.target.closest('[data-action]');
  if (!el) return;
  const a = el.dataset.action;
  if (a === 'tab') { tab = el.dataset.tab; $app.innerHTML = ''; render(); }
  else if (a === 'start') startSession(el.dataset.mode);
  else if (a === 'speak') speak(el.dataset.text, !!el.dataset.slow);
  else if (a === 'record') { if (S.recording) stopListening(true); else startListening(); }
  else if (a === 'submit-typed') submitTyped();
  else if (a === 'giveup') { stopListening(false); markResult(current(), false); }
  else if (a === 'next') next();
  else if (a === 'learn-next') completeLearning();
  else if (a === 'exit') { stopListening(false); S = null; render(); }
  else if (a === 'lib-kind') { libKind = el.dataset.kind; $app.innerHTML = ''; renderLibrary(); }
  else if (a === 'retry-review') startRetryReview();
  else if (a === 'retake') retake();
  else if (a === 'lesson-done') { S.lesson = false; render(); onCardShown(); }
  else if (a === 'export') exportData();
  else if (a === 'dev-next-day') { store.dev.offsetDays++; saveStore(); render(); }
  else if (a === 'dev-auto-day') { devAutoDay(); render(); }
  else if (a === 'dev-type') { store.dev.typeMode = el.checked; saveStore(); }
  else if (a === 'dev-mic') devMicTest();
  else if (a === 'dev-reset') { if (confirm('确定清空所有训练数据？')) { store = defaultStore(); saveStore(); render(); } }
});
document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && e.target.id === 'typed') submitTyped();
});

function exportData() {
  const blob = new Blob([JSON.stringify(store, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `studyen-data-${dayKey(now())}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
}

// ---------- 启动：读取与 iOS 版同一份语块清单 ----------
function interleave(fillers, phrasals) {
  const out = [];
  let fi = 0, pi = 0;
  while (fi < fillers.length || pi < phrasals.length) {
    const fr = fi / Math.max(fillers.length, 1), pr = pi / Math.max(phrasals.length, 1);
    if (fi < fillers.length && (pi >= phrasals.length || fr <= pr)) out.push(fillers[fi++]);
    else out.push(phrasals[pi++]);
  }
  return out;
}
Promise.all([
  fetch('../StudyEN/Resources/chunks.json').then(r => r.json()),
  fetch('../StudyEN/Resources/word_order.json').then(r => r.json()),
])
  .then(([data, drills]) => {
    DRILLS = drills;
    drills.forEach(d => { DRILL_BYID[d.id] = d; });
    CHUNKS = data;
    data.forEach(c => { BYID[c.id] = c; });
    ORDER = interleave(data.filter(c => c.kind === 'filler'), data.filter(c => c.kind === 'phrasal'));
    render();
  })
  .catch(() => {
    $app.innerHTML = '<p class="warn">读取语块清单失败。请从项目根目录启动本地服务器后访问 /web-prototype/。</p>';
  });
