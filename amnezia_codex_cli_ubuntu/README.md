# Codex CLI через AmneziaWG на Ubuntu

Комплект запускает Codex CLI и все его дочерние команды в отдельном network
namespace `codexvpn`. У обычных процессов Ubuntu маршрут не меняется. Если
AmneziaWG недоступен, обёртка отказывается запускать Codex.

## Поддерживаемые системы

- Ubuntu Server 22.04 LTS `jammy`, amd64.
- Ubuntu Server 24.04 LTS `noble`, amd64 — рекомендуемый вариант.

Ubuntu 26.04 `resolute` пока нельзя устанавливать через PPA: в репозитории
`ppa:amnezia/ppa` отсутствует серия `resolute`. Установщик проверяет версию до
изменения APT и завершится с понятной ошибкой. На 26.04 допускается только режим
`--skip-packages`, если модуль `amneziawg` и команды `awg`/`awg-quick` уже
установлены и проверены вручную.

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

## Шаг 1. Удалить сломанный PPA на Ubuntu 26.04

Этот шаг нужен только если `apt update` уже показывает:

```text
The repository 'https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu resolute Release' does not have a Release file
```

Посмотрите добавленные записи:

```bash
grep -RIl 'ppa.launchpadcontent.net/amnezia/ppa' \
  /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
```

Попробуйте штатное удаление:

```bash
add-apt-repository --remove -y ppa:amnezia/ppa
apt update
```

Если запись осталась, проверьте точное имя файла:

```bash
ls -l /etc/apt/sources.list.d/*amnezia* 2>/dev/null
```

На `resolute` обычно это один из файлов ниже. Удаляйте только существующий файл с
репозиторием Amnezia:

```bash
rm -f /etc/apt/sources.list.d/amnezia-ubuntu-ppa-resolute.sources
rm -f /etc/apt/sources.list.d/amnezia-ubuntu-ppa-resolute.list
apt update
```

После восстановления APT рекомендуется установить Ubuntu Server 24.04 LTS и
продолжить со следующего шага. Подмена `resolute` на `noble` в источниках APT в
этом проекте намеренно не используется.

## Шаг 2. Проверить сервер

Выполните от `root`:

```bash
sudo -i
cat /etc/os-release
dpkg --print-architecture
uname -r
command -v codex
codex --version
```

Ожидается Ubuntu 22.04/24.04, архитектура `amd64` и найденная команда `codex`.
Codex CLI должен быть установлен до запуска `install.sh`.

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

1. Проверяет ОС, архитектуру, Codex CLI и обязательные поля AWG-профиля.
2. Устанавливает заголовки текущего ядра, DKMS, `iproute2`, `curl` и AmneziaWG.
3. Проверяет загрузку модуля временным AWG-интерфейсом.
4. Копирует профиль в `/etc/amnezia-codex/awg0.conf` с правами `600`.
5. Сохраняет фактический путь Codex CLI в
   `/etc/amnezia-codex/real-codex-path`.
6. Создаёт namespace `codexvpn`, интерфейс `awg-codex` и отдельный DNS.
7. Создаёт и запускает `codex-vpn.service`.
8. Создаёт `/usr/local/bin/codex`, запускающий реальный CLI внутри namespace.
9. Проверяет, что через VPN получается публичный IPv4-адрес.

Если AmneziaWG уже установлен и команды `awg`, `awg-quick` работают:

```bash
./install.sh --skip-packages /root/amnezia_for_awg.conf
```

Не используйте `--skip-packages` только для обхода ошибки PPA: этот режим требует
заранее установленного и загружаемого модуля `amneziawg`.

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

После обновления CLI повторно запустите установщик, чтобы сохранить новый реальный
путь и пересоздать обёртку:

```bash
npm install -g @openai/codex@latest
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
