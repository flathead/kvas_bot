#!/bin/sh

# Цвета для текста
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # Сброс цвета

# Константы
BOT_DIR="/opt/apps/vpnbot"
VENV_DIR="$BOT_DIR/venv"
REPO_OWNER="flathead"
REPO_NAME="kvas_bot"
SCRIPT_DIR="/opt/bin"
mkdir -p "$SCRIPT_DIR"
SCRIPT_PATH="$SCRIPT_DIR/vpnbot"
LOG_FILE="/var/log/vpnbot_install.log"

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Пожалуйста, запустите скрипт с правами root.${NC}"
    exit 1
fi

# Приветствие
echo -e "${CYAN}${BOLD}===============================${NC}"
echo -e "${CYAN}${BOLD}       УСТАНОВКА VPN БОТА      ${NC}"
echo -e "${CYAN}${BOLD}===============================${NC}"

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

    # Путь к архиву с зависимостями
    DEPS_ARCHIVE="$BOT_DIR/deps.tar.gz"

    # Проверка наличия архива
    if [ ! -f "$DEPS_ARCHIVE" ]; then
        log "${RED}Архив зависимостей не найден: $DEPS_ARCHIVE!${NC}"
        deactivate
        exit 1
    fi

    # Создание временной папки для распаковки
    TEMP_DEPS_DIR="$VENV_DIR/temp_deps"
    mkdir -p "$TEMP_DEPS_DIR"

    # Распаковка архива
    log "${YELLOW}Распаковка архива зависимостей...${NC}"
    # Использование совместимой команды tar
    tar -xzvf "$DEPS_ARCHIVE" -C "$TEMP_DEPS_DIR" || {
        log "${RED}Ошибка распаковки архива зависимостей.${NC}"
        rm -rf "$TEMP_DEPS_DIR"
        deactivate
        exit 1
    }

    # Установка зависимостей из распакованной папки
    log "${YELLOW}Установка зависимостей из локального архива...${NC}"
    find "$TEMP_DEPS_DIR" -name '*.whl' -exec pip install --no-cache-dir --no-index --find-links="$TEMP_DEPS_DIR" {} + || {
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

    # Получение последней версии бота
    local latest_release_info
    latest_release_info=$(get_latest_release_info)

    local latest_version
    latest_version=$(echo "$latest_release_info" | grep -oP '"tag_name":\s*"\K[^"]+')

    if [ -z "$latest_version" ]; then
        log "${RED}Не удалось определить последнюю версию. Убедитесь, что есть доступ к GitHub API.${NC}"
        exit 1
    fi

    # Сбор обязательных данных
    while [ -z "$BOT_TOKEN" ]; do
        read -s -p "Введите токен бота (BOT_TOKEN) [обязательно]: " BOT_TOKEN
        echo
    done

    while [ -z "$ALLOWED_USERS" ]; do
        read -p "Введите ID разрешённых пользователей через запятую (ALLOWED_USERS) [обязательно]: " ALLOWED_USERS
    done

    # Сбор дополнительных данных
    read -p "Введите уровень логирования (LOG) [опционально, по умолчанию INFO]: " LOG_LEVEL

    # Установим значение по умолчанию для LOG, если пользователь его не ввел
    LOG_LEVEL=${LOG_LEVEL:-INFO}

    # Создание .env файла с версией
    cat <<EOF >"$BOT_DIR/.env"
BOT_TOKEN="$BOT_TOKEN"
ALLOWED_USERS="$ALLOWED_USERS"
LOG="$LOG_LEVEL"
ENV="PROD"
VER="$latest_version"
EOF

    log "${GREEN}.env файл успешно создан!${NC}"
}

# Создание скрипта управления
setup_management_script() {
    log "${YELLOW}Добавление скрипта управления vpnbot...${NC}"
    # Копируем скрипт в целевую папку
    mkdir -p "$(dirname "$SCRIPT_PATH")"
    cp "$BOT_DIR/scripts/vpnbot.sh" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    log "${GREEN}Скрипт управления установлен! Используйте 'vpnbot' для управления.${NC}"

    # Проверяем, добавлен ли каталог в PATH, и добавляем при необходимости
    if ! echo "$PATH" | grep -q "$SCRIPT_DIR"; then
        echo "export PATH=\$PATH:$SCRIPT_DIR" >> /etc/profile
        export PATH=$PATH:$SCRIPT_DIR
        log "${GREEN}Каталог $SCRIPT_DIR добавлен в PATH.${NC}"
    fi

    # Создаём лог для бота, если не существует
    touch "$BOT_DIR/logs/router_bot.log"
    chmod 666 "$BOT_DIR/logs/router_bot.log"
}

setup_autostart() {
    log "${YELLOW}Добавление автозапуска бота через cron...${NC}"

    # Удаляем старые задания с упоминанием vpnbot
    crontab -l 2>/dev/null | grep -v "vpnbot start" | crontab -

    # Добавляем новое задание
    (crontab -l 2>/dev/null; echo "@reboot $SCRIPT_PATH start") | crontab -

    log "${GREEN}Автозапуск бота успешно настроен через cron.${NC}"

    # Добавляем в cron команду на ежедневную очистку логов в 2 утра
    (crontab -l 2>/dev/null; echo "0 2 * * * vpnbot clear") | crontab -

    log "${GREEN}Ежедневная очистка логов бота успешно настроена через cron.${NC}"
}

