#!/bin/sh

# Цвета для текста
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # Сброс цвета

# Константы
BOT_DIR="/opt/vpnbot"
VENV_DIR="$BOT_DIR/venv"
REPO_OWNER="flathead"
REPO_NAME="kvas_bot"
SCRIPT_PATH="/usr/local/bin/vpnbot"
LOG_FILE="/var/log/vpnbot_install.log"
PYTHON_DEPS="aiogram asyncssh paramiko python-dotenv setuptools wheel"

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Пожалуйста, запустите скрипт с правами root.${NC}"
    exit 1
fi

# Приветствие
echo -e "${CYAN}${BOLD}====================================${NC}"
echo -e "${CYAN}${BOLD} УСТАНОВКА VPN БОТА ${NC}"
echo -e "${CYAN}${BOLD}====================================${NC}"

# Убедиться, что лог-файл доступен
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Установка необходимых пакетов
install_dependencies() {
    log "${YELLOW}Установка необходимых пакетов...${NC}"
    opkg update || {
        log "${RED}Ошибка: Невозможно обновить пакеты. Проверьте интернет.${NC}"
        exit 1
    }
    opkg install python3 || log "${RED}Python3 не установлен.${NC}"
    opkg install python3-pip || log "${RED}pip не установлен.${NC}"
    opkg install curl || log "${RED}curl не установлен.${NC}"
    opkg install daemonize || log "${RED}daemonize не установлен.${NC}"
    opkg install unzip || log "${RED}unzip не установлен.${NC}"
    pip3 install --upgrade pip || log "${RED}Ошибка обновления pip.${NC}"
    pip3 install virtualenv || log "${RED}Ошибка установки virtualenv.${NC}"
    log "${GREEN}Все зависимости успешно установлены.${NC}"
}

# Получение информации о последнем релизе
get_latest_release_info() {
    local release_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
    curl -sH "Accept: application/vnd.github.v3+json" "$release_url"
}

# Скачивание и распаковка релиза
download_and_extract_release() {
    log "${YELLOW}Получение информации о последнем релизе...${NC}"
    local release_info
    release_info=$(get_latest_release_info)

    local zipball_url
    zipball_url=$(echo "$release_info" | grep -oP '"zipball_url":\s*"\K[^"]+')
    if [ -z "$zipball_url" ]; then
        log "${RED}Ошибка: Не удалось получить ссылку на архив релиза.${NC}"
        exit 1
    fi

    local release_name
    release_name=$(echo "$release_info" | grep -oP '"tag_name":\s*"\K[^"]+')

    log "${YELLOW}Скачивание релиза $release_name...${NC}"
    curl -L -o "/tmp/${release_name}.zip" "$zipball_url" || {
        log "${RED}Ошибка скачивания релиза.${NC}"
        exit 1
    }

    log "${YELLOW}Распаковка архива...${NC}"
    unzip -o "/tmp/${release_name}.zip" -d "/tmp/" || {
        log "${RED}Ошибка распаковки.${NC}"
        exit 1
    }
    rm "/tmp/${release_name}.zip"

    local extracted_folder
    extracted_folder=$(find "/tmp" -mindepth 1 -maxdepth 1 -type d -name "${REPO_OWNER}-${REPO_NAME}-*" | head -n 1)
    if [ -z "$extracted_folder" ]; then
        log "${RED}Ошибка: Папка с релизом не найдена.${NC}"
        exit 1
    fi

    log "${YELLOW}Перенос содержимого в $BOT_DIR...${NC}"
    rm -rf "$BOT_DIR"
    mv "$extracted_folder" "$BOT_DIR"

    log "${GREEN}Релиз успешно скачан и распакован.${NC}"
}

# Создание виртуальной среды
create_virtualenv() {
    log "${YELLOW}Создание виртуальной среды...${NC}"
    python3 -m virtualenv "$VENV_DIR" || {
        log "${RED}Ошибка создания виртуальной среды.${NC}"
        exit 1
    }
    log "${GREEN}Виртуальная среда создана.${NC}"
}

