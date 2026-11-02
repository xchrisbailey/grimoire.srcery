const picker = document.querySelector('.picker');
const previews = document.querySelector('.previews');
const buttons = [...picker.querySelectorAll('button')];
const figures = [...previews.querySelectorAll('.preview')];

function selectPreview(button) {
  for (const choice of buttons) {
    choice.setAttribute('aria-pressed', String(choice === button));
  }
  for (const figure of figures) {
    figure.hidden = figure.id !== button.dataset.choice;
  }
}

// Enhance the complete image-and-caption list only after its controls are ready.
for (const button of buttons) {
  button.addEventListener('click', () => selectPreview(button));
  button.addEventListener('keydown', (event) => {
    const index = buttons.indexOf(button);
    let next;
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % buttons.length;
    if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index - 1 + buttons.length) % buttons.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = buttons.length - 1;
    if (next === undefined) return;
    event.preventDefault();
    buttons[next].focus();
    selectPreview(buttons[next]);
  });
}
selectPreview(buttons.find((button) => button.getAttribute('aria-pressed') === 'true'));
previews.classList.add('enhanced');
picker.hidden = false;

// Content starts visible; an unavailable observer never leaves unreadable sections.
if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('arriving');
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.1 });
  document.querySelectorAll('[data-enter]').forEach((element) => observer.observe(element));
}