# Справочная информация
show_help() {
    echo -e "${CYAN}${BOLD}Использование:${NC} ./install_bot.sh [команда]"
    echo -e "${CYAN}${BOLD}Доступные команды:${NC}"
    echo "  install_dependencies         Установить системные зависимости"
    echo "  download_and_extract_release Скачать и распаковать последнюю версию бота"
    echo "  create_virtualenv            Создать виртуальную среду Python"
    echo "  install_requirements         Установить Python-зависимости из локального архива"
    echo "  create_env_file              Создать файл конфигурации (.env)"
    echo "  setup_management_script      Настроить скрипт управления ботом"
    echo "  setup_autostart              Настроить автозапуск бота"
    echo "  setup_bot                    Выполнить полную установку (по умолчанию)"
    echo "  upgrade                      Обновить бота до последней версии"
    echo "  cleanup, --clean, -c         Очистить ненужные файлы, оставшиеся от установки"
    echo "  help, --help                 Показать эту справочную информацию"
}

# Очистка ненужных файлов
cleanup() {
    log "${YELLOW}Удаляю временные файлы...${NC}"
    rm "$BOT_DIR/deps.tar.gz"
    rm -rf "$BOT_DIR/scripts"
    rm "$BOT_DIR/requirements.txt"
    rm "$BOT_DIR/README.md"
    log "${GREEN}Временные файлы успешно удалены.${NC}"
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
    setup_autostart
    cleanup
    log "${GREEN}${BOLD}Установка завершена! Запускаю бота...${NC}"
    vpnbot start
    log "${GREEN}Бот успешно установлен и запущен.${NC}"
}

# Обновление бота
upgrade_bot() {
    log "${CYAN}Запуск обновления VPN-бота...${NC}"

    # Получение информации о последнем релизе
    local latest_release_info
    latest_release_info=$(get_latest_release_info)

    local latest_version
    latest_version=$(echo "$latest_release_info" | grep -oP '"tag_name":\s*"\K[^"]+')

    if [ -z "$latest_version" ]; then
        log "${RED}Не удалось получить последнюю версию. Проверьте соединение с GitHub API.${NC}"
        exit 1
    fi

    # Проверка текущей версии
    local current_version="Не установлена"
    if [ -f "$BOT_DIR/.env" ]; then
        current_version=$(grep -oP '^VER="\K[^"]+' "$BOT_DIR/.env" || echo "Не установлена")
    fi

    # Проверка на совпадение версий
    if [ "$current_version" = "$latest_version" ]; then
        log "${GREEN}Версия $current_version уже актуальна. Обновление не требуется.${NC}"
        exit 0
    fi

    log "${YELLOW}Текущая версия: $current_version${NC}"
    log "${YELLOW}Доступна новая версия: $latest_version${NC}"

    # Подтверждение от пользователя
    echo -e "${YELLOW}Вы хотите обновить до версии $latest_version? (y/n): ${NC}"
    read -r confirm
    if [ "$confirm" != "y" ]; then
        log "${RED}Обновление отменено пользователем.${NC}"
        exit 0
    fi

    # Резервное копирование .env
    local env_backup="/opt/tmp/.env"
    mkdir -p "/opt/tmp"
    if [ -f "$BOT_DIR/.env" ]; then
        cp "$BOT_DIR/.env" "$env_backup"
    fi

    # Удаляем старую версию
    log "${CYAN}Удаляем старую версию бота...${NC}"
    vpnbot stop
    sleep 5
    rm -rf "$BOT_DIR"
    rm -f "/var/run/vpnbot.pid"
    rm -f "$SCRIPT_PATH"

    # Загрузка и установка новой версии
    download_and_extract_release
    create_virtualenv
    install_requirements
    setup_management_script
    setup_autostart
    cleanup

    # Восстановление .env
    if [ -f "$env_backup" ]; then
        mv "$env_backup" "$BOT_DIR/.env"
        rm -f "$env_backup"

        # Обновление версии в .env
        sed -i "s/^VER=.*/VER=\"$latest_version\"/" "$BOT_DIR/.env"
    else
        # Создание нового .env, если бэкапа не существует
        сreate_env_file
    fi

    log "${GREEN}${BOLD}Обновление завершено! Запускаю бота...${NC}"
    vpnbot start
    log "${GREEN}Бот успешно обновлен и запущен.${NC}"
}

# Обработка аргументов
case "$1" in
    "install_dependencies")
        install_dependencies
        ;;
    "download_and_extract_release")
        download_and_extract_release
        ;;
    "create_virtualenv")
        create_virtualenv
        ;;
    "install_requirements")
        install_requirements
        ;;
    "create_env_file")
        create_env_file
        ;;
    "setup_management_script")
        setup_management_script
        ;;
    "setup_autostart")
        setup_autostart
        ;;
    "cleanup" | "--clean" | "-c")
        cleanup
        ;;
    "setup_bot" | "install" | "--setup" | "--install" | "")
        setup_bot
        ;;
    "upgrade")
        upgrade_bot
        ;;
    "help" | "--help")
        show_help
        ;;
    "post_install_info")
        show_post_install_info
        ;;
    *)
        echo -e "${RED}Неизвестная команда: $1${NC}"
        echo "Используйте './install_bot.sh help' для справки."
        exit 1
        ;;
esac