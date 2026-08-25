# Codex CLI через AmneziaWG на Ubuntu

Комплект сначала устанавливает и запускает AmneziaWG с профилем для OpenAI,
затем через поднятый VPN устанавливает Codex CLI. Codex и все его дочерние
команды работают в отдельном network namespace `codexvpn`; обычные процессы
Ubuntu продолжают использовать основной маршрут. Если VPN недоступен, обёртка
не запускает Codex.

Порядок всегда такой:

1. AmneziaWG.
2. Профиль `/root/amnezia_for_awg.conf` и проверка VPN-IP.
3. Установка Codex через этот VPN.
4. Защищённая команда `codex` и итоговая проверка.

## Поддерживаемые системы

- Ubuntu Server 22.04 LTS `jammy`, amd64.
- Ubuntu Server 24.04 LTS `noble`, amd64 — рекомендуемый вариант.
- Ubuntu Server 26.04 LTS `resolute`, amd64.

На Ubuntu 22.04/24.04 AmneziaWG устанавливается из официального PPA. Для Ubuntu
26.04 серии `resolute` в PPA нет, поэтому установщик автоматически собирает
модуль и утилиты из закреплённых ревизий официальных репозиториев Amnezia. Уже
добавленный нерабочий PPA `resolute` отключается с сохранением исходного файла.

## Какие файлы должны быть в папке

```text
/root/amnezia_codex_cli_ubuntu/
├── README.md
├── install.sh
├── verify.sh
└── uninstall.sh
```

Приватный профиль хранится отдельно:

```text
/root/amnezia_for_awg.conf
```

Не кладите `.conf` в Git-репозиторий.

## Шаг 1. Проверить сервер

Выполните от `root`:

```bash
sudo -i
cat /etc/os-release
dpkg --print-architecture
uname -r
```

Ожидается Ubuntu 22.04, 24.04 или 26.04 и архитектура `amd64`. Codex заранее
устанавливать не нужно. Скрипт создаёт собственную управляемую копию в
`/opt/openai-codex/bin` только после запуска VPN; ранее установленный вне VPN
Codex не используется.

## Шаг 2. Если ранее добавляли нерабочий PPA

На Ubuntu 26.04 установщик сам отключит файлы в `/etc/apt/sources.list.d`,
содержащие `ppa.launchpadcontent.net/amnezia/ppa`, переименовав их с суффиксом
`.disabled-by-amnezia-codex`. Активные строки в `/etc/apt/sources.list` будут
закомментированы после создания резервной копии.

До запуска можно посмотреть такие записи:

```bash
grep -RIl 'ppa.launchpadcontent.net/amnezia/ppa' \
  /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
```

## Шаг 3. Подготовить AmneziaWG-профиль

Экспортируйте нативную конфигурацию AmneziaWG. Она должна содержать:

```ini
[Interface]
Address = 10.x.x.x/32
PrivateKey = ...

[Peer]
PublicKey = ...
Endpoint = 203.0.113.10:12345
AllowedIPs = 0.0.0.0/0
```

Требования:

1. `AllowedIPs` обязательно включает `0.0.0.0/0`.
2. `Endpoint` задаётся числовым IPv4-адресом и портом, не доменным именем.
3. `PrivateKey` и `PresharedKey` нельзя публиковать.
4. На сервере профиль должен иметь права `600`.

```bash
chmod 600 /root/amnezia_for_awg.conf
```

## Шаг 4. Скопировать комплект на сервер

На Windows-ПК в PowerShell:

```powershell
cd C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli
scp -r .\amnezia_codex_cli_ubuntu root@SERVER_IP:/root/
scp C:\path\outside\repo\amnezia_for_awg.conf root@SERVER_IP:/root/
```

## Шаг 5. Проверить скачанные скрипты

На Ubuntu:

```bash
cd /root/amnezia_codex_cli_ubuntu
ls -la
chmod 755 install.sh verify.sh uninstall.sh
bash -n install.sh verify.sh uninstall.sh
```

