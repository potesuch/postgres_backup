#!/bin/bash

set -e

VERSION="1.0.0"
INSTALL_DIR="/opt/pg-backup"
BACKUP_DIR="$INSTALL_DIR/backups"
CONFIG_FILE="$INSTALL_DIR/config.env"
SCRIPT_PATH="$INSTALL_DIR/pg-backup.sh"
SCRIPT_RUN_PATH="$(realpath "$0")"
SCRIPT_REPO_URL="https://raw.githubusercontent.com/potesuch/postgres_backup/main/backup.sh"
RETAIN_DAYS=7

# Цвета
if [[ -t 0 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    CYAN=$'\e[36m'
    RESET=$'\e[0m'
    BOLD=$'\e[1m'
else
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    RESET=""
    BOLD=""
fi

print_msg() {
    local type="$1"
    local msg="$2"
    local color="$RESET"
    
    case "$type" in
        "INFO") color="$CYAN" ;;
        "SUCCESS") color="$GREEN" ;;
        "WARN") color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
    esac
    
    echo -e "${color}[$type]${RESET} $msg"
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_CONTAINER="$DB_CONTAINER"
DB_USER="$DB_USER"
CRON_TIME="$CRON_TIME"
EOF
    chmod 600 "$CONFIG_FILE"
    print_msg "SUCCESS" "Конфигурация сохранена"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        print_msg "SUCCESS" "Конфигурация загружена"
    else
        if [[ "$SCRIPT_RUN_PATH" != "$SCRIPT_PATH" ]]; then
            print_msg "INFO" "Конфигурация не найдена. Скрипт запущен из временного расположения."
            print_msg "INFO" "Перемещаем скрипт в основной каталог установки: ${BOLD}${SCRIPT_PATH}${RESET}..."
            mkdir -p "$INSTALL_DIR" || { print_msg "ERROR" "Не удалось создать каталог установки ${BOLD}${INSTALL_DIR}${RESET}. Проверьте права доступа."; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_msg "ERROR" "Не удалось создать каталог для бэкапов ${BOLD}${BACKUP_DIR}${RESET}. Проверьте права доступа."; exit 1; }

            if mv "$SCRIPT_RUN_PATH" "$SCRIPT_PATH"; then
                chmod +x "$SCRIPT_PATH"
                clear
                print_msg "SUCCESS" "Скрипт успешно перемещен в ${BOLD}${SCRIPT_PATH}${RESET}."
                print_msg "INFO" "Перезапускаем скрипт из нового расположения для завершения настройки."
                exec "$SCRIPT_PATH" "$@"
                exit 0
            else
                print_msg "ERROR" "Не удалось переместить скрипт в ${BOLD}${SCRIPT_PATH}${RESET}. Проверьте права доступа."
                exit 1
            fi
        else
            print_msg "INFO" "Создание новой конфигурации..."
            
            echo ""
            print_msg "INFO" "Создайте бота в ${CYAN}@BotFather${RESET}"
            read -rp "Введите Bot Token: " BOT_TOKEN
            
            echo ""
            print_msg "INFO" "ID можно узнать у ${CYAN}@username_to_id_bot${RESET}"
            read -rp "Введите Chat ID: " CHAT_ID
            
            echo ""
            read -rp "Введите название контейнера БД (по умолчанию postgres): " DB_CONTAINER
            DB_CONTAINER="${DB_CONTAINER:-postgres}"
            
            echo ""
            read -rp "Введите имя пользователя БД (по умолчанию postgres): " DB_USER
            DB_USER="${DB_USER:-postgres}"
            
            CRON_TIME=""
            
            mkdir -p "$INSTALL_DIR" "$BACKUP_DIR"
            save_config
        fi
    fi
}

send_telegram() {
    local msg="$1"
    local escaped_msg=$(echo "$msg" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/_/\\_/g' \
        -e 's/\*/\\*/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/(/\\(/g' \
        -e 's/)/\\)/g' \
        -e 's/~/\\~/g' \
        -e 's/`/\\`/g' \
        -e 's/>/\\>/g' \
        -e 's/#/\\#/g' \
        -e 's/+/\\+/g' \
        -e 's/-/\\-/g' \
        -e 's/=/\\=/g' \
        -e 's/|/\\|/g' \
        -e 's/{/\\{/g' \
        -e 's/}/\\}/g' \
        -e 's/\./\\./g' \
        -e 's/!/\\!/g')
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$escaped_msg" \
        -d parse_mode="MarkdownV2" > /dev/null
}

