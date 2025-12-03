#!/bin/bash

# === КОНФИГУРАЦИЯ ПО УМОЛЧАНИЮ ===
DEFAULT_DB_USER="netbox"
DEFAULT_DB_PASSWORD="123qweasdASD"
DEFAULT_ADMIN_EMAIL="admin@example.com"
DEFAULT_ADMIN_PASSWORD="123qweasdASD"

# Версии NetBox для выбора
NETBOX_VERSIONS=(
    "latest          (автоматически последняя)"
    "v4.4.7          (текущая стабильная)"
    "v4.4.6          (предыдущая стабильная)"
    "v4.4.5          (старая стабильная)"
    "v4.4.0          (начальная v4.4)"
    "v4.3.0          (стабильная v4.3)"
    "v4.2.0          (стабильная v4.2)"
    "v4.1.2          (стабильная v4.1)"
)
# ===================================================

set -e  # выход при ошибке

# Функция для проверки успешности выполнения
check_success() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ Ошибка: $1"
        exit 1
    fi
}

# Функция для запроса ввода с дефолтным значением
prompt_with_default() {
    local prompt="$1"
    local default_value="$2"
    local var_name="$3"
    
    echo -n "$prompt [$default_value]: "
    read -r input_value
    
    if [ -z "$input_value" ]; then
        input_value="$default_value"
        echo "Используется значение по умолчанию: $input_value"
    fi
    
    eval "$var_name='$input_value'"
}

