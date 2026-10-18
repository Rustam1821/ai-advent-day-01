'use strict';
let state;
let initialized = false;
let rendered = '';
let pending = false;
const el = id => document.getElementById(id);
const weekdays = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
function updateClock() {
  const now = new Date();
  const zone = state?.profile.timezone;
  const clock = el('current-time');
  clock.dateTime = now.toISOString();
  clock.textContent = new Intl.DateTimeFormat('ru-RU', {
    dateStyle: 'full', timeStyle: 'medium', ...(zone ? {timeZone: zone} : {}),
  }).format(now) + (zone ? ` · ${zone}` : ' · время компьютера');
}
async function api(path, data) {
  const options = data === undefined ? {} : {method: 'POST', headers: {'Content-Type': 'application/json', 'X-Local-Token': state.token}, body: JSON.stringify(data)};
  const response = await fetch(path, options);
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Ошибка запроса');
  return result;
}
function text(tag, content) {
  const node = document.createElement(tag);
  node.textContent = content;
  return node;
}
function card(event, recommendation) {
  const article = document.createElement('article');
  article.append(text('h3', event.title_ru || event.title), text('p', `${event.local_date} · ${event.venue}\n${event.address}`), text('p', event.description_ru || event.description));
  if (event.title_ru || event.description_ru) {
    const original = document.createElement('details');
    original.append(text('summary', 'Оригинал из источника'), text('p', event.title), text('p', event.description));
    article.append(original);
  }
  if (recommendation) article.append(text('p', `Почему стоит посетить: ${event.reason}`));
  const link = text('a', 'Открыть событие · Ticketmaster');
  // The server also validates URLs; never interpret provider text as HTML.
  if (event.url.startsWith('https://')) link.href = event.url;
  link.target = '_blank';
  link.rel = 'noopener noreferrer';
  article.append(link);
  if (recommendation) {
    const actions = document.createElement('div');
    for (const [vote, label] of [['like', '👍 Нравится'], ['dislike', '👎 Не подходит'], ['clear', 'Сбросить']]) {
      const button = text('button', label);
      const current = state.feedback[event.id]?.vote;
      if (current === vote) button.className = 'selected';
      button.addEventListener('click', async () => {
        button.disabled = true;
        try { await api('/api/feedback', {id: event.id, vote}); await refresh(); }
        catch (error) { el('error').textContent = error.message; button.disabled = false; }
      });
      actions.append(button);
    }
    article.append(actions);
  }
  return article;
}
async function refresh() {
  state = await api('/api/state');
  updateClock();
  if (!initialized) {
    for (const key of ['city', 'timezone', 'preferences']) el(key).value = state.profile[key];
    el('interests').value = state.profile.interests.join(', ');
    el('schedule-weekday').value = String(state.schedule.weekday);
    el('schedule-time').value = state.schedule.time;
    initialized = true;
  }
  const missing = Object.entries(state.configured).filter(([, ready]) => !ready).map(([key]) => key);
  el('config').textContent = missing.length ? `Не настроены: ${missing.join(', ')}. Заполните .env и перезапустите сервис.` : 'Ключи настроены. Доступность внешних сервисов проверяется при запуске поиска.';
  el('schedule').textContent = `${weekdays[state.schedule.weekday]}, ${state.schedule.time} (${state.profile.timezone}), каждую неделю. Следующий запуск: ${state.next_schedule}`;
  el('run').disabled = state.running || pending;
  el('run').textContent = state.running ? 'Поиск выполняется…' : 'Найти мероприятия сейчас';
  el('status').textContent = state.run.telegram || 'Подборка ещё не запускалась';
  el('error').textContent = state.last_error || '';
  el('period').textContent = state.run.weekend ? `· ${state.run.profile.city} · ${state.run.weekend}` : '';
  const recommendations = state.run.recommendations || [];
  el('warnings').textContent = [...(state.run.warnings || []), ...(state.run.finished_at && recommendations.length > 0 && recommendations.length < 5 ? ['Доступно менее 5 рекомендаций; недостающие события не добавляются.'] : [])].join(' ');
  const fingerprint = JSON.stringify([state.run, state.feedback]);
  if (rendered !== fingerprint) {
    el('recommendations').replaceChildren(...recommendations.map(event => card(event, true)));
    if (!recommendations.length) el('recommendations').append(text('p', state.running ? 'Ожидаем результаты…' : 'Рекомендаций пока нет. Подробности — в статусе и журнале.'));
    const events = state.run.events || [];
    el('count').textContent = `(${events.length})`;
    el('events').replaceChildren(...events.map(event => card(event, false)));
    rendered = fingerprint;
  }
  el('logs').textContent = (state.logs || []).map(row => `${new Date(row.time).toLocaleString('ru-RU')} [${row.stage}] ${row.message}`).join('\n');
}
el('profile').addEventListener('submit', async event => {
  event.preventDefault();
  el('save').disabled = true;
  try {
    await api('/api/profile', {city: el('city').value, timezone: el('timezone').value, interests: el('interests').value.split(',').map(x => x.trim()).filter(Boolean), preferences: el('preferences').value});
    el('saved').textContent = 'Сохранено';
    await refresh();
  } catch (error) { el('error').textContent = error.message; }
  finally { el('save').disabled = false; }
});
el('schedule-form').addEventListener('submit', async event => {
  event.preventDefault();
  el('save-schedule').disabled = true;
  el('schedule-saved').textContent = '';
  try {
    await api('/api/schedule', {weekday: Number(el('schedule-weekday').value), time: el('schedule-time').value});
    el('schedule-saved').textContent = 'Сохранено';
    await refresh();
  } catch (error) { el('error').textContent = error.message; }
  finally { el('save-schedule').disabled = false; }
});
el('run').addEventListener('click', async () => {
  pending = true;
  el('run').disabled = true;
  try { await api('/api/run', {}); await refresh(); }
  catch (error) { el('error').textContent = error.message; }
  finally { pending = false; el('run').disabled = Boolean(state?.running); }
});
async function poll() {
  try { await refresh(); }
  catch (error) { el('error').textContent = `Нет связи с сервисом: ${error.message}`; }
  setTimeout(poll, 3000);
}
updateClock();
setInterval(updateClock, 1000);
poll();
