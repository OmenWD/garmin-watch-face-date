# Свой циферблат для Garmin Forerunner 955 — план

Дата: 2026-08-31

## 1. Вводные

| Параметр | Значение |
|---|---|
| Часы | Garmin Forerunner 955 (product id в SDK: `fr955`) |
| Экран | круглый, 260×260 px, MIP (transflective), always-on |
| Цвет | 64 цвета, приглушённые; тонкие градиенты и тёмно-серые оттенки не читаются |
| Платформа | Connect IQ 4.x (System 5), язык Monkey C |
| Стиль | цифровой минимализм: крупное время, тонкие подписи, один акцентный цвет |
| Папка проекта | `MIND/Garmin/` |

## 2. Что можно и что нельзя взять за основу

**Нельзя:**
- Стоковые циферблаты Garmin зашиты в прошивку часов, исходников нет, вытащить нельзя.
- Циферблаты из Connect IQ Store поставляются как подписанные `.prg` — декомпиляции нет.

**Можно:** форкнуть открытый циферблат и переделать под себя.

### Кандидаты на базу

| База | Что это | Лицензия | Плюсы | Минусы |
|---|---|---|---|---|
| **Сэмплы из SDK** (`~/Library/Application Support/Garmin/ConnectIQ/Sdks/<ver>/samples/`) | официальные примеры Garmin, ставятся вместе с SDK | Apache-2.0 | эталонный код, точно собирается, минимум лишнего | простые, «голые» |
| [garmin/connectiq-apps](https://github.com/garmin/connectiq-apps) → `watchfaces/` (`TypedFace`, `DanceDanceGarmin`) | официальные показательные циферблаты | Apache-2.0 | правильные паттерны, в т.ч. работа с настройками | демонстрационные, не «повседневные» |
| [fevieira27/MoveToBeActive](https://github.com/fevieira27/MoveToBeActive) | «боевой» циферблат с кучей данных (здоровье, погода, уведомления), поддержка десятков устройств | см. LICENSE в репо | много готовых готовых блоков данных; **в `manifest_example.xml` есть `<iq:product id="fr955"/>`**, `minApiLevel="3.2.0"` | тяжёлый, per-device папки ресурсов; отдельной `resources-fr955` нет — используется базовая `resources/`, раскладку под 260×260 надо проверять |
| [okdar/smartarcs](https://github.com/okdar/smartarcs) | SmartArcs — дуги по краю экрана | открытая | чистый код, хорошая работа с настройками | стиль «дуги», не наш минимализм |

**Рекомендация:** база — **сэмпл из SDK / `TypedFace`** (чистый Apache-2.0 старт под одно устройство), а из `MoveToBeActive` подсматриваем и переносим готовые куски: получение погоды, Body Battery, уведомлений, экономичную отрисовку. Так мы не тащим в проект поддержку 60 устройств и её ресурсы.

Fallback: если хочется сразу «богатый» циферблат — форкаем `MoveToBeActive`, вырезаем всё кроме `fr955` из манифеста и лишние `resources-*` папки, дальше переделываем вёрстку.

## 3. Тулчейн (шаг 0, на маке сейчас ничего не установлено)

1. Аккаунт разработчика Garmin (бесплатно) → скачать **Connect IQ SDK Manager** с developer.garmin.com
2. В SDK Manager: поставить последний SDK (7.x) + образ устройства **Forerunner 955**
3. VS Code + расширение **Monkey C** (издатель Garmin)
4. Команда `Monkey C: Generate a Developer Key` — создаёт ключ подписи (без него не собрать)
5. Проверка: `Monkey C: Run App` → запускается симулятор с fr955

Пути после установки:
- SDK: `~/Library/Application Support/Garmin/ConnectIQ/Sdks/`
- Образы устройств: `~/Library/Application Support/Garmin/ConnectIQ/Devices/fr955/`
- В папке устройства лежит `simulator.json` — там точные лимиты памяти и размеры иконок для 955

## 4. Структура проекта

```
MIND/Garmin/mind-face/
├── manifest.xml            # только fr955, type="watchface", minApiLevel 3.2.0
├── monkey.jungle           # project.manifest = manifest.xml
├── resources/
│   ├── drawables/          # launcher_icon.png + drawables.xml
│   ├── strings/strings.xml
│   ├── properties.xml      # значения настроек по умолчанию
│   └── settings/settings.xml  # UI настроек в Garmin Connect
└── source/
    ├── MindFaceApp.mc      # AppBase: getInitialView(), onSettingsChanged()
    └── MindFaceView.mc     # WatchFace: onLayout / onUpdate / onPartialUpdate / onEnterSleep / onExitSleep
```

Вёрстку делаем **кодом**, без `layouts/layout.xml` — гибче для позиционирования и проще считать clip-регион для секунд.

## 5. Макет (260×260)

```
          ПН 31 АВГ            ← дата, FONT_TINY, приглушённый цвет, y≈44

        12:47 ⁵⁸               ← время FONT_NUMBER_HOT по центру (cy−6),
                                 секунды мелким шрифтом справа, акцентный цвет

   ШАГИ            ПУЛЬС       ← подписи FONT_XTINY, y≈cy+30
   8 421            62         ← значения FONT_SMALL, x = cx±52, y≈cy+50

       [███████░░] 78%         ← батарея: rounded rect, y≈cy+74,
                                 <15% — красный
```

Позиции считаем от `dc.getWidth()/getHeight()`, а не хардкодом — чтобы потом можно было добавить другие устройства.

## 6. Ключевые технические моменты

**Два режима отрисовки:**
- `onUpdate(dc)` — раз в минуту (и при пробуждении). Рисуем всё.
- `onPartialUpdate(dc)` — раз в секунду в low-power. Только секунды: `dc.setClip(x,y,w,h)` → `dc.clear()` → нарисовать → `dc.clearClip()`. Выход за бюджет по времени/памяти = система отключит partial update у циферблата.
- `onEnterSleep()` / `onExitSleep()` — переключение режима, в sleep не рисуем ничего «дорогого».

**Данные (все без дополнительных permissions):**
- Время: `System.getClockTime()`, формат 12/24 — `System.getDeviceSettings().is24Hour`
- Дата: `Time.Gregorian.info(Time.now(), FORMAT_MEDIUM)`
- Шаги/калории/этажи: `ActivityMonitor.getInfo()`
- Пульс: `Activity.getActivityInfo().currentHeartRate`, fallback — `ActivityMonitor.getHeartRateHistory(1, true)`
- Батарея: `System.getSystemStats().battery`
- Погода (позже): `Toybox.Weather.getCurrentConditions()` — данные из кеша телефона, CIQ 3.2+

**MIP-экран:** сплошные насыщенные цвета, контраст текст/фон максимальный, антиалиасинг включаем через `if (dc has :setAntiAlias)`.

**Настройки** (`properties.xml` + `settings/settings.xml`), правятся в Garmin Connect на телефоне:
- акцентный цвет (список)
- показывать/скрывать секунды
- что в левом/правом слоте (шаги / калории / этажи / Body Battery)

## 7. Сборка, запуск, установка

- Симулятор: в VS Code `Monkey C: Run App` (Cmd+Shift+P)
- Сборка релиза: `Monkey C: Build for Device` → получаем `.prg`
- На часы: подключить FR955 по USB, скопировать `.prg` в `GARMIN/APPS/`, отключить, выбрать циферблат в меню часов. Аккаунт и Store для личного использования не нужны.

## 8. Публикация (опционально)

Connect IQ Store: бесплатный аккаунт разработчика, загрузка `.iq` пакета (`Monkey C: Export Project`), скриншоты из симулятора, ревью несколько дней.

## 9. Порядок работ

1. Установить SDK + образ fr955 + developer key ← **блокирует всё остальное**
2. Посмотреть сэмплы в `Sdks/<ver>/samples/`, выбрать базу
3. Собрать скелет `mind-face`, добиться запуска в симуляторе с временем и датой
4. Добавить шаги, пульс, батарею
5. Секунды через `onPartialUpdate` + проверка бюджета в симуляторе (Simulation → Watch Face Diagnostics)
6. Настройки (цвет, слоты данных)
7. Залить на часы, поносить день, поправить читаемость
8. (Опционально) погода / Body Battery / иконка уведомлений

## 10. Открытые вопросы

- Какой акцентный цвет по умолчанию?
- Шрифты: системные (бесплатно по памяти) или свои bitmap-шрифты (красивее, но занимают память и нужно генерить под 260×260)?
- Нужен ли режим «ночь» (инверсия/приглушение) по времени суток?
