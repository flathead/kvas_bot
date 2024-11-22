#!/bin/bash

# Цвета для текста
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # Сброс цвета

# Переменные
BOT_DIR="/apps/vpnbot"
VENV_DIR="$BOT_DIR/venv"
REPO_URL="https://github.com/flathead/kvas_bot.git"
SUPERVISOR_CONF="/etc/supervisor/conf.d/vpnbot.conf"
SCRIPT_PATH="/usr/local/bin/vpnbot"
LOG_FILE="/var/log/vpnbot_install.log"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Пожалуйста, запустите скрипт с правами root.${NC}"
    exit 1
fi

if [ -f "$SUPERVISOR_CONF" ]; then
    echo -e "${YELLOW}Обнаружена старая версия бота. Остановить и удалить? (y/n): ${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" == "y" ]; then
        supervisorctl stop vpnbot
        rm -rf "$BOT_DIR" "$SUPERVISOR_CONF"
        echo -e "${GREEN}Старая версия успешно удалена.${NC}"
    fi
fi

# Приветствие
echo -e "${CYAN}${BOLD}====================================${NC}"
echo -e "${CYAN}${BOLD} УСТАНОВКА VPN БОТА НА РОУТЕР ${NC}"
echo -e "${CYAN}${BOLD}====================================${NC}"

# Проверка наличия КВАС
if ! command -v kvas &>/dev/null; then
    echo -e "${RED}Утилита КВАС не найдена.${NC}"
    echo -e "${YELLOW}Пожалуйста, установите КВАС, следуя гайду:${NC}"
    echo -e "${CYAN}$KVAS_GUIDE${NC}"
    echo -e "${RED}Установка прервана. Утилита КВАС необходима для работы.${NC}"
    exit 1
else
    echo -e "${GREEN}Утилита КВАС найдена.${NC}"
fi

# Проверка и установка необходимых пакетов
install_dependencies() {
    echo -e "${YELLOW}Установка необходимых пакетов...${NC}"
    opkg update
    opkg install python3 python3-pip git python3-supervisor
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка установки зависимостей. Проверьте подключение к интернету.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Все зависимости успешно установлены.${NC}"
}

# Клонирование репозитория
clone_repo() {
    if [ ! -d "$BOT_DIR" ]; then
        echo -e "${YELLOW}Клонирование репозитория...${NC}"
        git clone "$REPO_URL" "$BOT_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Ошибка клонирования репозитория. Проверьте URL и подключение к интернету.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Репозиторий уже существует. Обновляю...${NC}"
        cd "$BOT_DIR" && git pull
    fi
}

# Создание виртуальной среды
create_virtualenv() {
    echo -e "${YELLOW}Создание виртуальной среды Python...${NC}"
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Ошибка создания виртуальной среды. Проверьте доступность Python 3.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Виртуальная среда уже существует.${NC}"
    fi
}

# Установка Python-зависимостей
install_requirements() {
    echo -e "${YELLOW}Установка зависимостей Python...${NC}"
    source "$VENV_DIR/bin/activate"
    cd "$BOT_DIR" || exit 1
    pip install --upgrade pip
    pip install -r requirements.txt
    deactivate
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка установки зависимостей. Проверьте наличие файла requirements.txt.${NC}"
        exit 1
    fi
}

# Настройка supervisord
setup_supervisor() {
    echo -e "${YELLOW}Настройка supervisord...${NC}"
    if [ ! -f "$SUPERVISOR_CONF" ]; then
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
    else
        echo -e "${GREEN}Конфигурация supervisord уже существует.${NC}"
    fi
    supervisord
    supervisorctl reread
    supervisorctl update
}

# Создание скрипта управления
setup_management_script() {
    echo -e "${YELLOW}Добавление скрипта управления vpnbot...${NC}"
    cat <<EOF >"$SCRIPT_PATH"
#!/bin/bash
$BOT_DIR/scripts/vpnbot.sh "\$@"
EOF
    chmod +x "$SCRIPT_PATH"
    echo -e "${GREEN}Скрипт управления установлен! Используйте 'vpnbot' для управления.${NC}"
}

# Создание .env файла
create_env_file() {
    echo -e "${CYAN}${BOLD}Настраиваем файл конфигурации (.env)...${NC}"

    # Ввод токена бота
    while [ -z "$BOT_TOKEN" ]; do
        read -p "Введите токен бота (BOT_TOKEN) [обязательно]: " BOT_TOKEN
    done

    # Ввод ID разрешённых пользователей
    while [ -z "$ALLOWED_USERS" ]; do
        read -p "Введите ID разрешённых пользователей через запятую (ALLOWED_USERS) [обязательно]: " ALLOWED_USERS
    done

    # Ввод IP адреса роутера с значением по умолчанию
    read -p "Введите IP адрес роутера (ROUTER_IP) [по умолчанию: 192.168.1.1]: " ROUTER_IP
    ROUTER_IP=${ROUTER_IP:-192.168.1.1}

    # Ввод порта роутера с значением по умолчанию
    read -p "Введите порт роутера (ROUTER_PORT) [по умолчанию: 22]: " ROUTER_PORT
    ROUTER_PORT=${ROUTER_PORT:-22}

    # Ввод имени пользователя для SSH
    read -p "Введите имя пользователя для SSH (ROUTER_USER) [по умолчанию: admin]: " ROUTER_USER
    ROUTER_USER=${ROUTER_USER:-admin}

    # Ввод пароля для SSH с скрытым вводом
    read -s -p "Введите пароль для SSH (ROUTER_PASS) [по умолчанию: пусто]: " ROUTER_PASS
    echo
    ROUTER_PASS=${ROUTER_PASS:-""}

    # Ввод уровня логирования с значением по умолчанию
    read -p "Введите уровень логирования (DEBUG, INFO, WARNING, ERROR) (LOG) [по умолчанию: INFO]: " LOG_LEVEL
    LOG_LEVEL=${LOG_LEVEL:-INFO}

    echo -e "${YELLOW}Создаём файл конфигурации...${NC}"
    cat <<EOF >"$BOT_DIR/.env"
BOT_TOKEN="$BOT_TOKEN"
ALLOWED_USERS=$ALLOWED_USERS
ROUTER_IP="$ROUTER_IP"
ROUTER_PORT="$ROUTER_PORT"
ROUTER_USER="$ROUTER_USER"
ROUTER_PASS="$ROUTER_PASS"
LOG="$LOG_LEVEL"
EOF

    echo -e "${GREEN}.env файл успешно создан!${NC}"
}


# Основная установка
setup_bot() {
    echo -e "${CYAN}Запуск установки VPN-бота...${NC}"
    install_dependencies
    clone_repo
    create_virtualenv
    install_requirements
    create_env_file
    setup_supervisor
    setup_management_script
    echo -e "${GREEN}${BOLD}Установка завершена! Бот запущен и управляется через 'vpnbot'.${NC}"
}

# Запуск установки
setup_bot
