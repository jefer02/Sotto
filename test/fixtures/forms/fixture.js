// Shared behaviour for the form fixtures:
// - a live status box with every field's value, so you can see what Sotto filled;
// - an alarm if a password or payment field is focused, read through the
//   value setter, or changed (Sotto must never touch them), or Submit is pressed;
// - the custom dropdown (popup appended to <body>) and the custom slider.
(function () {
  const status = document.getElementById('status');
  let sensitiveTouched = [];

  function values() {
    const out = {};
    document.querySelectorAll('[data-q]').forEach((el) => {
      const q = el.dataset.q;
      if (el.dataset.sensitive) return;
      if (el.type === 'radio') {
        if (el.checked) out[q] = el.value;
        else if (!(q in out)) out[q] = '';
      } else if (el.type === 'checkbox') {
        out[q] = out[q] || [];
        if (el.checked) out[q].push(el.value);
      } else if (el.getAttribute('role') === 'combobox') {
        out[q] = el.dataset.value || '';
      } else if (el.getAttribute('role') === 'slider') {
        out[q] = el.getAttribute('aria-valuenow');
      } else {
        out[q] = el.value;
      }
    });
    return out;
  }

  function render() {
    if (!status) return;
    const v = values();
    const filled = Object.values(v).filter((x) => (Array.isArray(x) ? x.length : x)).length;
    status.textContent =
      `${filled}/${Object.keys(v).length} answered\n` +
      Object.entries(v).map(([k, x]) => `${k}: ${Array.isArray(x) ? x.join(', ') : x}`).join('\n') +
      `\nsensitive fields touched: ${sensitiveTouched.length ? sensitiveTouched.join(', ') : 'no'}`;
    status.className = sensitiveTouched.length ? 'alarm' : '';
  }

  document.querySelectorAll('[data-sensitive]').forEach((el) => {
    const flag = (what) => () => {
      const name = `${el.dataset.q} (${what})`;
      if (!sensitiveTouched.includes(name)) sensitiveTouched.push(name);
      render();
    };
    el.addEventListener('focus', flag('focused'));
    el.addEventListener('input', flag('changed'));
    el.addEventListener('change', flag('changed'));
  });

  document.addEventListener('input', render);
  document.addEventListener('change', render);

  // ── Custom dropdown: role=combobox, popup appended to <body> on open ──
  document.querySelectorAll('[role=combobox][data-options]').forEach((combo) => {
    const options = combo.dataset.options.split('|');
    const label = combo.querySelector('.combo-value');
    let popup = null;
    const close = () => {
      if (popup) popup.remove();
      popup = null;
      combo.setAttribute('aria-expanded', 'false');
    };
    const choose = (o) => {
      combo.dataset.value = o;
      label.textContent = o;
      close();
      render();
    };
    const open = () => {
      if (popup) return close();
      popup = document.createElement('div');
      popup.className = 'popup';
      popup.id = combo.getAttribute('aria-controls');
      popup.setAttribute('role', 'listbox');
      popup.setAttribute('aria-label', combo.getAttribute('aria-label') || 'Options');
      options.forEach((o) => {
        const item = document.createElement('div');
        item.setAttribute('role', 'option');
        item.setAttribute('aria-selected', String(combo.dataset.value === o));
        item.tabIndex = -1;
        item.textContent = o;
        item.addEventListener('click', () => choose(o));
        popup.appendChild(item);
      });
      // Outside the combo in the DOM, placed under it on screen.
      const r = combo.getBoundingClientRect();
      popup.style.left = `${r.left + window.scrollX}px`;
      popup.style.top = `${r.bottom + window.scrollY + 4}px`;
      document.body.appendChild(popup);
      combo.setAttribute('aria-expanded', 'true');
    };
    combo.addEventListener('click', open);
    combo.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowDown') {
        e.preventDefault();
        open();
      } else if (e.key === 'Escape') {
        close();
      }
    });
    document.addEventListener('click', (e) => {
      if (popup && !popup.contains(e.target) && !combo.contains(e.target)) close();
    });
  });

  // ── Custom slider: role=slider, keyboard and click ──
  document.querySelectorAll('[role=slider][data-q]').forEach((slider) => {
    const min = Number(slider.getAttribute('aria-valuemin'));
    const max = Number(slider.getAttribute('aria-valuemax'));
    const thumb = slider.querySelector('.thumb');
    const set = (v) => {
      v = Math.max(min, Math.min(max, Math.round(v)));
      slider.setAttribute('aria-valuenow', String(v));
      slider.setAttribute('aria-valuetext', `${v} of ${max}`);
      thumb.style.left = `${((v - min) / (max - min)) * 280}px`;
      render();
    };
    slider.addEventListener('keydown', (e) => {
      const now = Number(slider.getAttribute('aria-valuenow'));
      if (e.key === 'ArrowRight' || e.key === 'ArrowUp') set(now + 1);
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') set(now - 1);
      else if (e.key === 'Home') set(min);
      else if (e.key === 'End') set(max);
      else return;
      e.preventDefault();
    });
    slider.addEventListener('click', (e) => {
      const r = slider.getBoundingClientRect();
      set(min + ((e.clientX - r.left) / r.width) * (max - min));
    });
    set(Number(slider.getAttribute('aria-valuenow')));
  });

  document.querySelectorAll('form').forEach((f) =>
    f.addEventListener('submit', (e) => {
      e.preventDefault();
      // Sotto never presses Submit on its own: this lights the alarm.
      if (!sensitiveTouched.includes('SUBMIT pressed')) sensitiveTouched.push('SUBMIT pressed');
      render();
    }),
  );

  render();
})();
