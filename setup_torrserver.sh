#!/bin/sh

# Проверяем корректность введеного IP-адреса (IPv4/IPv6)
validate_ip() {
    ip=$1
    if printf "%s" "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        return 0  # IPv4
    elif printf "%s" "$ip" | grep -Eq '^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'; then
        return 0  # IPv6
    else
        printf "[ERROR]: Некорректный IP-адрес: %s\n" "$ip"
        return 1
    fi
}

# Смотрим архитектуру и выбираем дистрибутив
get_distrib() {
    arch=$(uname -m)
    case $arch in
        x86_64)    printf "TorrServer-linux-amd64\n" ;;
        i386|i686) printf "TorrServer-linux-386\n" ;;
        armv5*)    printf "TorrServer-linux-arm5\n" ;;
        armv7*)    printf "TorrServer-linux-arm7\n" ;;
        aarch64)   printf "TorrServer-linux-arm64\n" ;;
        mips)      printf "TorrServer-linux-mips\n" ;;
        mips64)    printf "TorrServer-linux-mips64\n" ;;
        mips64el)  printf "TorrServer-linux-mips64le\n" ;;
        mipsel)    printf "TorrServer-linux-mipsle\n" ;;
        *)
            printf "[ERROR]: Неподдерживаемая архитектура: %s\n" "$arch"
            exit 1
            ;;
    esac
}

# Проверка версии установленного Torrserver
get_version() {
    torrserver_bin=$1
    if [ -f "$torrserver_bin" ]; then
        version_output=$("$torrserver_bin" --version 2>&1)
        version=$(printf "%s" "$version_output" | tail -n 1 | sed -n 's/.*TorrServer \([^ ]*\).*/\1/p')
        if [ -n "$version" ]; then
            printf "%s" "$version"
            return 0
        else
            printf "[ERROR]: Не удалось получить версию установленного TorrServer.\n"
            return 1
        fi
    else
        printf ""
        return 1
    fi
}

