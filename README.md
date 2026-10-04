# Routekeeper

**Каждому приложению — свой путь.**

Routekeeper для macOS отправляет выбранные приложения через ваш прокси-сервер, остальные оставляет как есть и следит, чтобы ничего не ушло мимо прокси. Для каждого исходящего соединения он решает, что с ним делать: пустить через прокси, напрямую, заблокировать или спросить вас. Например, рабочий мессенджер идёт через ваш прокси, банк напрямую, а незнакомая программа блокируется.

**[getroutekeeper.app](https://getroutekeeper.app/)** ·
[Документация](https://getroutekeeper.app/docs/) ·
[Быстрый старт](https://getroutekeeper.app/docs/start/) ·
[Свой прокси-сервер](https://getroutekeeper.app/docs/server/) ·
[Конфиденциальность](https://getroutekeeper.app/privacy/) ·
[Что нового](CHANGELOG.md)

Код приложения закрыт. Здесь лежат сборки, список изменений, сайт и скрипт для своего прокси-сервера ([`server.sh`](server.sh)).

## Скачать

**[Скачать Routekeeper.dmg](../../releases/latest/download/Routekeeper.dmg)** — последняя версия, публичная бета. Все версии — в **[Releases](../../releases)**, что в них нового — в [CHANGELOG.md](CHANGELOG.md).

DMG подписан Developer ID и заверен Apple (нотаризован). При первом открытии macOS, как обычно для программ из интернета, спросит, открыть ли его. Обновления Routekeeper проверяет сам и ставит после вашего подтверждения. Чтобы узнавать о новых версиях, нажмите **Watch → Custom → Releases** вверху этой страницы.

**Требования:**
- macOS 14 Sonoma или новее, Mac на Apple Silicon или Intel;
- учётная запись администратора: macOS попросит три разрешения для сетевого расширения;
- приложение должно лежать в папке «Программы».

Пошагово — в [быстром старте](https://getroutekeeper.app/docs/start/).

## Что умеет

- **Маршрут для приложения в один клик:** через выбранный прокси, напрямую, блокировать или спрашивать. Приложение узнаётся по подписи разработчика вместе с его дочерними процессами, поэтому правило для терминала действует и на `git`, `npm`, `curl`.
- **Сервисы:** готовые наборы адресов (видеосервисы, мессенджеры, AI-сервисы и другие), чтобы отправить через прокси только их, а не всё приложение.
- **Правила-исключения** по домену, подсети, порту и протоколу. Побеждает самое точное правило, а не первое в списке.
- **Прокси SOCKS5, HTTP CONNECT и HTTPS**, с логином и паролем или без. Строку вида `socks5://user:pass@host:port` можно просто вставить.
- **Если прокси недоступен,** соединения не уходят напрямую (если вы сами этого не разрешили). Маршруты можно перевести на другой прокси и отменить перевод.
- **Четыре режима файрвола:** «Только прокси», «Тихий», «Спрашивать», «Блокировать всё».
- **Обзор, монитор и раздел утечек:** состояние прокси, каждое соединение и его маршрут, а также DNS, UDP и процессы, которые ушли мимо прокси, с подсказкой, как это закрыть.
- **Интерфейс** на русском и английском.

Чего Routekeeper не умеет и почему — в разделе [«Ограничения»](https://getroutekeeper.app/docs/limits/). Главное: через прокси идёт только TCP, поэтому звонкам и играм прокси не поможет.

## Приватность

Routekeeper не собирает телеметрию и ничего не отправляет разработчику. Сам он ходит в сеть только за обновлениями, за списками адресов сервисов и, через ваш прокси, за проверкой внешнего IP. Подробно — в [политике конфиденциальности](https://getroutekeeper.app/privacy/).

## Сообщить об ошибке

1. Проверьте [«Если не работает»](https://getroutekeeper.app/docs/troubleshooting/): там разобраны частые проблемы и сообщения приложения.
2. Соберите диагностику: **Справка → Собрать диагностику…**. Архив появится на рабочем столе. В нём настройки без паролей, но с адресом и логином прокси, последние соединения и логи за 30 минут. Просмотрите его перед отправкой: issue здесь публичные.
3. [Откройте issue](../../issues/new/choose): версия Routekeeper и macOS, что делали, что ожидали, что получилось.

Если приложение не открывается, логи можно собрать командой:

```bash
log show --last 30m --info --predicate 'subsystem BEGINSWITH "app.getroutekeeper" OR subsystem BEGINSWITH "dev.ilyabazenov"' > routekeeper.log
```

---

## English

**Routekeeper** for macOS sends the apps you choose through your proxy server, leaves the rest alone, and makes sure nothing slips past the proxy. For every outgoing connection it decides what to do: send it through a proxy, let it go direct, block it, or ask you.

- **Download:** [Routekeeper.dmg](../../releases/latest/download/Routekeeper.dmg) (public beta). Signed with Developer ID and notarized by Apple; it updates itself after you confirm.
- **Requirements:** macOS 14 Sonoma or later, Apple Silicon or Intel, an admin account. The app must live in Applications.
- **Docs:** [getroutekeeper.app/en/docs](https://getroutekeeper.app/en/docs/) · [Quick start](https://getroutekeeper.app/en/docs/start/) · [Your own proxy server](https://getroutekeeper.app/en/docs/server/) · [Privacy](https://getroutekeeper.app/en/privacy/) · [What's new](CHANGELOG.md)
- **Bug reports:** collect diagnostics with **Help → Collect Diagnostics…** (review the archive first: it contains proxy addresses and recent connections), then [open an issue](../../issues/new/choose).

The app's source code is closed. This repository holds releases, the changelog, the website and the proxy server installer [`server.sh`](server.sh).
