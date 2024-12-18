# 🌐 KVAS VPN Bot: Telegram-бот для управления списками сайтов на роутере

[![GitHub License](https://img.shields.io/github/license/flathead/kvas_bot?color=blue)](https://github.com/flathead/kvas_bot/blob/main/LICENSE)
[![Python Version](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)

## 🔍 Обзор

KVAS VPN Bot - это Telegram-бот для управления списками блокировки сайтов на роутерах с использованием [утилиты КВАС](https://github.com/qzeleza/kvas). С помощью этого бота вы можете легко добавлять, удалять и просматривать списки заблокированных сайтов прямо из Telegram.

## 🚨 Предварительные требования

### Необходимые компоненты
- Роутер Keenetic с SSH-доступом
- Установленный Shadowsocks. Можно использовать мой скрипт для быстрой установки: [Shadowsocks easy installer](https://github.com/flathead/shadowsocks-installer)
- Установленная [утилита КВАС](https://github.com/qzeleza/kvas)
- Токен Telegram-бота от [@BotFather](https://t.me/botfather)

### Поддерживаемые платформы
- Роутеры Keenetic c OpenWRT, установленном на USB-накопителе.

## 🛠 Установка

### Шаг 1: Установка КВАС
Перед установкой бота убедитесь, что КВАС установлен:
```bash
# Следуйте руководству по установке КВАС:
# https://github.com/qzeleza/kvas/wiki/Установка-пакета
```

### Шаг 2: Установка бота

Запустите скрипт установки:

```bash
hash -r && curl -sLf -o /opt/tmp/install_bot.sh https://github.com/flathead/kvas_bot/raw/main/scripts/install_bot.sh && sh /opt/tmp/install_bot.sh
```

### Шаг 3: Конфигурация
В процессе установки вам потребуется указать:

- Токен Telegram-бота<span style="color:red">*</span> (обязательно)
- ID разрешенных пользователей<span style="color:red">*</span> (обязательно)
- Уровень логирования (опционально)

## 🛠 Обновление

Для обновления, находясь на сервере, выполните команду `vpnbot upgrade`

## 📋 Команды бота

`/start`: Запуск бота и доступ к главному меню

## 🖥 Функциональность

- Добавление сайтов в список разблокировки
- Удаление сайтов из списка разблокировки
- Просмотр текущего списка разблокировки
- Перезагрузка роутера
- Контроль доступа пользователей

## 🔒 Функции безопасности

- Белый список пользователей
- Ведение журнала ошибок
- Управление таймаутами

## 📦 Зависимости

- Python 3.10+
- `python-telegram-bot`
- `asyncio`
- `python-dotenv`

## 🛡️ Рекомендации по безопасности

- Ограничьте доступ к боту доверенными пользователями Telegram
- Регулярно обновляйте бот и [утилиту КВАС](https://github.com/qzeleza/kvas)

## 🔧 Устранение неполадок

- Убедитесь, что КВАС установлен корректно
- Проверьте сетевое подключение
- Изучите файлы журнала для получения подробной информации об ошибках
  Логи можно найти в `/opt/apps/vpnbot/logs/router_bot.log`, ошибки при монтировании бота можно найти в `/var/log/vpnbot.log`

## 🤝 Вклад

Приветствуются вклады, сообщения об ошибках и предложения функций!

## 📞 Поддержка

По вопросам и поддержке, пожалуйста, создайте issue на GitHub

## 🙏 Благодарности

- [Проект КВАС](https://github.com/qzeleza/kvas)