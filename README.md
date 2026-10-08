<div align="center">

<a href="https://getroutekeeper.app/"><img src="icon.png" width="128" height="128" alt="Routekeeper"></a>

# Routekeeper

**Каждому приложению — свой путь.**

Прокси для отдельных приложений на macOS — без утечек и с файрволом.

**Русский** · [English](README.en.md)

[![Последняя версия](https://img.shields.io/github/v/release/ilyabazhenov/routekeeper?style=flat-square&label=%D0%B2%D0%B5%D1%80%D1%81%D0%B8%D1%8F&color=ffb547&labelColor=0a0f1f)](../../releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-ffb547?style=flat-square&logo=apple&logoColor=white&labelColor=0a0f1f)](https://getroutekeeper.app/docs/start/)
[![Нотаризован Apple](https://img.shields.io/badge/Developer_ID-%D0%BD%D0%BE%D1%82%D0%B0%D1%80%D0%B8%D0%B7%D0%BE%D0%B2%D0%B0%D0%BD-3ecf8e?style=flat-square&labelColor=0a0f1f)](https://getroutekeeper.app/docs/start/)
[![Без телеметрии](https://img.shields.io/badge/%D0%B1%D0%B5%D0%B7_%D1%82%D0%B5%D0%BB%D0%B5%D0%BC%D0%B5%D1%82%D1%80%D0%B8%D0%B8-3ecf8e?style=flat-square&labelColor=0a0f1f)](https://getroutekeeper.app/privacy/)

<br>

<a href="../../releases/latest/download/Routekeeper.dmg"><img src="https://img.shields.io/badge/%D0%A1%D0%BA%D0%B0%D1%87%D0%B0%D1%82%D1%8C_%D0%B4%D0%BB%D1%8F_Mac-Routekeeper.dmg-ffb547?style=for-the-badge&logo=apple&logoColor=white&labelColor=0a0f1f" alt="Скачать для Mac" height="40"></a>

**[Сайт](https://getroutekeeper.app/)** ·
**[Документация](https://getroutekeeper.app/docs/)** ·
**[Быстрый старт](https://getroutekeeper.app/docs/start/)** ·
**[Свой сервер](https://getroutekeeper.app/docs/server/)** ·
**[Что нового](CHANGELOG.md)**

<br>

<a href="https://getroutekeeper.app/"><img src=".github/readme/app-ru.png" alt="Окно Routekeeper: Telegram и Slack идут через прокси, Safari и Zoom напрямую, Adobe Updater заблокирован" width="100%"></a>

</div>

<br>

Routekeeper отправляет выбранные приложения через ваш прокси-сервер, остальные оставляет как есть и следит, чтобы ничего не ушло мимо прокси. Для каждого исходящего соединения он решает, что с ним делать:

| | Действие | Например |
|:-:|---|---|
| 🟢 | **Через прокси** — через выбранный вами SOCKS5-, HTTP- или HTTPS-прокси | Telegram, Slack, `git` и `curl` в терминале |
| ⚪ | **Напрямую** — как будто Routekeeper нет | Банк, Госуслуги, маркетплейсы |
| 🔴 | **В тупик** — соединение сбрасывается | Незнакомая программа, которая рвётся в сеть |
| 🟡 | **Спросить** — окно-вопрос с подписью, путём и родительскими процессами | Всё, на что правила ещё нет |

## Что умеет

**Маршруты**
- **Приложение — в один клик:** через выбранный прокси, напрямую, в тупик или спросить. Приложение узнаётся по подписи разработчика вместе с helper-процессами, поэтому правило для терминала действует и на `git`, `npm`, `curl`.
- **Сервисы:** готовые наборы адресов — видеосервисы, мессенджеры, AI-сервисы, сервисы для разработчиков, а также российские сервисы, которые идут напрямую. Можно отправить через прокси только их, а не всё приложение. Каталог обновляется с сайта, без новой версии приложения.
- **Правила-исключения** по домену, шаблону `*.`, IP, подсети, порту и протоколу. Побеждает самое точное правило, а не первое в списке.

**Не протекает**
- **Если прокси недоступен,** соединения получают отказ, а не уходят напрямую (если вы сами этого не разрешили). Маршруты можно перевести на другой прокси — и отменить перевод.
- **UDP и QUIC** у проксируемых приложений закрыты, имена сайтов разрешает прокси.
- **«Мимо прокси»:** DNS к провайдеру, UDP и процессы, которые ушли мимо прокси, — с подсказкой, как это закрыть.

**Видно, что происходит**
- **Обзор:** всё ли работает, самая серьёзная проблема и кнопка, которая её решает; состояние каждого прокси и что прямо сейчас идёт через него.
- **Монитор** каждого соединения и его маршрута, с картой трафика.
- **Четыре режима файрвола:** «Только прокси», «Тихий», «Спрашивать», «Блокировать всё». После установки Routekeeper только маршрутизирует и ни о чём не спрашивает.

**Свой прокси-сервер**
- **Мастер «Свой сервер…»:** IP, пароль сервера и домен — и Routekeeper сам поставит на VPS HTTPS-прокси и добавит его. Потом в карточке прокси сервер можно проверить, обновить, сменить пароль.
- **Или вручную,** одной командой на сервере с Debian или Ubuntu — скрипт [`server.sh`](server.sh) из этого репозитория:

  ```bash
  curl -fsSL https://getroutekeeper.app/server.sh | bash -s -- --domain my-name.duckdns.org
  ```

Прокси — SOCKS5, HTTP CONNECT и HTTPS, с логином и паролем или без; строку вида `socks5://user:pass@host:port` можно просто вставить. С VLESS и Shadowsocks Routekeeper работает через локальный SOCKS5-порт их клиента. Интерфейс — на русском и английском.

Чего Routekeeper не умеет и почему — в разделе [«Ограничения»](https://getroutekeeper.app/docs/limits/). Главное: через прокси идёт только TCP, поэтому звонкам и играм прокси не поможет.

## Установка

1. **[Скачайте Routekeeper.dmg](../../releases/latest/download/Routekeeper.dmg)** и перетащите Routekeeper в папку «Программы».
2. **Откройте его и разрешите сетевое расширение.** macOS попросит три разрешения; нужна учётная запись администратора.
3. **Добавьте прокси** — свой или [поставьте сервер из приложения](https://getroutekeeper.app/docs/server/).
4. **Введите лицензию.** Без неё всё настраивается, но трафик Routekeeper не направляет. Как получить — на странице [«Лицензия»](https://getroutekeeper.app/docs/license/).

Пошагово — в [быстром старте](https://getroutekeeper.app/docs/start/).

> [!NOTE]
> **Требования:** macOS 14 Sonoma или новее, Mac на Apple Silicon или Intel.
> DMG подписан Developer ID и нотаризован Apple. Обновления Routekeeper проверяет сам и ставит после вашего подтверждения. Чтобы узнавать о новых версиях здесь, нажмите **Watch → Custom → Releases** вверху страницы.

## Приватность

Routekeeper не собирает телеметрию, не требует аккаунта и ничего не отправляет разработчику. Сам он ходит в сеть только за обновлениями, за каталогом сервисов и, через ваш прокси, за проверкой внешнего IP. Правила и пароли хранит системное расширение в файле, доступном только root. Подробно — в [политике конфиденциальности](https://getroutekeeper.app/privacy/).

## Сообщить об ошибке

1. Проверьте [«Если не работает»](https://getroutekeeper.app/docs/troubleshooting/): там разобраны частые проблемы и сообщения приложения.
2. Соберите диагностику: **Справка → Собрать диагностику…** Архив появится на рабочем столе. В нём настройки без паролей, но с адресом и логином прокси, последние соединения и логи за 30 минут. **Просмотрите его перед отправкой:** issue здесь публичные.
3. [Откройте issue](../../issues/new/choose): версия Routekeeper и macOS, что делали, что ожидали, что получилось.

<details>
<summary>Приложение не открывается — как собрать логи</summary>

```bash
log show --last 30m --info --predicate 'subsystem BEGINSWITH "app.getroutekeeper" OR subsystem BEGINSWITH "dev.ilyabazenov"' > routekeeper.log
```

</details>

## Что в этом репозитории

Код приложения закрыт. Здесь лежат:

| | |
|---|---|
| [Releases](../../releases) | Routekeeper.dmg, все версии |
| [CHANGELOG.md](CHANGELOG.md) | Что нового — коротко по версиям |
| [`server.sh`](server.sh) | Установщик своего HTTPS-прокси на Debian или Ubuntu |
| [Issues](../../issues) | Ошибки и предложения |
| Остальное | Сайт [getroutekeeper.app](https://getroutekeeper.app/) и документация (GitHub Pages) |

<br>

<div align="center">
<sub><a href="https://getroutekeeper.app/">getroutekeeper.app</a></sub>
</div>