# Функция для запроса пароля с проверкой
prompt_password() {
    local prompt="$1"
    local default_value="$2"
    local var_name="$3"
    local password1
    local password2
    
    while true; do
        # Запрашиваем первый раз
        echo -n "$prompt [по умолчанию: *****]: "
        read -rs password1
        echo
        
        # Если ничего не введено, используем значение по умолчанию
        if [ -z "$password1" ]; then
            password1="$default_value"
            echo "Используется пароль по умолчанию"
            break
        fi
        
        # Проверяем минимальную длину пароля
        if [ ${#password1} -lt 8 ]; then
            echo "⚠️  Пароль должен содержать минимум 8 символов"
            continue
        fi
        
        # Запрашиваем второй раз для проверки
        echo -n "Повторите пароль: "
        read -rs password2
        echo
        
        # Проверяем совпадение
        if [ "$password1" = "$password2" ]; then
            break
        else
            echo "❌ Пароли не совпадают. Попробуйте еще раз."
        fi
    done
    
    eval "$var_name='$password1'"
}

# Функция для запроса email с валидацией
prompt_email() {
    local prompt="$1"
    local default_value="$2"
    local var_name="$3"
    local email
    
    while true; do
        echo -n "$prompt [$default_value]: "
        read -r email
        
        if [ -z "$email" ]; then
            email="$default_value"
            echo "Используется email по умолчанию: $email"
            break
        fi
        
        # Простая проверка формата email
        if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "❌ Некорректный формат email. Попробуйте еще раз."
        fi
    done
    
    eval "$var_name='$email'"
}

# Функция для выбора версии NetBox
select_netbox_version() {
    echo ""
    echo "=== ВЫБОР ВЕРСИИ NETBOX ==="
    for i in "${!NETBOX_VERSIONS[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${NETBOX_VERSIONS[$i]}"
    done
    echo ""
    
    while true; do
        echo -n "Выберите версию NetBox (1-${#NETBOX_VERSIONS[@]}) [1]: "
        read -r choice
        
        # Если ничего не выбрано, используем latest
        if [ -z "$choice" ]; then
            choice=1
        fi
        
        # Проверяем, что выбор в пределах диапазона
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#NETBOX_VERSIONS[@]}" ]; then
            selected_version="${NETBOX_VERSIONS[$((choice-1))]}"
            
            # Если выбран "latest", получаем последнюю версию
            if [[ "$selected_version" == *"latest"* ]]; then
                echo "[*] Будет установлена последняя версия NetBox"
                NETBOX_VERSION="latest"
            else
                # Извлекаем номер версии (например, "v4.4.7")
                NETBOX_VERSION=$(echo "$selected_version" | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
                if [ -z "$NETBOX_VERSION" ]; then
                    echo "❌ Не удалось определить версию, используем latest"
                    NETBOX_VERSION="latest"
                else
                    echo "✅ Выбрана версия: $NETBOX_VERSION"
                fi
            fi
            break
        else
            echo "❌ Неверный выбор. Попробуйте еще раз."
        fi
    done
}

# Функция для вывода конфигурации
show_configuration() {
    echo ""
    echo "=== КОНФИГУРАЦИЯ УСТАНОВКИ ==="
    echo "Пользователь БД: $DB_USER"
    echo "Пароль БД: ***** (длина: ${#DB_PASSWORD} символов)"
    echo "Email администратора: $ADMIN_EMAIL"
    echo "Пароль администратора: ***** (длина: ${#ADMIN_PASSWORD} символов)"
    
    if [ "$NETBOX_VERSION" = "latest" ]; then
        echo "Версия NetBox: последняя доступная"
    else
        echo "Версия NetBox: $NETBOX_VERSION"
    fi
    echo "================================"
    echo ""
}

# Функция для получения последней версии NetBox
get_latest_netbox_version() {
    local latest_version
    # Получаем версию без лишних сообщений
    latest_version=$(curl -s https://api.github.com/repos/netbox-community/netbox/releases/latest 2>/dev/null | 
                    grep '"tag_name":' | 
                    sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$latest_version" ]; then
        echo "v4.4.7"  # fallback версия
    else
        echo "$latest_version"
    fi
}

# Функция для создания configuration.py
create_configuration() {
    local config_file="/opt/netbox/netbox/netbox/configuration.py"
    local secret_key="$1"
    
    echo "[*] Создание configuration.py..."
    echo "[*] Путь к конфигурации: $config_file"
    
    # Создаем директорию, если ее нет
    mkdir -p "$(dirname "$config_file")"
    
    # Создаем простой configuration.py
    cat > "$config_file" << EOF
import os
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ALLOWED_HOSTS = ['*']

DATABASE = {
    'NAME': 'netbox',
    'USER': '$DB_USER',
    'PASSWORD': '$DB_PASSWORD',
    'HOST': 'localhost',
    'PORT': '',
    'CONN_MAX_AGE': 300,
    'ENGINE': 'django.db.backends.postgresql',
}

REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 1,
        'SSL': False,
    },
}

SECRET_KEY = '$secret_key'

DEBUG = False

LOG_LEVEL = 'WARNING'

PLUGINS = []
EOF
    
    # Устанавливаем правильные права
    chown netbox:netbox "$config_file"
    chmod 644 "$config_file"
    
    echo "✅ Configuration.py создан в $config_file"
}

# === ОСНОВНАЯ УСТАНОВКА NETBOX ===

# Интерактивный ввод конфигурации
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   УСТАНОВКА NETBOX v4.4+                      ║"
echo "║                   на Ubuntu 24.04.3 LTS                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Выбор версии NetBox
select_netbox_version

# 2. Настройка базы данных
echo ""
echo "=== НАСТРОЙКА БАЗЫ ДАННЫХ ==="
prompt_with_default "Введите имя пользователя для базы данных" "$DEFAULT_DB_USER" "DB_USER"
prompt_password "Введите пароль для базы данных" "$DEFAULT_DB_PASSWORD" "DB_PASSWORD"

# 3. Настройка администратора
echo ""
echo "=== НАСТРОЙКА АДМИНИСТРАТОРА ==="
prompt_email "Введите email администратора" "$DEFAULT_ADMIN_EMAIL" "ADMIN_EMAIL"
prompt_password "Введите пароль администратора" "$DEFAULT_ADMIN_PASSWORD" "ADMIN_PASSWORD"

# Подтверждение конфигурации
show_configuration

echo -n "Продолжить установку NetBox с этими настройками? (y/N): "
read -r confirm
if [[ ! "$confirm" =~ ^[YyДд]$ ]]; then
    echo "❌ Установка отменена."
    exit 1
fi

echo ""
echo "[+] Начинаем установку NetBox..."

# Получаем конкретную версию, если выбрано latest
if [ "$NETBOX_VERSION" = "latest" ]; then
    echo "[*] Определение последней версии NetBox..."
    NETBOX_VERSION=$(get_latest_netbox_version)
    echo "[*] Используется версия: $NETBOX_VERSION"
fi

# 1. Обновление системы и установка базовых пакетов
echo "[1] Обновление системы и установка зависимостей..."
apt update -y
apt install -y \
    curl \
    wget \
    nginx \
    postgresql \
    postgresql-contrib \
    redis-server \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    libpq-dev \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libssl-dev \
    libjpeg-dev \
    zlib1g-dev \
    git

# 2. Настройка PostgreSQL
echo "[2] Настройка PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

sudo -u postgres psql -c "DROP DATABASE IF EXISTS netbox;" 2>/dev/null || true
sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;" 2>/dev/null || true
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE netbox OWNER $DB_USER;"
sudo -u postgres psql -c "ALTER USER $DB_USER CREATEDB;"

# 3. Настройка Redis
echo "[3] Настройка Redis..."
systemctl enable redis-server
systemctl start redis-server

# 4. Создание системного пользователя
echo "[4] Создание пользователя netbox..."
if ! id "netbox" &>/dev/null; then
    useradd --system --home-dir /opt/netbox --create-home --shell /bin/bash netbox
fi

# 5. Очистка и клонирование NetBox
echo "[5] Подготовка директории и клонирование NetBox $NETBOX_VERSION..."

# Останавливаем службы если они запущены
systemctl stop netbox 2>/dev/null || true

# Очищаем директорию
echo "Очищаем директорию /opt/netbox..."
rm -rf /opt/netbox
mkdir -p /opt/netbox
chown -R netbox:netbox /opt/netbox

# Клонируем заново
cd /opt/netbox
echo "[*] Клонирование NetBox $NETBOX_VERSION..."
sudo -u netbox git clone --branch "$NETBOX_VERSION" --depth 1 https://github.com/netbox-community/netbox.git .
check_success "Клонирование NetBox $NETBOX_VERSION"

# Устанавливаем правильные права после клонирования
chown -R netbox:netbox /opt/netbox
chmod -R 755 /opt/netbox

# 6. Создание/обновление конфигурационного файла
echo "[6] Настройка конфигурации..."

# Генерация SECRET_KEY
echo "[*] Генерация SECRET_KEY..."
SECRET_KEY=$(sudo -u netbox python3 /opt/netbox/netbox/generate_secret_key.py)

# Создаем configuration.py
create_configuration "$SECRET_KEY"

# Проверяем, что файл создан
if [ ! -f "/opt/netbox/netbox/netbox/configuration.py" ]; then
    echo "❌ Файл configuration.py не создан!"
    exit 1
fi

# 7. Создание виртуального окружения и установка зависимостей
echo "[7] Установка Python зависимостей..."
rm -rf /opt/netbox/venv
python3 -m venv /opt/netbox/venv
chown -R netbox:netbox /opt/netbox/venv

sudo -u netbox /opt/netbox/venv/bin/pip install --upgrade pip
sudo -u netbox /opt/netbox/venv/bin/pip install -r /opt/netbox/requirements.txt
check_success "Установка Python пакетов"

# 8. Миграции базы данных
echo "[8] Применение миграций..."
cd /opt/netbox
export NETBOX_CONFIGURATION="netbox.configuration"
sudo -u netbox /opt/netbox/venv/bin/python3 /opt/netbox/netbox/manage.py migrate
check_success "Миграции базы данных"

# 9. Сбор статических файлов
echo "[9] Сбор статических файлов..."
sudo -u netbox /opt/netbox/venv/bin/python3 /opt/netbox/netbox/manage.py collectstatic --no-input
check_success "Сбор статических файлов"

# Исправляем права на статические файлы
STATIC_DIR="/opt/netbox/netbox/static"
if [ -d "$STATIC_DIR" ]; then
    chown -R netbox:www-data "$STATIC_DIR"
    chmod -R 755 "$STATIC_DIR"
else
    # В новых версиях может быть другой путь
    ALT_STATIC_DIR="/opt/netbox/netbox/netbox/static"
    if [ -d "$ALT_STATIC_DIR" ]; then
        chown -R netbox:www-data "$ALT_STATIC_DIR"
        chmod -R 755 "$ALT_STATIC_DIR"
    else
        echo "⚠️  Директория статических файлов не найдена"
    fi
fi

# 10. Создание суперпользователя
echo "[10] Создание администратора..."
echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.create_superuser('admin', '$ADMIN_EMAIL', '$ADMIN_PASSWORD')" | sudo -u netbox /opt/netbox/venv/bin/python3 /opt/netbox/netbox/manage.py shell
check_success "Создание суперпользователя"

# 11. Создание systemd службы
echo "[11] Настройка службы NetBox..."
cat > /etc/systemd/system/netbox.service <<EOF
[Unit]
Description=NetBox WSGI Service
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=netbox
Group=netbox
WorkingDirectory=/opt/netbox/netbox
Environment=PATH=/opt/netbox/venv/bin
Environment=PYTHONPATH=/opt/netbox/netbox
Environment=NETBOX_CONFIGURATION=netbox.configuration
ExecStart=/opt/netbox/venv/bin/gunicorn --bind 127.0.0.1:8001 --workers 3 --threads 3 netbox.wsgi:application
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable netbox
systemctl start netbox
check_success "Запуск службы NetBox"

# 12. Настройка Nginx
echo "[12] Настройка Nginx..."
STATIC_PATH="/opt/netbox/netbox/static"
if [ ! -d "$STATIC_PATH" ]; then
    # Проверяем альтернативный путь
    STATIC_PATH="/opt/netbox/netbox/netbox/static"
fi

cat > /etc/nginx/sites-available/netbox <<EOF
server {
    listen 80;
    server_name _;

    client_max_body_size 25m;

    # Статические файлы
    location /static/ {
        alias $STATIC_PATH/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Динамические запросы к NetBox
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }
}
EOF

ln -sf /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации nginx
nginx -t
check_success "Проверка конфигурации Nginx"

systemctl enable nginx
systemctl restart nginx
check_success "Перезапуск Nginx"

# 13. Финальные проверки
echo "[13] Финальные проверки..."
sleep 5

# Проверяем статусы
echo "--- Статус служб ---"
systemctl status netbox --no-pager -l
systemctl status nginx --no-pager -l

# Проверяем статические файлы
echo "--- Проверка статических файлов ---"
if [ -d "$STATIC_PATH" ]; then
    ls -la "$STATIC_PATH/" | head -5
else
    echo "⚠️  Директория статических файлов не найдена"
fi

# Проверяем доступность
SERVER_IP=$(hostname -I | awk '{print $1}')
if curl -s -I http://localhost > /dev/null; then
    echo "✅ NetBox доступен по HTTP"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                NETBOX УСПЕШНО УСТАНОВЛЕН!                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    
    echo ""
    echo "🌐 ДОСТУП К NETBOX:"
    echo "------------------"
    echo "📦 Версия NetBox: $NETBOX_VERSION"
    echo "🌐 URL: http://$SERVER_IP"
    echo "👤 Логин: admin"
    echo "📧 Email: $ADMIN_EMAIL"
    echo "🔑 Пароль: (тот, что вы указали)"
    echo ""
else
    echo "⚠️  Проблемы с доступом, проверяем логи..."
    journalctl -u netbox --no-pager -l --lines=10
    echo "Проверьте также: tail -f /var/log/nginx/error.log"
fi

# 15. Готово!
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    УСТАНОВКА ЗАВЕРШЕНА!                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Версия NetBox: $NETBOX_VERSION"
echo "🌐 URL: http://$SERVER_IP"
echo "👤 Логин: admin"
echo "📧 Email: $ADMIN_EMAIL"
echo "🔑 Пароль: (тот, что вы указали)"
echo "🗄️  Пользователь БД: $DB_USER"
echo "🔐 Пароль БД: (тот, что вы указали)"

echo ""
echo "📋 КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ PLUGINS (после установки):"
echo "----------------------------------------------------"
echo "  1. Установить плагин:"
echo "     sudo -u netbox /opt/netbox/venv/bin/pip install <имя_плагина>"
echo ""
echo "  2. Добавить плагин в конфигурацию (/opt/netbox/netbox/netbox/configuration.py):"
echo "     PLUGINS = ["
echo "         '<имя_плагина>',"
echo "     ]"
echo ""
echo "  3. Применить миграции:"
echo "     sudo -u netbox /opt/netbox/venv/bin/python3 /opt/netbox/netbox/manage.py migrate"
echo ""
echo "  4. Собрать статические файлы:"
echo "     sudo -u netbox /opt/netbox/venv/bin/python3 /opt/netbox/netbox/manage.py collectstatic --no-input"
echo ""
echo "  5. Перезапустить NetBox:"
echo "     sudo systemctl restart netbox"
echo ""

echo "📋 КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ NETBOX:"
echo "---------------------------------"
echo "   systemctl restart netbox    # Перезапуск NetBox"
echo "   systemctl status netbox     # Статус NetBox"
echo "   journalctl -u netbox -f     # Просмотр логов в реальном времени"
echo "   sudo -u netbox /opt/netbox/venv/bin/python3 /opt/netbox/netbox/manage.py createsuperuser  # Создать нового админа"
echo ""
echo "⚙️  ФАЙЛЫ КОНФИГУРАЦИИ:"
echo "----------------------"
echo "   Конфигурация NetBox: /opt/netbox/netbox/netbox/configuration.py"
echo "   Служба systemd: /etc/systemd/system/netbox.service"
echo "   Конфиг Nginx: /etc/nginx/sites-available/netbox"
echo ""
echo "⚠️  СОВЕТЫ ПО БЕЗОПАСНОСТИ:"
echo "---------------------------"
echo "   1. Смените пароли администратора и БД после первого входа"
echo "   2. Настройте SSL/TLS для HTTPS"
echo "   3. Ограничьте доступ по IP если возможно"
echo "   4. Настройте бэкапы базы данных"
echo ""
echo "🎉 Наслаждайтесь использованием NetBox!"