send_telegram_file() {
    local file="$1"
    local caption="$2"
    local escaped_caption=$(echo "$caption" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/_/\\_/g' \
        -e 's/\*/\\*/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/(/\\(/g' \
        -e 's/)/\\)/g' \
        -e 's/~/\\~/g' \
        -e 's/`/\\`/g' \
        -e 's/>/\\>/g' \
        -e 's/#/\\#/g' \
        -e 's/+/\\+/g' \
        -e 's/-/\\-/g' \
        -e 's/=/\\=/g' \
        -e 's/|/\\|/g' \
        -e 's/{/\\{/g' \
        -e 's/}/\\}/g' \
        -e 's/\./\\./g' \
        -e 's/!/\\!/g')
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        -F document=@"$file" \
        -F caption="$escaped_caption" \
        -F parse_mode="MarkdownV2" > /dev/null
}

create_backup() {
    print_msg "INFO" "Создание бэкапа БД..."
    print_msg "INFO" "pg_dumpall НЕ блокирует БД, работа продолжается"
    
    if ! docker inspect "$DB_CONTAINER" > /dev/null 2>&1; then
        print_msg "ERROR" "Контейнер $DB_CONTAINER не найден"
        send_telegram "❌ Ошибка: контейнер $DB_CONTAINER не найден"
        exit 1
    fi
    
    local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    local backup_file="$BACKUP_DIR/db_backup_${timestamp}.sql.gz"
    
    if ! docker exec -t "$DB_CONTAINER" pg_dumpall -c -U "$DB_USER" | gzip -9 > "$backup_file"; then
        print_msg "ERROR" "Ошибка создания дампа"
        send_telegram "❌ Ошибка создания бэкапа БД"
        exit 1
    fi
    
    print_msg "SUCCESS" "Бэкап создан: $backup_file"
    
    local size=$(du -h "$backup_file" | awk '{print $1}')
    local date=$(date +'%Y-%m-%d %H:%M:%S')
    local caption=$'💾 *Бэкап PostgreSQL*\n📦 *Контейнер:* '"$DB_CONTAINER"$'\n📏 *Размер:* '"$size"$'\n📅 *Дата:* '"$date"
    
    print_msg "INFO" "Отправка в Telegram..."
    if send_telegram_file "$backup_file" "$caption"; then
        print_msg "SUCCESS" "Бэкап отправлен в Telegram"
    else
        print_msg "ERROR" "Ошибка отправки в Telegram"
    fi
    
    find "$BACKUP_DIR" -name "db_backup_*.sql.gz" -mtime +$RETAIN_DAYS -delete
    print_msg "INFO" "Старые бэкапы удалены (старше $RETAIN_DAYS дней)"
}

restore_backup() {
    clear
    echo -e "${GREEN}${BOLD}Восстановление из бэкапа${RESET}"
    echo ""
    
    if ! compgen -G "$BACKUP_DIR/db_backup_*.sql.gz" > /dev/null; then
        print_msg "ERROR" "Бэкапы не найдены в $BACKUP_DIR"
        read -rp "Нажмите Enter..."
        return
    fi
    
    readarray -t backups < <(find "$BACKUP_DIR" -name "db_backup_*.sql.gz" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)
    
    echo "Доступные бэкапы:"
    local i=1
    for file in "${backups[@]}"; do
        local size=$(du -h "$file" | awk '{print $1}')
        echo " $i) $(basename "$file") [$size]"
        i=$((i+1))
    done
    echo ""
    echo " 0) Отмена"
    echo ""
    
    read -rp "${GREEN}[?]${RESET} Выберите бэкап: " choice
    
    if [[ "$choice" == "0" || -z "$choice" ]]; then
        return
    fi
    
    local selected="${backups[$((choice-1))]}"
    
    if [[ ! -f "$selected" ]]; then
        print_msg "ERROR" "Неверный выбор"
        read -rp "Нажмите Enter..."
        return
    fi
    
    echo ""
    print_msg "WARN" "${YELLOW}ВНИМАНИЕ!${RESET} Все данные в БД будут удалены!"
    read -rp "Введите ${GREEN}${BOLD}Y${RESET} для подтверждения: " confirm
    
    if [[ "${confirm,,}" != "y" ]]; then
        print_msg "INFO" "Отменено"
        read -rp "Нажмите Enter..."
        return
    fi
    
    echo ""
    print_msg "INFO" "Восстановление из $(basename "$selected")..."
    
    local temp_file="${selected%.gz}"
    gunzip -c "$selected" > "$temp_file"
    
    if docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d postgres < "$temp_file" 2>&1 | grep -v "already exists\|does not exist"; then
        print_msg "SUCCESS" "База данных восстановлена!"
        send_telegram $'✅ *Восстановление завершено*\n📦 Контейнер: '"$DB_CONTAINER"
    else
        print_msg "ERROR" "Ошибка восстановления"
        send_telegram "❌ Ошибка восстановления БД"
    fi
    
    rm -f "$temp_file"
    
    echo ""
    read -rp "Нажмите Enter..."
}

