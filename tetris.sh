#!/bin/bash

download_node() {
  echo "Начинаю установку ноды через Docker..."

  # Правильная установка Docker
  echo "Установка Docker..."
  sudo apt-get remove docker docker-engine docker.io containerd runc || true
  sudo apt-get update
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    wget \
    jq
  
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Установка Ollama
  echo "Устанавливаю Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
  
  # Зап��ск сервиса Ollama
  echo "Запускаю сервис Ollama..."
  systemctl start ollama || ollama serve &
  sleep 10  # Даем время Ollama запуститься

  # Загрузка файла infera
  wget -O infera "https://drive.google.com/uc?id=1VSeI8cXojdh78H557SQJ9LfnnaS96DT-&export=download&confirm=yes"
  chmod +x infera

  # Создание Dockerfile
  cat <<EOF > Dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    curl git nano make gcc build-essential jq screen \
    ca-certificates gcc unzip lz4 wget bison software-properties-common \
    && apt-get clean
COPY infera /usr/local/bin/infera
RUN chmod +x /usr/local/bin/infera
CMD ["infera"]
EOF

  # Сборка Docker-образа
  docker build -t infera-node .

  # Запуск контейнера с параметром network=host
  docker run -d --name infera-node --network="host" --restart unless-stopped infera-node

  echo "Нода успешно установлена и запущена в контейнере Docker!"
}

check_points() {
  total_points=$(curl -s http://localhost:11025/points | jq)
  echo -e "У вас столько поинтов: $total_points"
}

watch_secrets() {
  curl -s http://localhost:11025/node_details | jq
}

check_logs() {
  docker logs --tail 100 infera-node
}

restart_node() {
  echo "Перезагружаю ноду..."
  docker restart infera-node
  echo "Нода была успешно перезагружена."
}

# Добавляем новую функцию для автоматического перезапуска
setup_auto_restart() {
  echo "Настраиваю автоматический перезапуск ноды каждые 2 часа..."
  
  # Создаем запись в crontab с логированием
  (crontab -l 2>/dev/null; echo "0 */2 * * * docker restart infera-node >> /root/node_restart.log 2>&1") | crontab -
  
  echo "✅ Автоматический перезапуск настроен!"
  echo "🕐 Нода будет перезапускаться каждые 2 часа"
  echo "📝 Логи перезапуска сохраняются в /root/node_restart.log"
}

# Добавляем функцию для отключения автоперезапуска
disable_auto_restart() {
  echo "Отключаю автоматический перезапуск..."
  crontab -l | grep -v "docker restart infera-node" | crontab -
  echo "✅ Автоматический перезапуск отключен"
}

update_node() {
  echo "Начинаю обновление ноды..."

  # Удаляем старый контейнер
  docker stop infera-node && docker rm infera-node

  # Удаляем старый образ
  docker rmi infera-node

  # Переустановка
  download_node
}

delete_node() {
  read -p "Вы уверены, что хотите удалить ноду? (нажмите y для продолжения): " confirm
  if [[ "$confirm" == "y" ]]; then
    echo "Удаляю ноду..."
    docker stop infera-node && docker rm infera-node
    docker rmi infera-node
    rm -f infera Dockerfile
    echo "Нода успешно удалена."
  else
    echo "Операция отменена."
  fi
}

exit_from_script() {
  exit 0
}

# Добавляем функцию проверки статуса автоперезапуска
check_auto_restart() {
  if crontab -l | grep -q "docker restart infera-node"; then
    echo "✅ Автоперезапуск активен"
    echo "🕐 Текущее расписание:"
    crontab -l | grep "docker restart infera-node"
    
    # Показываем время до следующего перезапуска
    current_minute=$(date +%M)
    minutes_left=$((120 - (current_minute % 120)))
    hours_left=$((minutes_left / 60))
    mins_left=$((minutes_left % 60))
    
    echo "⏳ Следующий перезапуск через: ${hours_left}ч ${mins_left}мин"
  else
    echo "❌ Автоперезапуск не активен"
  fi
}

while true; do
  echo -e "\n\nМеню:"
  echo "1. 🌱 Установить ноду"
  echo "2. 📊 Проверить сколько поинтов"
  echo "3. 📂 Посмотреть данные"
  echo "4. 🕸️ Посмотреть логи"
  echo "5. 🍴 Перезагрузить ноду"
  echo "6. 🔄 Обновить ноду"
  echo "7. ❌ Удалить ноду"
  echo "8. ⏰ Включить авто-перезапуск (каждые 2 часа)"
  echo "9. 🚫 Отключить авто-перезапуск"
  echo "10. 📋 Проверить статус авто-перезапуска"
  echo -e "11. 🚪 Выйти из скрипта\n"
  read -p "Выберите пункт меню: " choice

  case $choice in
    1)
      download_node
      ;;
    2)
      check_points
      ;;
    3)
      watch_secrets
      ;;
    4)
      check_logs
      ;;
    5)
      restart_node
      ;;
    6)
      update_node
      ;;
    7)
      delete_node
      ;;
    8)
      setup_auto_restart
      ;;
    9)
      disable_auto_restart
      ;;
    10)
      check_auto_restart
      ;;
    11)
      exit_from_script
      ;;
    *)
      echo "Неверный пункт. Пожалуйста, выберите правильную цифру в меню."
      ;;
  esac
done