`bash -n` ничего не устанавливает; он только проверяет синтаксис. Если вывода нет,
синтаксис корректен.

## Шаг 6. Запустить установку

```bash
./install.sh /root/amnezia_for_awg.conf
```

Скрипт последовательно:

1. Проверяет ОС, архитектуру и обязательные поля AWG-профиля.
2. Устанавливает AmneziaWG из PPA либо собирает его из официальных исходников.
3. Проверяет модуль временным AWG-интерфейсом.
4. Копирует профиль в `/etc/amnezia-codex/awg0.conf` с правами `600`.
5. Создаёт namespace `codexvpn`, интерфейс `awg-codex` и отдельный DNS.
6. Запускает `codex-vpn.service` и проверяет публичный IPv4 через VPN.
7. Если управляемая копия Codex отсутствует, запускает официальный установщик
   внутри `codexvpn`.
8. Сохраняет путь реального CLI в `/etc/amnezia-codex/real-codex-path`.
9. Создаёт fail-closed обёртку `/usr/local/bin/codex`.

Если AmneziaWG уже установлен и команды `awg`, `awg-quick` работают:

```bash
./install.sh --skip-packages /root/amnezia_for_awg.conf
```

Режим `--skip-packages` требует заранее установленных и работающих команд
`awg`, `awg-quick` и модуля `amneziawg`. Для Ubuntu 26.04 обходить PPA этим
параметром больше не требуется.

## Шаг 7. Проверить результат

```bash
hash -r
type -a codex
./verify.sh
```

Первым путём должен быть `/usr/local/bin/codex`. Успешный `verify.sh` показывает:

- активную службу `codex-vpn.service`;
- маршрут `default dev awg-codex`;
- отсутствие IPv6 default route;
- разные публичные IP у хоста и Codex namespace;
- HTTP `401` от OpenAI API без токена — это означает, что API доступен.

Дополнительные команды:

```bash
systemctl status codex-vpn.service --no-pager
ip netns exec codexvpn awg show awg-codex
curl -4 https://api.ipify.org
ip netns exec codexvpn curl -4 https://api.ipify.org
```

## Шаг 8. Войти в Codex на SSH-сервере

```bash
codex login --device-auth
```

Откройте показанную ссылку на своём ПК и введите одноразовый код. Затем:

```bash
codex login status
codex exec "Ответь только словом OK"
```

## Ежедневная работа

Запускайте только:

```bash
codex
```

Не запускайте напрямую путь из `/etc/amnezia-codex/real-codex-path`: это реальный
CLI без VPN-обёртки.

## Замена VPN-профиля

Завершите процессы Codex и выполните:

```bash
cd /root/amnezia_codex_cli_ubuntu
./install.sh --skip-packages /root/new_amnezia.conf
./verify.sh
```

Предыдущий профиль сохраняется как
`/etc/amnezia-codex/awg0.conf.backup.YYYYMMDD-HHMMSS`.

## Обновление Codex CLI

Codex, установленный этим проектом, обновляйте через тот же VPN и в тот же
каталог, затем повторно запустите установщик:

```bash
ip netns exec codexvpn env \
  HOME=/root \
  CODEX_HOME=/root/.codex \
  CODEX_INSTALL_DIR=/opt/openai-codex/bin \
  CODEX_NON_INTERACTIVE=1 \
  sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh | sh'
hash -r
./install.sh --skip-packages /root/amnezia_for_awg.conf
./verify.sh
```

## Удаление

Сохранить установленный AWG-профиль:

```bash
./uninstall.sh
```

Удалить также основной профиль и сохранённый путь Codex:

```bash
./uninstall.sh --purge-config
```

Пакеты AmneziaWG и timestamp-резервные копии не удаляются автоматически.

## Диагностика

```bash
journalctl -u codex-vpn.service -n 100 --no-pager
dkms status
dpkg -s "linux-headers-$(uname -r)"
modprobe amneziawg
./verify.sh
```

Официальная инструкция по модулю:
[amneziawg-linux-kernel-module](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module).
