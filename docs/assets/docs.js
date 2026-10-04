// Routekeeper docs: copy buttons on commands, and old single-page anchors → new pages.
document.querySelectorAll('.cmd').forEach(function (box) {
  var lang = document.documentElement.lang;
  var label = lang === 'ru' ? 'Копировать' : 'Copy';
  var done = lang === 'ru' ? 'Скопировано' : 'Copied';
  var btn = document.createElement('button');
  btn.className = 'copy'; btn.type = 'button'; btn.textContent = label;
  btn.addEventListener('click', function () {
    navigator.clipboard.writeText(box.querySelector('pre').innerText.trim()).then(function () {
      btn.textContent = done;
      setTimeout(function () { btn.textContent = label; }, 1600);
    });
  });
  box.appendChild(btn);
});
(function () {
  var moved = document.body.dataset.moved;
  if (!moved || !location.hash) return;
  var map = JSON.parse(moved);
  var to = map[location.hash.slice(1)];
  if (to) location.replace(to);
})();