setup_cron() {
    if [[ $EUID -ne 0 ]]; then
        print_msg "ERROR" "Требуются права root для настройки cron"
        read -rp "Нажмите Enter..."
        return
    fi
    
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Настройка автоматического бэкапа${RESET}"
        echo ""
        
        if [[ -n "$CRON_TIME" ]]; then
            print_msg "INFO" "Текущая настройка: ${BOLD}$CRON_TIME${RESET}"
        else
            print_msg "INFO" "Автоматический бэкап ${BOLD}выключен${RESET}"
        fi
        
        echo ""
        echo "1. Ежечасно"
        echo "2. Ежедневно"
        echo "3. Выбрать время (например: 08:00 14:00 20:00)"
        echo "4. Выключить автобэкап"
        echo ""
        echo "0. Назад"
        echo ""
        
        read -rp "${GREEN}[?]${RESET} Выберите: " choice
        echo ""
        
        case $choice in
            1)
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH backup" | crontab -
                (crontab -l 2>/dev/null; echo "@hourly $SCRIPT_PATH backup >> /var/log/pg_backup.log 2>&1") | crontab -
                CRON_TIME="@hourly"
                save_config
                print_msg "SUCCESS" "Установлен ежечасный бэкап"
                ;;
            2)
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH backup" | crontab -
                (crontab -l 2>/dev/null; echo "@daily $SCRIPT_PATH backup >> /var/log/pg_backup.log 2>&1") | crontab -
                CRON_TIME="@daily"
                save_config
                print_msg "SUCCESS" "Установлен ежедневный бэкап"
                ;;
            3)
                echo "Введите время через пробел (например: 08:00 14:00 20:00):"
                read -rp "Время: " times
                
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH backup" | crontab -
                
                IFS=' ' read -ra arr <<< "$times"
                for t in "${arr[@]}"; do
                    if [[ $t =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
                        local hour=$((10#${BASH_REMATCH[1]}))
                        local min=$((10#${BASH_REMATCH[2]}))
                        (crontab -l 2>/dev/null; echo "$min $hour * * * $SCRIPT_PATH backup >> /var/log/pg_backup.log 2>&1") | crontab -
                    fi
                done
                
                CRON_TIME="$times"
                save_config
                print_msg "SUCCESS" "Установлено время: $times"
                ;;
            4)
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH backup" | crontab -
                CRON_TIME=""
                save_config
                print_msg "SUCCESS" "Автобэкап выключен"
                ;;
            0) break ;;
            *) print_msg "ERROR" "Неверный выбор" ;;
        esac
        
        echo ""
        read -rp "Нажмите Enter..."
    done
}

edit_settings() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Настройки${RESET}"
        echo ""
        echo "1. Bot Token: ${BOLD}${BOT_TOKEN:0:10}...${RESET}"
        echo "2. Chat ID: ${BOLD}$CHAT_ID${RESET}"
        echo "3. Контейнер БД: ${BOLD}$DB_CONTAINER${RESET}"
        echo "4. Пользователь БД: ${BOLD}$DB_USER${RESET}"
        echo ""
        echo "0. Назад"
        echo ""
        
        read -rp "${GREEN}[?]${RESET} Что изменить: " choice
        echo ""
        
        case $choice in
            1)
                read -rp "Новый Bot Token: " BOT_TOKEN
                save_config
                print_msg "SUCCESS" "Token обновлен"
                ;;
            2)
                read -rp "Новый Chat ID: " CHAT_ID
                save_config
                print_msg "SUCCESS" "Chat ID обновлен"
                ;;
            3)
                read -rp "Название контейнера: " DB_CONTAINER
                save_config
                print_msg "SUCCESS" "Контейнер обновлен"
                ;;
            4)
                read -rp "Имя пользователя БД: " DB_USER
                save_config
                print_msg "SUCCESS" "Пользователь обновлен"
                ;;
            0) break ;;
            *) print_msg "ERROR" "Неверный выбор" ;;
        esac
        
        echo ""
        read -rp "Нажмите Enter..."
    done
}

