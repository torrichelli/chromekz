# Инструкция по загрузке и установке на новый VPS

## Способ 1: Копирование через SSH (Рекомендуется)

### 1.1 Подключение к серверу
```bash
ssh root@your-server-ip
```

### 1.2 Создание скрипта
```bash
nano fresh_vps_deploy.sh
```

Скопируйте весь код из файла `fresh_vps_deploy.sh` и вставьте в редактор nano.
Сохраните: `Ctrl+X`, затем `Y`, затем `Enter`

### 1.3 Установка прав и запуск
```bash
chmod +x fresh_vps_deploy.sh
sudo bash fresh_vps_deploy.sh
```

## Способ 2: Через GitHub (если есть репозиторий)

### 2.1 Создайте репозиторий на GitHub
Загрузите файл `fresh_vps_deploy.sh` в репозиторий

### 2.2 На сервере:
```bash
# Установка git
apt update && apt install git -y

# Клонирование репозитория
git clone https://github.com/ваш-username/ваш-репозиторий.git
cd ваш-репозиторий

# Запуск
chmod +x fresh_vps_deploy.sh
sudo bash fresh_vps_deploy.sh
```

## Способ 3: Через wget с файлообменника

### 3.1 Загрузите файл на файлообменник
- Upload скрипт на любой файлообменник (например file.io, transfer.sh)
- Получите прямую ссылку

### 3.2 На сервере:
```bash
wget "прямая-ссылка-на-файл" -O fresh_vps_deploy.sh
chmod +x fresh_vps_deploy.sh
sudo bash fresh_vps_deploy.sh
```

## Способ 4: Через SCP с локального компьютера

Если у вас есть скрипт на локальном компьютере:

```bash
scp fresh_vps_deploy.sh root@your-server-ip:/root/
ssh root@your-server-ip
chmod +x fresh_vps_deploy.sh
sudo bash fresh_vps_deploy.sh
```

## Требования к серверу

- **ОС:** Ubuntu 22.04 LTS
- **RAM:** минимум 1GB (рекомендуется 2GB)
- **Диск:** минимум 20GB
- **Доступ:** root или sudo

## Важные моменты

1. **Перед запуском** убедитесь что домен `logistics.xrom.org` указывает на IP вашего сервера в DNS настройках

2. **После установки** настройте SSL:
```bash
sudo certbot --nginx -d logistics.xrom.org
```

3. **Первый запуск:** создайте сотрудника через http://logistics.xrom.org/register

## Возможные ошибки

- **Домен не указывает на сервер:** Настройте A-запись в DNS
- **Порты закрыты:** Скрипт автоматически настроит UFW firewall
- **Недостаточно памяти:** Добавьте swap-файл

## Управление после установки

```bash
# Статус сервисов
sudo systemctl status hromkz
sudo systemctl status nginx
sudo systemctl status postgresql

# Логи приложения
sudo journalctl -u hromkz -f

# Перезапуск
sudo systemctl restart hromkz
```