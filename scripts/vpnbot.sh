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
SUPERVISOR_CONF="/etc/supervisor/conf.d/vpnbot.conf"

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
    echo -e "  ${GREEN}upgrade${NC}   - Обновляет репозиторий и перезапускает бота"
    echo -e "  ${GREEN}help${NC}      - Показывает это сообщение"
    echo -e ""
    echo -e "${YELLOW}Аргументы:${NC}"
    echo -e "  ${GREEN}-h, --help${NC} - Показывает это сообщение"
}

# Проверка наличия supervisord
check_supervisor() {
    if ! command -v supervisord &>/dev/null; then
        echo -e "${YELLOW}Устанавливаю supervisord...${NC}"
        opkg update && opkg install python3-supervisor
        if [ $? -ne 0 ]; then
            echo -e "${RED}Ошибка установки supervisord. Проверьте подключение к интернету.${NC}"
            exit 1
        fi
        echo -e "${GREEN}supervisord успешно установлен!${NC}"
    fi
}

# Создание конфигурации supervisord
create_supervisor_config() {
    if [ ! -f "$SUPERVISOR_CONF" ]; then
        echo -e "${YELLOW}Создаю конфигурацию supervisord для бота...${NC}"
        cat <<EOF >"$SUPERVISOR_CONF"
[program:vpnbot]
command=$VENV_DIR/bin/python3 $BOT_DIR/bot.py
directory=$BOT_DIR
autostart=true
autorestart=true
stderr_logfile=/var/log/vpnbot.err.log
stdout_logfile=/var/log/vpnbot.out.log
EOF
        echo -e "${GREEN}Конфигурация supervisord создана: ${SUPERVISOR_CONF}${NC}"
    fi
}

# Запуск бота
start_bot() {
    check_supervisor
    create_supervisor_config
    echo -e "${YELLOW}Запускаю supervisord...${NC}"
    supervisord
    supervisorctl reread
    supervisorctl update
    supervisorctl start vpnbot
    echo -e "${GREEN}Бот успешно запущен!${NC}"
}

# Остановка бота
stop_bot() {
    echo -e "${YELLOW}Останавливаю бота...${NC}"
    supervisorctl stop vpnbot
    echo -e "${GREEN}Бот успешно остановлен!${NC}"
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
    echo -e "${YELLOW}Перезапускаю бота...${NC}"
    stop_bot
    start_bot
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
