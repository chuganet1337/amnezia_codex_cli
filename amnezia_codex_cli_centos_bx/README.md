# Codex CLI через AmneziaWG на CentOS/BitrixVM 9

Комплект предназначен для CentOS Stream 9 и RHEL 9 совместимых систем, включая
сервер BitrixVM на совместимой базе. Только Codex CLI и запущенные им дочерние
процессы идут через AmneziaWG. Сеть портала Bitrix24, nginx, Apache, MySQL и
остальных служб не переключается в VPN.

## Какие файлы должны быть в папке

```text
/root/amnezia_codex_cli_centos_bx/
├── README.md
├── install.sh
├── verify.sh
└── uninstall.sh
```

Приватный профиль хранится отдельно:

```text
/root/amnezia_for_awg.conf
```

## Шаг 1. Проверить ОС, ядро и Codex

```bash
sudo -i
cat /etc/os-release
uname -r
uname -m
command -v codex
codex --version
```

Требуется major-версия ОС 9, RHEL/CentOS совместимая система, `x86_64` и Codex CLI
в `PATH`. Установщик сам определяет фактический путь Codex и больше не требует,
чтобы бинарник обязательно находился в `/usr/bin/codex`.

Проверьте наличие заголовков точно для запущенного ядра:

```bash
rpm -q "kernel-devel-$(uname -r)"
```

Если пакет не найден, установщик попытается его установить. Он намеренно не
обновляет ядро и не перезагружает сервер BitrixVM автоматически.

## Шаг 2. Подготовить AmneziaWG-профиль

Профиль должен содержать как минимум:

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

1. `AllowedIPs` включает `0.0.0.0/0`.
2. `Endpoint` указан числовым IPv4-адресом и портом.
3. Профиль не хранится в Git.
4. На сервере файл имеет права `600`.

```bash
chmod 600 /root/amnezia_for_awg.conf
```

## Шаг 3. Скопировать комплект с Windows

В PowerShell:

```powershell
cd C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli
scp -r .\amnezia_codex_cli_centos_bx root@BITRIX_SERVER_IP:/root/
scp C:\path\outside\repo\amnezia_for_awg.conf root@BITRIX_SERVER_IP:/root/
```

## Шаг 4. Проверить скрипты

На сервере:

```bash
cd /root/amnezia_codex_cli_centos_bx
ls -la
chmod 755 install.sh verify.sh uninstall.sh
bash -n install.sh verify.sh uninstall.sh
```

Если `bash -n` не вывел ошибок, переходите к установке.

## Шаг 5. Запустить установку

```bash
./install.sh /root/amnezia_for_awg.conf
```

Установщик:

1. Проверяет ОС, Codex CLI и поля AWG-профиля.
2. Устанавливает `dnf-plugins-core`, совпадающий `kernel-devel`, DKMS и AWG-пакеты.
3. Подключает COPR `amneziavpn/amneziawg`.
4. Проверяет модуль `amneziawg` временным интерфейсом.
5. Сохраняет профиль в `/etc/amnezia-codex/awg0.conf` с правами `600`.
6. Сохраняет реальный путь Codex в `/etc/amnezia-codex/real-codex-path`.
7. Создаёт namespace `codexvpn`, интерфейс `awg-codex` и отдельный DNS.
8. Устанавливает `codex-vpn.service` и fail-closed обёртку
   `/usr/local/bin/codex`.
9. Проверяет получение публичного IPv4 через VPN.

Если пакеты и модуль уже установлены:

```bash
./install.sh --skip-packages /root/amnezia_for_awg.conf
```

## Шаг 6. Проверить результат

```bash
hash -r
type -a codex
./verify.sh
```

Первым путём должен быть `/usr/local/bin/codex`. Проверка должна подтвердить:

- активную службу;
- единственный IPv4 default route через `awg-codex`;
- отсутствие IPv6 default route;
- разные IP у хоста и namespace;
- доступность OpenAI API.

Ручная проверка:

```bash
systemctl status codex-vpn.service --no-pager
ip netns exec codexvpn awg show awg-codex
curl -4 https://api.ipify.org
ip netns exec codexvpn curl -4 https://api.ipify.org
```

## Шаг 7. Войти в Codex по SSH

```bash
codex login --device-auth
codex login status
codex exec "Ответь только словом OK"
```

## Ежедневная работа

```bash
codex
```

Не запускайте напрямую путь, сохранённый в
`/etc/amnezia-codex/real-codex-path`: он обходит VPN-обёртку.

## Замена профиля

```bash
cd /root/amnezia_codex_cli_centos_bx
./install.sh --skip-packages /root/new_amnezia.conf
./verify.sh
```

Старый профиль сохраняется в timestamp-резервную копию.

## Обновление Codex CLI

```bash
npm install -g @openai/codex@latest
hash -r
./install.sh --skip-packages /root/amnezia_for_awg.conf
./verify.sh
```

Повторный запуск нужен, чтобы установщик заново определил фактический путь CLI.

## Удаление

Сохранить профиль:

```bash
./uninstall.sh
```

Удалить также основной профиль и сохранённый путь CLI:

```bash
./uninstall.sh --purge-config
```

Пакеты AmneziaWG и timestamp-резервные копии остаются установленными.

## Диагностика

```bash
journalctl -u codex-vpn.service -n 100 --no-pager
dkms status
rpm -q "kernel-devel-$(uname -r)"
modprobe amneziawg
./verify.sh
```

Официальная инструкция по модулю:
[amneziawg-linux-kernel-module](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module).