update_script() {
    print_msg "INFO" "Проверка обновлений..."
    echo ""
    
    if [[ "$EUID" -ne 0 ]]; then
        print_msg "ERROR" "Требуются права root для обновления"
        read -rp "Нажмите Enter..."
        return
    fi

    local TEMP_SCRIPT=$(mktemp)
    
    if ! curl -fsSL "$SCRIPT_REPO_URL" -o "$TEMP_SCRIPT"; then
        print_msg "ERROR" "Не удалось загрузить обновление"
        rm -f "$TEMP_SCRIPT"
        read -rp "Нажмите Enter..."
        return
    fi

    local REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_SCRIPT" | cut -d'"' -f2)
    
    if [[ -z "$REMOTE_VERSION" ]]; then
        print_msg "ERROR" "Не удалось определить версию"
        rm -f "$TEMP_SCRIPT"
        read -rp "Нажмите Enter..."
        return
    fi

    print_msg "INFO" "Текущая версия: ${BOLD}${YELLOW}${VERSION}${RESET}"
    print_msg "INFO" "Доступная версия: ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}"
    echo ""

    if [[ "$VERSION" == "$REMOTE_VERSION" ]]; then
        print_msg "INFO" "У вас установлена актуальная версия"
        rm -f "$TEMP_SCRIPT"
        read -rp "Нажмите Enter..."
        return
    fi

    read -rp "Обновить до версии ${BOLD}${REMOTE_VERSION}${RESET}? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: " confirm
    echo ""

    if [[ "${confirm,,}" != "y" ]]; then
        print_msg "WARN" "Обновление отменено"
        rm -f "$TEMP_SCRIPT"
        read -rp "Нажмите Enter..."
        return
    fi

    local BACKUP_SCRIPT="${SCRIPT_PATH}.bak.$(date +%s)"
    cp "$SCRIPT_PATH" "$BACKUP_SCRIPT"
    
    if mv "$TEMP_SCRIPT" "$SCRIPT_PATH"; then
        chmod +x "$SCRIPT_PATH"
        print_msg "SUCCESS" "Скрипт обновлен до версии ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}"
        echo ""
        print_msg "INFO" "Перезапуск скрипта..."
        read -rp "Нажмите Enter..."
        exec "$SCRIPT_PATH" "$@"
        exit 0
    else
        print_msg "ERROR" "Ошибка обновления. Восстановление из резервной копии..."
        mv "$BACKUP_SCRIPT" "$SCRIPT_PATH"
        rm -f "$TEMP_SCRIPT"
        read -rp "Нажмите Enter..."
        return
    fi
}

setup_symlink() {
    if [[ "$EUID" -ne 0 ]]; then
        return
    fi
    
    local SYMLINK_PATH="/usr/local/bin/postgres-backup"
    
    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        return 0
    fi
    
    rm -f "$SYMLINK_PATH"
    if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH" 2>/dev/null; then
        print_msg "SUCCESS" "Команда ${BOLD}postgres-backup${RESET} доступна"
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}PostgreSQL Backup Tool v$VERSION${RESET}"
        echo ""
        echo "1. Создать бэкап сейчас"
        echo "2. Восстановить из бэкапа"
        echo "3. Настроить автоматический бэкап"
        echo "4. Изменить настройки"
        echo "5. Обновить скрипт"
        echo ""
        echo "0. Выход"
        echo ""
        
        read -rp "${GREEN}[?]${RESET} Выберите: " choice
        echo ""
        
        case $choice in
            1) 
                create_backup
                read -rp "Нажмите Enter..."
                ;;
            2) restore_backup ;;
            3) setup_cron ;;
            4) edit_settings ;;
            5) update_script ;;
            0) exit 0 ;;
            *) 
                print_msg "ERROR" "Неверный выбор"
                read -rp "Нажмите Enter..."
                ;;
        esac
    done
}

# Проверка jq
if ! command -v jq &> /dev/null; then
    print_msg "INFO" "Установка jq..."
    apt-get update -qq && apt-get install -y jq -qq
fi

# Запуск
if [[ -z "$1" ]]; then
    load_config
    setup_symlink
    main_menu
elif [[ "$1" == "backup" ]]; then
    load_config
    create_backup
elif [[ "$1" == "restore" ]]; then
    load_config
    restore_backup
else
    print_msg "ERROR" "Использование: $0 [backup|restore]"
    exit 1
fi
