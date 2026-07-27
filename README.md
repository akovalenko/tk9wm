# tk9wm — оконный менеджер для X11 на Tcl/Tk 9 (whale)

Reparenting-WM целиком на скрипте: ни строчки C, Xlib дёргается через
cffi. Идейный наследник tkwm (Eric Schenk, Neil McKay, 1994–95) — но без
патчей к Tk: часть машинерии TIP 47 уже в ядре Tk 9, остальное добирается
второй X-коннекцией.

Устройство: один whale-процесс, два X-соединения. Tk рисует декорации
(override-redirect-рамки), cffi-соединение владеет SubstructureRedirect
и делает WM-хирургию (save-set, reparent, map). Файлы:

- `substrate.tcl` — механизм, без которого WM не написать: cffi-обвязка
  Xlib, X-error-handler (ставится ДО загрузки Tk — порядок критичен),
  fd-помпа (worker-тред + блокирующий poll, ping-pong), manage/unmanage,
  adoption существующих окон, фокус-ядро с починкой внешнего
  PointerRoot-сброса, close-механика (WM_DELETE_WINDOW / XKillClient),
  синтетический ConfigureNotify (ICCCM 4.1.5), EWMH-минимум. Зовёт
  policy-* хуки.
- `policy.tcl` — наши локальные решения: декорации Tk-виджетами
  (титлбар/✕/слот, цвета подсветки), каскад-размещение, drag за
  заголовок, click-to-focus. Реализует policy-* хуки (контракт — в
  шапке substrate.tcl).
- `wm.tcl` — тонкая сборка: source обоих слоёв + `substrate-start`;
  режим demo для самотеста.

## Запуск

Нужен собранный whale (Tcl/Tk 9 + cffi + Thread): репа whalebuild
ожидается соседкой (`../whalebuild/work/linux/whale`), переопределяется
переменными `WHALE` / `LINUX`.

- `run-xephyr.sh [дисплей]` — живой плейграунд в Xephyr (по умолчанию :7)
  с xterm и xclock.
- Регрессии (каждая сама поднимает Xvfb, один shell-вызов):
  `run-demo.sh` (полный цикл + скриншоты), `run-adopt-test.sh` (подбор
  окон, живших до WM), `run-focus-test.sh` (ховер-тайпинг, смерть/withdraw
  фокусного окна, внешний PointerRoot-сброс), `run-withdraw-test.sh`
  (withdraw/deiconify без смерти клиента), `run-dialog-test.sh` (диалог с
  `WM_TRANSIENT_FOR` на тесном экране: центровка по родителю, прижим к
  экрану, `WM_STATE`), `run-gtk-test.sh` (GTK3-канарейка zenity).
- Диагностика живого дисплея (read-only, любой дисплей): `probe-focus.tcl`
  — снимок фокуса; `probe-watch.tcl` — вахта смен фокуса; `probe-trace.tcl`
  — что под указателем и куда ушёл фокус, построчно на каждое изменение;
  `probe-at.tcl` — цепочка окон под пикселем (пиксели врут, дерево — нет);
  `probe-grab.tcl` — держит ли кто пассивный grab на окне;
  `probe-pointer.tcl` — не заморожен ли указатель чужим sync-grab-ом;
  `set-focus.tcl` / `set-pointerroot.tcl` — внешние воздействия на фокус.
  `spike/` — исторический спайк root-redirect.

**Грабля живого Xephyr:** после интерактивного ресайза окна Xephyr экран
растёт (RandR), но **XTEST остаётся зажат в стартовом прямоугольнике** —
синтетический указатель (`xdotool`) упирается в старую границу, живая мышь
ходит везде. Значит headless-драйв такой сессии врёт: задавай финальный
размер сразу (`-screen WxH`), не ресайзи окно.

История шагов и находки — `ideas/tk9-window-manager.md` в репе thoughts.