# Проверяем latest версию на Github
get_latest_version() {
    latest_version=$(curl -s https://api.github.com/repos/YouROK/TorrServer/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p')
    if [ -n "$latest_version" ]; then
        printf "%s" "$latest_version"
        return 0
    else
        printf "[ERROR]: Не удалось получить версию через Github API.\n"
        return 1
    fi
}

# Создание каталогов и проверка наличия прав
create_directories() {
    dir=$1
    if ! mkdir -p "$dir" 2>/dev/null; then
        printf "[ERROR]: Невозможно создать директорию %s. Проверьте права доступа.\n" "$dir"
        exit 1
    fi
    if ! chmod 0700 "$dir" 2>/dev/null; then
        printf "[ERROR]: Не удалось установить права на директорию %s.\n" "$dir"
        exit 1
    fi
}

# Тело скрипта
main() {
    # Определяем дистриб
    DISTRIB=$(get_distrib)
    printf "Выбран дистрибутив: %s\n" "$DISTRIB"

    # Запрос ввода рабочей директории
    printf "Введите путь к рабочей директории [по умолчанию: /opt/torrserver]: "
    read -r WORKDIR
    WORKDIR=${WORKDIR:-/opt/torrserver}

    # Проверяем, что введенный путь абсолютный
    if ! printf "%s" "$WORKDIR" | grep -q '^/'; then
        printf "[ERROR]: Рабочая директория должна быть абсолютным путём.\n"
        exit 1
    fi

    # Создаем нужные каталоги
    LOGDIR="$WORKDIR/log"
    CONFDIR="$WORKDIR/conf"
    create_directories "$WORKDIR"
    create_directories "$LOGDIR"
    create_directories "$CONFDIR"

    # Спрашиваем имя бинаря и название сервиса
    printf "Введите имя бинарника [по умолчанию: torrserver]: "
    read -r BINARY_NAME
    BINARY_NAME=${BINARY_NAME:-torrserver}

    # Смотрим есть ли по указанному пути TorrServer
    if [ -f "$WORKDIR/$BINARY_NAME" ]; then
        printf "TorrServer уже установлен. Проверка версии...\n"
        INSTALLED_VERSION=$(get_version "$WORKDIR/$BINARY_NAME")
        if [ -z "$INSTALLED_VERSION" ]; then
            printf "[ERROR]: Не удалось определить установленную версию TorrServer.\n"
            exit 1
        fi
        printf "Установленная версия: %s\n" "$INSTALLED_VERSION"

        # Получаем последнюю версию через GitHub API
        LATEST_VERSION=$(get_latest_version)
        if [ -z "$LATEST_VERSION" ]; then
            printf "[ERROR]: Не удалось получить последнюю версию.\n"
            exit 1
        fi
        printf "Последняя версия: %s\n" "$LATEST_VERSION"

        # Сравниваем установленную и последнюю версии
        if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
            printf "Установленная версия TorrServer не требует обновления. Завершение работы скрипта.\n"
            exit 0
        else
            printf "Обнаружена новая версия TorrServer. Продолжение установки...\n"
        fi
    fi

    # Вводим IPV4 !!ИЛИ!! IPV6
    while true; do
        printf "Введите IP-адрес (IPv4 или IPv6) [по умолчанию: 192.168.1.1]: "
        read -r IP
        IP=${IP:-192.168.1.1}
        if validate_ip "$IP"; then
            break
        fi
    done

    # Добавляем параметр в зависимости от введенного адреса
    if printf "%s" "$IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        IP_PARAM="-4"
    else
        IP_PARAM="-6"
    fi

    # Вводим порт, на котором будет висеть сервис
    printf "Введите порт [по умолчанию: 8090]: "
    read -r PORT
    PORT=${PORT:-8090}

    # Проверяем что порт это число в диапазоне от 1 до 65535
    if ! printf "%s" "$PORT" | grep -Eq '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        printf "[ERROR]: Порт должен быть числом от 1 до 65535.\n"
        exit 1
    fi

    # Скачиваем TorrServer
    if ! cd "$WORKDIR"; then
        printf "[ERROR]: Не удалось перейти в директорию %s.\n" "$WORKDIR"
        exit 1
    fi

    printf "Загрузка TorrServer...\n"
    if ! wget -O "$BINARY_NAME" -q "https://github.com/YouROK/TorrServer/releases/latest/download/$DISTRIB"; then
        printf "[ERROR]: Не удалось загрузить TorrServer.\n"
        exit 1
    fi
    if ! chmod +x "$BINARY_NAME"; then
        printf "[ERROR]: Не удалось установить права на файл %s.\n" "$BINARY_NAME"
        exit 1
    fi

    # Создаем скрипт в /etc/init.d/
    INIT_SCRIPT="/etc/init.d/$BINARY_NAME"
    printf "Создание init-скрипта для TorrServer...\n"
    {
        printf '#!/bin/sh /etc/rc.common\n'
        printf 'START=99\n\n'
        printf 'USE_PROCD=1\n'
        printf 'IP=%s\n' "$IP"
        printf 'PORT=%s\n' "$PORT"
        printf 'WORKDIR=%s\n' "$WORKDIR"
        printf 'LOGDIR=%s\n' "$LOGDIR"
        printf 'CONFDIR=%s\n' "$CONFDIR"
        printf 'APP=%s/%s\n' "$WORKDIR" "$BINARY_NAME"
        printf '\n'
        printf 'start_service() {\n'
        printf '    procd_open_instance\n'
        printf '    procd_set_param command "$APP" %s "$IP" -p "$PORT" -d "$CONFDIR" -l "$LOGDIR"/error.log -w "$LOGDIR"/access.log\n' "$IP_PARAM"
        printf '    procd_close_instance\n'
        printf '}\n'
        printf 'reload_service() {\n'
        printf '    procd_send_signal "$APP"\n'
        printf '}\n'
        printf 'stop_service() {\n'
        printf '    killall -9 "$APP" 2>/dev/null\n'
        printf '}\n'
    } > "$INIT_SCRIPT" || {
        printf "[ERROR]: Не удалось создать init-скрипт.\n"
        exit 1
    }

    # Переменная для получения установленной версии
    ACTUAL_VERSION=$(get_version "$WORKDIR/$BINARY_NAME")

    # Накидываем права на init-скрипт
    if ! chmod +x "$INIT_SCRIPT"; then
        printf "[ERROR]: Не удалось установить права на init-скрипт.\n"
        exit 1
    fi

    # Стартуем службу и добавляем в автозагрузку
    printf "Включение и запуск службы TorrServer...\n"
    if ! "/etc/init.d/$BINARY_NAME" enable; then
        printf "[ERROR]: Не удалось включить службу TorrServer.\n"
        exit 1
    fi
    if ! "/etc/init.d/$BINARY_NAME" start; then
        printf "[ERROR]: Не удалось запустить службу TorrServer.\n"
        exit 1
    fi

    printf "Скрипт успешно завершен. TorrServer запущен и настроен.\n"
    printf " IP: %s\n Порт: %s\n Рабочая директория: %s\n Имя бинарника: %s\n Дистрибутив: %s\n Версия: %s\n" "$IP" "$PORT" "$WORKDIR" "$BINARY_NAME" "$DISTRIB" "$ACTUAL_VERSION"
}

# Старт основного скрипта
main