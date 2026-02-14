#!/bin/bash

set -e


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}VPN Server Installation Script${NC}"
echo -e "${BLUE}========================================${NC}"


if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Запустите скрипт с правами root (sudo ./install.sh)${NC}"
    exit 1
fi


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="/opt/vpn-server"
SERVICE_NAME="vpn-server"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo -e "${YELLOW}[1/6] Проверка наличия исполняемого файла...${NC}"


if [ ! -f "${SCRIPT_DIR}/relay_server" ]; then
    echo -e "${RED}Ошибка: Файл relay_server не найден в ${SCRIPT_DIR}${NC}"
    echo -e "${YELLOW}Скомпилируйте сервер: cargo build --release${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Исполняемый файл найден${NC}"

echo -e "${YELLOW}[2/6] Создание директории установки...${NC}"
mkdir -p "${INSTALL_DIR}"
echo -e "${GREEN}✓ Директория создана: ${INSTALL_DIR}${NC}"

echo -e "${YELLOW}[3/6] Копирование файлов...${NC}"
cp "${SCRIPT_DIR}/relay_server" "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/relay_server"
echo -e "${GREEN}✓ Файлы скопированы${NC}"

echo -e "${YELLOW}[4/6] Создание systemd service файла...${NC}"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=VPN Relay Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/relay_server
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓ Service файл создан${NC}"

echo -e "${YELLOW}[5/6] Настройка systemd...${NC}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
echo -e "${GREEN}✓ Systemd настроен${NC}"

echo -e "${YELLOW}[6/6] Запуск сервера...${NC}"
systemctl start "${SERVICE_NAME}.service"
sleep 2

# Проверяем статус
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    echo -e "${GREEN}✓ Сервер успешно запущен${NC}"
else
    echo -e "${RED}✗ Ошибка при запуске сервера${NC}"
    echo -e "${YELLOW}Проверьте логи: journalctl -u ${SERVICE_NAME}.service -n 50${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Установка завершена успешно!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""


sleep 3


CONFIG_FILE="${INSTALL_DIR}/server_config.json"

if [ -f "${CONFIG_FILE}" ]; then
    echo -e "${YELLOW}Конфигурация сервера:${NC}"
    cat "${CONFIG_FILE}" | python3 -m json.tool 2>/dev/null || cat "${CONFIG_FILE}"
    echo ""
    

    SERVER_IP=$(grep -o '"server_ip": "[^"]*"' "${CONFIG_FILE}" | cut -d'"' -f4)
    PORT=$(grep -o '"port": [0-9]*' "${CONFIG_FILE}" | grep -o '[0-9]*')
    KEY=$(grep -o '"encryption_key": "[^"]*"' "${CONFIG_FILE}" | cut -d'"' -f4)
    
    if [ ! -z "$SERVER_IP" ] && [ ! -z "$PORT" ] && [ ! -z "$KEY" ]; then
        RAW_FORMAT="${SERVER_IP}:${PORT}:${KEY}"
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}${RAW_FORMAT}${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}Конфигурационный файл еще не создан. Проверьте логи сервера.${NC}"
fi

echo ""
echo -e "${BLUE}Полезные команды:${NC}"
echo -e "  Статус:     ${YELLOW}systemctl status ${SERVICE_NAME}.service${NC}"
echo -e "  Логи:       ${YELLOW}journalctl -u ${SERVICE_NAME}.service -f${NC}"
echo -e "  Перезапуск: ${YELLOW}systemctl restart ${SERVICE_NAME}.service${NC}"
echo -e "  Остановка:  ${YELLOW}systemctl stop ${SERVICE_NAME}.service${NC}"
echo ""

