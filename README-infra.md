# SOL CBM-RS — Infraestrutura Local Windows

## Visão Geral

Infraestrutura para rodar o SOL de forma autônoma em um servidor Windows 11 Pro,
sem dependências externas da PROCERGS.

## Serviços e Portas

| Serviço       | Porta     | URL                              | Usuário / Senha                  |
|---------------|-----------|----------------------------------|----------------------------------|
| Nginx         | 80        | http://localhost                 | —                                |
| SOL Backend   | 8080      | http://localhost:8080/api/health | (JWT via Keycloak)               |
| Keycloak      | 8180      | http://localhost:8180            | admin / Keycloak@Admin2026       |
| Oracle XE     | 1521      | jdbc:oracle:thin:@localhost:1521:XE | sol / Sol@CBM2026             |
| MinIO API     | 9000      | http://localhost:9000            | sol-app / SolApp@Minio2026       |
| MinIO Console | 9001      | http://localhost:9001            | solminio / MinIO@SOL2026         |

## Sequência de Instalação (Sprint 0)

Execute como Administrador, na ordem:

```powershell
# 1. Pre-requisitos (Java 21, Node 20, Maven, NSSM, Git, Angular CLI)
.\infra\scripts\00-prerequisites.ps1

# 2. Oracle XE — instalar MANUALMENTE antes:
#    https://www.oracle.com/database/technologies/xe-downloads.html
#    Depois configurar schema SOL:
.\infra\scripts\01-oracle-xe.ps1 -SysPassword <senha_do_instalador>

# 3. Keycloak
.\infra\scripts\02-keycloak.ps1

# 4. MinIO
.\infra\scripts\03-minio.ps1

# 5. Nginx
.\infra\scripts\04-nginx.ps1

# 6. Compilar backend e registrar como servico
cd C:\SOL\backend
mvn clean package -DskipTests
cd C:\SOL
.\infra\scripts\05-sol-service.ps1

# 7. Importar realm Keycloak
.\infra\scripts\06-keycloak-realm.ps1

# 8. Criar buckets MinIO
.\infra\scripts\07-minio-buckets.ps1

# 9. Verificar tudo
.\infra\scripts\08-verify-all.ps1
```

## Gerenciamento dos Servicos

```powershell
# Parar tudo
Stop-Service SOL-Backend, SOL-Nginx, SOL-Keycloak, SOL-MinIO

# Iniciar tudo (na ordem correta)
Start-Service SOL-MinIO
Start-Service SOL-Keycloak
Start-Sleep -Seconds 15
Start-Service SOL-Backend
Start-Service SOL-Nginx

# Status
Get-Service SOL-* | Select-Object Name, Status, StartType

# Logs em tempo real
Get-Content C:\SOL\logs\sol-backend-stdout.log -Tail 50 -Wait
Get-Content C:\SOL\logs\keycloak.log -Tail 50 -Wait
Get-Content C:\SOL\logs\nginx-access.log -Tail 50 -Wait
```

## Estrutura de Diretorios

```
C:\SOL\
├── infra\
│   ├── scripts\          # Scripts PowerShell 00-08
│   ├── keycloak\         # sol-realm.json
│   ├── minio\            # mc.exe (MinIO Client)
│   └── nginx\            # nginx.conf (copia)
├── backend\              # Projeto Spring Boot 3
│   ├── pom.xml
│   ├── src\
│   └── target\           # JAR compilado
├── frontend\             # Projeto Angular 18
│   ├── package.json
│   ├── angular.json
│   ├── src\
│   └── dist\             # Build de producao
├── data\
│   ├── oracle\           # Datafiles Oracle XE
│   ├── keycloak\         # Banco H2 do Keycloak
│   └── minio\            # Objetos (arquivos SOL)
├── logs\                 # Logs de todos os servicos
├── instaladores\         # Arquivos baixados (.zip, .exe)
└── certs\                # Certificados TLS (para producao HTTPS)
```

## Compilacao e Deploy do Backend

```powershell
cd C:\SOL\backend

# Compilar (primeira vez ou apos alteracoes)
mvn clean package -DskipTests

# Reiniciar o servico para aplicar o novo JAR
Stop-Service SOL-Backend
Start-Sleep -Seconds 5
Start-Service SOL-Backend

# Verificar
Invoke-RestMethod http://localhost:8080/api/health
```

## Compilacao e Deploy do Frontend

```powershell
cd C:\SOL\frontend

# Instalar dependencias (primeira vez)
npm install

# Build de producao
npm run build:prod

# O Nginx ja serve os arquivos de C:\SOL\frontend\dist\sol-frontend\browser\
# Nenhum reinicio necessario — Nginx serve os arquivos estaticos diretamente
```

## Senhas Padrao (ALTERAR EM PRODUCAO)

Todas as senhas foram definidas nos scripts de instalacao.
Em producao, substitua por senhas fortes e armazene em cofre de segredos.

## Observacoes de Producao

- Habilitar HTTPS: obter certificado (autoassinado ou Let's Encrypt) e configurar no Nginx
- Keycloak: alterar para banco Oracle XE ao inves do H2 embutido (mais robusto)
- Windows Update: configurar janela de manutencao para evitar reinicializacoes inesperadas
- Backup: configurar backup diario de C:\SOL\data\ (Oracle, Keycloak, MinIO)
- Monitoramento: configurar alertas de servico com o Windows Task Scheduler
