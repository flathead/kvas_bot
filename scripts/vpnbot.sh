#!/bin/bash

# Цвета для текста
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # Сброс цвета

# Параметры
BOT_DIR="/apps/vpnbot"
VENV_DIR="$BOT_DIR/venv"
DAEMON_SCRIPT="/usr/local/bin/vpnbot_daemon"
PID_FILE="/var/run/vpnbot.pid"

# Заголовок
print_header() {
    echo -e "${CYAN}${BOLD}====================================${NC}"
    echo -e "${CYAN}${BOLD}    УПРАВЛЕНИЕ VPN БОТОМ ${NC}"
    echo -e "${CYAN}${BOLD}====================================${NC}"
}

# Помощь
print_help() {
    print_header
    echo -e "${GREEN}${BOLD}Использование:${NC} vpnbot [команда]"
    echo -e ""
    echo -e "${YELLOW}Доступные команды:${NC}"
    echo -e "  ${GREEN}start${NC}     - Запускает бота"
    echo -e "  ${GREEN}stop${NC}      - Останавливает бота"
    echo -e "  ${GREEN}restart${NC}   - Перезапускает бота"
    echo -e "  ${GREEN}upgrade${NC}   - Обновляет репозиторий и перезапускает бота"
    echo -e "  ${GREEN}help${NC}      - Показывает это сообщение"
    echo -e ""
    echo -e "${YELLOW}Аргументы:${NC}"
    echo -e "  ${GREEN}-h, --help${NC} - Показывает это сообщение"
}

# Проверка запущенного процесса
is_bot_running() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Запуск бота
start_bot() {
    if is_bot_running; then
        echo -e "${YELLOW}Бот уже запущен.${NC}"
        return 0
    fi

    echo -e "${YELLOW}Запускаю бота...${NC}"
    $DAEMON_SCRIPT
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Бот успешно запущен!${NC}"
    else
        echo -e "${RED}Ошибка при запуске бота.${NC}"
    fi
}

# Остановка бота
stop_bot() {
    if ! is_bot_running; then
        echo -e "${YELLOW}Бот уже остановлен.${NC}"
        return 0
    fi

    echo -e "${YELLOW}Останавливаю бота...${NC}"
    kill "$(cat "$PID_FILE")" && rm -f "$PID_FILE"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Бот успешно остановлен!${NC}"
    else
        echo -e "${RED}Ошибка при остановке бота.${NC}"
    fi
}

# Перезапуск бота
restart_bot() {
    echo -e "${YELLOW}Перезапускаю бота...${NC}"
    stop_bot
    start_bot
}

# Обновление бота
upgrade_bot() {
    echo -e "${YELLOW}Обновляю репозиторий...${NC}"
    cd "$BOT_DIR" || exit 1
    git pull
    echo -e "${YELLOW}Устанавливаю обновлённые зависимости...${NC}"
    source "$VENV_DIR/bin/activate"
    pip install --upgrade -r requirements.txt
    deactivate
    restart_bot
    echo -e "${GREEN}Бот успешно обновлён и перезапущен!${NC}"
}

# Основная логика
case "$1" in
start)
    start_bot
    ;;
stop)
    stop_bot
    ;;
restart)
    restart_bot
    ;;
upgrade)
    upgrade_bot
    ;;
help | -h | --help | "")
    print_help
    ;;
*)
    echo -e "${RED}Неизвестная команда: $1${NC}"
    print_help
    ;;
esac
