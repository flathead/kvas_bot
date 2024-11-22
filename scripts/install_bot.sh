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
SCRIPT_PATH="/usr/local/bin/vpnbot"
LOG_FILE="/var/log/vpnbot_install.log"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Пожалуйста, запустите скрипт с правами root.${NC}"
    exit 1
fi

# Приветствие
echo -e "${CYAN}${BOLD}====================================${NC}"
echo -e "${CYAN}${BOLD} УСТАНОВКА VPN БОТА НА РОУТЕР ${NC}"
echo -e "${CYAN}${BOLD}====================================${NC}"

# Проверка и установка необходимых пакетов
install_dependencies() {
    echo -e "${YELLOW}Установка необходимых пакетов...${NC}"
    opkg update
    opkg install python3 python3-pip git daemonize
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

    echo -e "${YELLOW}Создаём файл конфигурации...${NC}"
    cat <<EOF >"$BOT_DIR/.env"
BOT_TOKEN="$BOT_TOKEN"
ALLOWED_USERS=$ALLOWED_USERS
EOF

    echo -e "${GREEN}.env файл успешно создан!${NC}"
}

# Создание скрипта управления
setup_management_script() {
    echo -e "${YELLOW}Добавление скрипта управления vpnbot...${NC}"
    ln -sf "$BOT_DIR/scripts/vpnbot.sh" "$SCRIPT_PATH"
    chmod +x "$BOT_DIR/scripts/vpnbot.sh"
    echo -e "${GREEN}Скрипт управления установлен! Используйте 'vpnbot' для управления.${NC}"
}

# Основная установка
setup_bot() {
    echo -e "${CYAN}Запуск установки VPN-бота...${NC}"
    install_dependencies
    clone_repo
    create_virtualenv
    install_requirements
    create_env_file
    setup_management_script
    echo -e "${GREEN}${BOLD}Установка завершена! Запускаю бота...${NC}"
    vpnbot start
    echo -e "${GREEN}Бот успешно установлен и запущен.${NC}"
}

# Запуск установки
setup_bot
