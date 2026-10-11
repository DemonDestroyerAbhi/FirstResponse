/// Static CSS and JS for the site. Kept small: pages must load fast on a
/// cheap phone over a weak connection.
library;

const styleCss = r'''
:root {
  --bg: #ffffff; --fg: #1a1a1a; --muted: #5c5c5c; --line: #dddddd;
  --accent: #0f766e; --notice-bg: #fff6db; --notice-fg: #5c4300;
  --ok-bg: #e6f4f1; --ok-fg: #0b4f49;
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #121212; --fg: #ececec; --muted: #a8a8a8; --line: #333333;
    --accent: #5eead4; --notice-bg: #3a2f0b; --notice-fg: #fde68a;
    --ok-bg: #0f2e2b; --ok-fg: #99f6e4;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font: 18px/1.6 system-ui, -apple-system, "Segoe UI", Roboto,
    "Noto Sans", "Noto Sans Devanagari", sans-serif;
}
header, main, footer { max-width: 44rem; margin: 0 auto; padding: 0 1rem; }
header { padding-top: 1rem; }
.brand { font-weight: 700; color: var(--fg); text-decoration: none; }
a { color: var(--accent); }
h1 { font-size: 1.8rem; line-height: 1.25; margin: 1.5rem 0 0.5rem; }
h2 { font-size: 1.25rem; margin-top: 2rem; }
.lead { font-size: 1.1rem; }
.crumbs { margin-top: 1rem; color: var(--muted); font-size: 0.9rem; }
.notice, .banner, .checked { padding: 0.75rem 1rem; border-radius: 8px; }
.notice, .banner { background: var(--notice-bg); color: var(--notice-fg); }
.checked { background: var(--ok-bg); color: var(--ok-fg); }
.quotes { padding-left: 1.2rem; }
.steps { padding-left: 1.4rem; }
.steps li { margin-bottom: 1rem; }
.steps p { margin: 0.2rem 0; }
.rules li { margin-bottom: 0.6rem; }
.rules small { color: var(--muted); }
.meta, footer { color: var(--muted); font-size: 0.85rem; }
footer { margin-top: 3rem; padding-bottom: 2rem; border-top: 1px solid var(--line); }
.filter, .diagnose label { display: block; font-weight: 600; }
input[type=search], textarea {
  display: block; width: 100%; margin-top: 0.4rem; padding: 0.6rem;
  font: inherit; color: inherit; background: transparent;
  border: 1px solid var(--line); border-radius: 8px;
}
button {
  margin-top: 0.6rem; padding: 0.6rem 1.4rem; font: inherit; font-weight: 600;
  color: #fff; background: #0f766e; border: 0; border-radius: 8px; cursor: pointer;
}
.diagnose { margin-top: 2rem; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; }
.diagnose h2 { margin-top: 0; }
.result:not(:empty) { margin-top: 1rem; }
[hidden] { display: none !important; }
''';

/// Search filter for the guide list, and the "check your message" box.
/// Uses textContent only, never innerHTML, so API text cannot inject markup.
const siteJs = r'''
(() => {
  const filter = document.getElementById('filter');
  if (filter) {
    filter.addEventListener('input', () => {
      const q = filter.value.trim().toLowerCase();
      for (const li of document.querySelectorAll('.rules li')) {
        li.hidden = q !== '' && !li.dataset.search.includes(q);
      }
    });
  }

  const api = document.documentElement.dataset.api;
  if (!api) return;

  const el = (tag, text) => {
    const e = document.createElement(tag);
    if (text) e.textContent = text;
    return e;
  };
  const ruleLink = (id, title) => {
    const href = RULE_PAGES[id];
    if (!href) return el('strong', title);
    const a = el('a', title);
    a.href = href;
    return a;
  };

  for (const form of document.querySelectorAll('.diagnose-form')) {
    const out = form.parentElement.querySelector('.result');
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const text = form.elements.text.value.trim();
      if (!text) return;
      out.replaceChildren(el('p', 'Checking…'));
      try {
        const res = await fetch(api.replace(/\/$/, '') + '/v1/diagnose', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ text, portal: form.dataset.portal }),
        });
        if (!res.ok) throw new Error(String(res.status));
        show(out, await res.json());
      } catch {
        out.replaceChildren(el('p', "Couldn't reach the server. Please try again in a moment."));
      }
    });
  }

  function show(out, d) {
    if (d.decision === 'answer') {
      const p = el('p', 'This looks like: ');
      p.append(ruleLink(d.rule.id, d.rule.title));
      out.replaceChildren(p, el('p', d.rule.explain));
    } else if (d.decision === 'confirm') {
      const ul = el('ul');
      for (const c of d.candidates) {
        const li = el('li');
        li.append(ruleLink(c.ruleId, c.title));
        ul.append(li);
      }
      out.replaceChildren(el('p', 'Is it one of these?'), ul);
    } else {
      out.replaceChildren(el('p',
        "We don't recognise this message yet, so we've noted it for our team. " +
        'Check that it is copied exactly, or ask at the office that showed it.'));
    }
  }
})();
''';
