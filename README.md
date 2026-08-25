# AmneziaWG для Codex CLI

Репозиторий содержит два отдельных комплекта. Ubuntu-комплект сначала поднимает
AmneziaWG с профилем OpenAI, затем устанавливает Codex через VPN и запускает его
дочерние процессы в выделенном network namespace. Остальной трафик сервера
продолжает идти через обычную сеть.

## Структура репозитория

```text
amnezia_codex_cli/
├── .github/
│   └── workflows/
│       └── shellcheck.yml
├── .gitignore
├── README.md
├── docs/
│   └── WINDOWS_UPDATE.md
├── amnezia_codex_cli_ubuntu/
│   ├── README.md
│   ├── install.sh
│   ├── reinstall.sh
│   ├── verify.sh
│   └── uninstall.sh
└── amnezia_codex_cli_centos_bx/
    ├── README.md
    ├── install.sh
    ├── verify.sh
    └── uninstall.sh
```

Назначение файлов:

| Файл | Где находится | Назначение |
|---|---|---|
| `README.md` | в корне | общая структура и выбор комплекта |
| `README.md` | в папке ОС | полная пошаговая установка для этой ОС |
| `install.sh` | в папке ОС | установка namespace, службы и обёртки `codex` |
| `reinstall.sh` | Ubuntu | восстановимая чистая переустановка всего стека |
| `verify.sh` | в папке ОС | безопасная проверка службы, маршрутов, DNS и OpenAI |
| `uninstall.sh` | в папке ОС | удаление namespace и службы |
| `.gitignore` | только в корне | запрещает коммитить `.conf`, ключи и резервные копии |

VPN-профиль `amnezia_for_awg.conf` в репозиторий класть нельзя. Храните его
отдельно и копируйте прямо на нужный сервер, например в `/root/`.

## Какой комплект выбрать

- Обычный Ubuntu-сервер: `amnezia_codex_cli_ubuntu`.
- BitrixVM, CentOS Stream 9 или совместимая RHEL 9 система:
  `amnezia_codex_cli_centos_bx`.

Ubuntu 26.04 `resolute` не имеет пакетов в PPA Amnezia. На этой версии Ubuntu
установщик отключает нерабочую запись PPA и собирает модуль и утилиты из
закреплённых ревизий официальных репозиториев Amnezia.

## Размещение на Windows-ПК

Рекомендуемое итоговое расположение:

```text
C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli\
```

Внутри этой папки должны лежать обе платформенные папки из схемы выше. Полная
инструкция для первоначального клонирования, переноса старой папки и последующих
обновлений находится в [docs/WINDOWS_UPDATE.md](docs/WINDOWS_UPDATE.md).

## Быстрый запуск на Ubuntu 22.04/24.04

С Windows-ПК скопируйте папку и конфигурацию:

```powershell
scp -r "C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli\amnezia_codex_cli_ubuntu" root@SERVER_IP:/root/
scp "C:\path\outside\repo\amnezia_for_awg.conf" root@SERVER_IP:/root/
```

На сервере:

```bash
cd /root/amnezia_codex_cli_ubuntu
chmod 755 install.sh reinstall.sh verify.sh uninstall.sh
bash -n install.sh reinstall.sh verify.sh uninstall.sh
./install.sh /root/amnezia_for_awg.conf
./verify.sh
```

Перед запуском обязательно прочитайте
[`amnezia_codex_cli_ubuntu/README.md`](amnezia_codex_cli_ubuntu/README.md).

## Быстрый запуск на CentOS/BitrixVM 9

С Windows-ПК:

```powershell
scp -r "C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli\amnezia_codex_cli_centos_bx" root@BITRIX_SERVER_IP:/root/
scp "C:\path\outside\repo\amnezia_for_awg.conf" root@BITRIX_SERVER_IP:/root/
```

На сервере:

```bash
cd /root/amnezia_codex_cli_centos_bx
chmod 755 install.sh verify.sh uninstall.sh
bash -n install.sh verify.sh uninstall.sh
./install.sh /root/amnezia_for_awg.conf
./verify.sh
```

Перед запуском обязательно прочитайте
[`amnezia_codex_cli_centos_bx/README.md`](amnezia_codex_cli_centos_bx/README.md).

## Безопасность

- Никогда не коммитьте `PrivateKey`, `PresharedKey`, `auth.json` и AWG `.conf`.
- Не публикуйте полный вывод конфигурации или `awg showconf`.
- Установщик сохраняет рабочий профиль в `/etc/amnezia-codex/awg0.conf` с правами
  `600`.
- Обёртка обеспечивает fail-closed запуск: без активного VPN Codex не стартует.
- Пользователь `root` всё равно может намеренно запустить реальный бинарник в обход
  обёртки; схема защищает штатный запуск и от случайной утечки трафика.
