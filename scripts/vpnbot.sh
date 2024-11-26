#!/bin/sh

# Цвета для текста
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m'

# Параметры
BOT_DIR="/opt/apps/vpnbot"
VENV_DIR="$BOT_DIR/venv"
BOT_SCRIPT="$BOT_DIR/main.py"
PID_FILE="/var/run/vpnbot.pid"
LOG_FILE="/var/log/vpnbot.log"

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
    echo -e "  ${GREEN}logs${NC}      - Показывает логи бота"
    echo -e "  ${GREEN}clear${NC}     - Очищает логи бота"
    echo -e "  ${GREEN}help${NC}      - Показывает это сообщение"
    echo -e ""
    echo -e "${YELLOW}Аргументы:${NC}"
    echo -e "  ${GREEN}-h, --help${NC}  - Показывает это сообщение"
    echo -e "  ${GREEN}-l, --log${NC}   - Показывает логи бота"
    echo -e "  ${GREEN}-c, --clear${NC} - Очищает логи бота"
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
    daemonize -p "$PID_FILE" -o "$LOG_FILE" -e "$LOG_FILE" "$VENV_DIR/bin/python" "$BOT_SCRIPT"
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
    echo -e "${YELLOW}Запускаю полное обновление с переустановкой...${NC}"
    cd "/opt/tmp" || exit 1
    curl -sOfL https://github.com/flathead/kvas_bot/raw/main/scripts/install_bot.sh
    sh install_bot.sh setup_bot
}

# Вывести логи на экран
show_logs() {
    echo -e "${YELLOW}Показываю логи...${NC}"
    tail -f "$LOG_FILE"
}

# Очистка log-файла
clear_logs() {
    echo -e "${YELLOW}Очищаю логи...${NC}"
    echo "" >"$LOG_FILE"
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
logs | --log | -l)
    show_logs
    ;;
clear | --clear | -c)
    clear_logs
    ;;
help | -h | --help | "")
    print_help
    ;;
*)
    echo -e "${RED}Неизвестная команда: $1${NC}"
    print_help
    ;;
esac
