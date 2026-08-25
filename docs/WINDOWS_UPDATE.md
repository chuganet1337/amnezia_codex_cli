# Клонирование и обновление проекта на Windows

Все команды ниже выполняются в PowerShell.

## 1. Проверить Git

```powershell
git --version
```

Если команда не найдена, установите Git for Windows, затем закройте и заново
откройте PowerShell.

## 2. Сохранить старую папку

Если сейчас существует отдельная папка
`C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli_ubuntu`, не удаляйте
её. Переименуйте в резервную копию:

```powershell
cd C:\Users\chuga\Documents\projects\linux
Rename-Item amnezia_codex_cli_ubuntu amnezia_codex_cli_ubuntu_backup_20260825
```

Если такой папки нет, пропустите этот шаг.

## 3. Клонировать единый репозиторий

```powershell
cd C:\Users\chuga\Documents\projects\linux
git clone https://github.com/chuganet1337/amnezia_codex_cli.git
cd .\amnezia_codex_cli
git status
```

Ожидаемая локальная структура:

```text
C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli\
├── amnezia_codex_cli_ubuntu\
└── amnezia_codex_cli_centos_bx\
```

Не копируйте `.git` из старой папки. Не переносите AWG `.conf` внутрь нового
репозитория.

## 4. Сравнить старые и новые файлы

```powershell
Compare-Object `
  (Get-ChildItem .\amnezia_codex_cli_ubuntu -File | Select-Object -ExpandProperty Name) `
  (Get-ChildItem ..\amnezia_codex_cli_ubuntu_backup_20260825 -File | Select-Object -ExpandProperty Name)
```

Старую копию оставьте до успешной установки и проверки нового комплекта.

## 5. Получать последующие обновления

```powershell
cd C:\Users\chuga\Documents\projects\linux\amnezia_codex_cli
git status
git pull --ff-only
```

Если `git status` показывает локальные изменения, не выполняйте принудительный
сброс. Сначала сохраните их отдельным коммитом или скопируйте изменённые файлы в
резервную папку.

## 6. Отправить Ubuntu-комплект на сервер

```powershell
scp -r .\amnezia_codex_cli_ubuntu root@SERVER_IP:/root/
scp C:\path\outside\repo\amnezia_for_awg.conf root@SERVER_IP:/root/
```

## 7. Отправить CentOS/BitrixVM-комплект на сервер

```powershell
scp -r .\amnezia_codex_cli_centos_bx root@BITRIX_SERVER_IP:/root/
scp C:\path\outside\repo\amnezia_for_awg.conf root@BITRIX_SERVER_IP:/root/
```

Замените `SERVER_IP`, `BITRIX_SERVER_IP` и путь к конфигурации на фактические
значения. Приватный AWG-профиль храните вне Git-репозитория.