# Установка Python-зависимостей из архива
install_requirements() {
    log "${YELLOW}Установка зависимостей Python...${NC}"
    . "$VENV_DIR/bin/activate"

    # Проверка наличия архива
    if [ ! -f "$BASE_DIR/deps.tar.gz" ]; then
        log "${RED}Архив зависимостей не найден!${NC}"
        deactivate
        exit 1
    fi

    # Создание временной папки для распаковки
    TEMP_DEPS_DIR="$VENV_DIR/temp_deps"
    mkdir -p "$TEMP_DEPS_DIR"

    # Распаковка архива
    log "${YELLOW}Распаковка архива зависимостей...${NC}"
    tar --strip-components=1 -xzf "$BASE_DIR/deps.tar.gz" -C "$TEMP_DEPS_DIR" || {
        log "${RED}Ошибка распаковки архива зависимостей.${NC}"
        rm -rf "$TEMP_DEPS_DIR"
        deactivate
        exit 1
    }

    # Установка зависимостей из временной папки
    log "${YELLOW}Установка зависимостей из локального архива...${NC}"
    pip install --no-cache-dir --no-index --find-links="$TEMP_DEPS_DIR" *.whl || {
        log "${RED}Ошибка установки зависимостей.${NC}"
        rm -rf "$TEMP_DEPS_DIR"
        deactivate
        exit 1
    }

    # Очистка временных файлов
    rm -rf "$TEMP_DEPS_DIR"

    deactivate
    log "${GREEN}Зависимости Python успешно установлены.${NC}"
}

# Создание файла конфигурации .env
create_env_file() {
    log "${CYAN}${BOLD}Настраиваем файл конфигурации (.env)...${NC}"

    # Сбор обязательных данных
    while [ -z "$BOT_TOKEN" ]; do
        read -s -p "Введите токен бота (BOT_TOKEN) [обязательно]: " BOT_TOKEN
        echo
    done

    while [ -z "$ALLOWED_USERS" ]; do
        read -p "Введите ID разрешённых пользователей через запятую (ALLOWED_USERS) [обязательно]: " ALLOWED_USERS
    done

    while [ -z "$ROUTER_USER" ]; do
        read -p "Введите имя пользователя маршрутизатора (ROUTER_USER) [обязательно]: " ROUTER_USER
    done

    while [ -z "$ROUTER_PASS" ]; do
        read -s -p "Введите пароль маршрутизатора (ROUTER_PASS) [обязательно]: " ROUTER_PASS
        echo
    done

    # Сбор дополнительных данных
    read -p "Введите IP адрес маршрутизатора (ROUTER_IP) [опционально]: " ROUTER_IP
    read -p "Введите порт маршрутизатора (ROUTER_PORT) [опционально]: " ROUTER_PORT
    read -p "Введите уровень логирования (LOG) [опционально, по умолчанию INFO]: " LOG_LEVEL

    # Установим значение по умолчанию для LOG, если пользователь его не ввел
    LOG_LEVEL=${LOG_LEVEL:-INFO}

    # Создание файла .env
    cat <<EOF >"$BOT_DIR/.env"
BOT_TOKEN="$BOT_TOKEN"
ALLOWED_USERS="$ALLOWED_USERS"
ROUTER_IP="$ROUTER_IP"
ROUTER_PORT="$ROUTER_PORT"
ROUTER_USER="$ROUTER_USER"
ROUTER_PASS="$ROUTER_PASS"
LOG="$LOG_LEVEL"
EOF

    log "${GREEN}.env файл успешно создан!${NC}"
}

# Создание скрипта управления
setup_management_script() {
    log "${YELLOW}Добавление скрипта управления vpnbot...${NC}"
    ln -sf "$BOT_DIR/scripts/vpnbot.sh" "$SCRIPT_PATH"
    chmod +x "$BOT_DIR/scripts/vpnbot.sh"
    log "${GREEN}Скрипт управления установлен! Используйте 'vpnbot' для управления.${NC}"
}

# Основная установка
setup_bot() {
    log "${CYAN}Запуск установки VPN-бота...${NC}"
    install_dependencies
    download_and_extract_release
    create_virtualenv
    install_requirements
    create_env_file
    setup_management_script
    log "${GREEN}${BOLD}Установка завершена! Запускаю бота...${NC}"
    "$SCRIPT_PATH" start
    log "${GREEN}Бот успешно установлен и запущен.${NC}"
}

# Запуск установки
setup_bot
