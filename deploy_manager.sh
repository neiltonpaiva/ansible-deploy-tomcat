#!/bin/bash
# Ansible Tomcat Deploy Manager - Updated Version
# Project: ansible-deploy-tomcat
# User: ansible

set -euo pipefail

# Configurações atualizadas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="/home/ansible/ansible-deploy-tomcat"
FSX_MOUNT="/mnt/ansible"
LOG_DIR="$ANSIBLE_DIR/logs"
BACKUP_DIR="/home/ansible/backups/tomcat"
PROJECT_NAME="ansible-deploy-tomcat"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Funções de log
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Banner do projeto
show_banner() {
    echo -e "${PURPLE}
╔════════════════════════════════════════════════════════╗
║                                                        ║
║           🚀 Ansible Tomcat Deploy Manager            ║
║                                                        ║
║  Project: ${PROJECT_NAME}                    ║
║  User: $(whoami)                                            ║
║  Host: $(hostname)                                     ║
║  Time: $(date '+%Y-%m-%d %H:%M:%S')                          ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
${NC}"
}

# Verificar pré-requisitos
check_prerequisites() {
    local errors=0
    
    info "Verificando pré-requisitos..."
    
    # Verificar se FSx está montado
    if ! mountpoint -q "$FSX_MOUNT"; then
        error "FSx não está montado em $FSX_MOUNT"
        errors=$((errors + 1))
    else
        log "✓ FSx mount verificado: $FSX_MOUNT"
    fi
    
    # Verificar se diretório Ansible existe
    if [ ! -d "$ANSIBLE_DIR" ]; then
        error "Diretório Ansible não encontrado: $ANSIBLE_DIR"
        errors=$((errors + 1))
    else
        log "✓ Diretório projeto verificado: $ANSIBLE_DIR"
    fi
    
    # Verificar se ansible está instalado
    if ! command -v ansible &> /dev/null; then
        error "Ansible não está instalado"
        errors=$((errors + 1))
    else
        log "✓ Ansible verificado: $(ansible --version | head -1)"
    fi
    
    # Verificar diretórios necessários
    mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$FSX_MOUNT/staging" "$FSX_MOUNT/triggers" "$FSX_MOUNT/deployed"
    
    return $errors
}

# Listar updates disponíveis
list_updates() {
    echo -e "${BLUE}
╔════════════════════════════════════════════════════════╗
║               📦 Updates Disponíveis                   ║
╚════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # WAR Updates
    if [ -d "$FSX_MOUNT/staging" ]; then
        echo -e "${GREEN}📦 WAR Updates:${NC}"
        if find "$FSX_MOUNT/staging" -maxdepth 2 -name "war-*" -type d 2>/dev/null | head -1 > /dev/null; then
            find "$FSX_MOUNT/staging" -maxdepth 2 -name "war-*" -type d -printf "  🔸 %P\n" 2>/dev/null | sort -r
        else
            echo "  ℹ️  Nenhum update WAR disponível"
        fi
        echo
        
        echo -e "${CYAN}🔄 Version Updates:${NC}"
        if find "$FSX_MOUNT/staging" -maxdepth 2 -name "version-*" -type d 2>/dev/null | head -1 > /dev/null; then
            find "$FSX_MOUNT/staging" -maxdepth 2 -name "version-*" -type d -printf "  🔸 %P\n" 2>/dev/null | sort -r
        else
            echo "  ℹ️  Nenhum update de versão disponível"
        fi
        echo
    fi
    
    # Triggers pendentes
    if [ -d "$FSX_MOUNT/triggers" ] && ls "$FSX_MOUNT/triggers"/*.json >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Triggers Pendentes:${NC}"
        for trigger in "$FSX_MOUNT/triggers"/*.json; do
            [ -f "$trigger" ] || continue
            filename=$(basename "$trigger" .json)
            echo "  📋 $filename"
            if command -v jq >/dev/null 2>&1; then
                echo "     Type: $(jq -r '.UpdateType' "$trigger" 2>/dev/null || echo 'N/A')"
                echo "     Size: $(numfmt --to=iec "$(jq -r '.Size' "$trigger" 2>/dev/null || echo '0')" 2>/dev/null || echo 'N/A')"
                echo "     User: $(jq -r '.User' "$trigger" 2>/dev/null || echo 'N/A')"
                echo "     Time: $(jq -r '.Timestamp' "$trigger" 2>/dev/null || echo 'N/A')"
            fi
            echo
        done
    else
        echo -e "${GREEN}✅ Nenhum trigger pendente${NC}"
    fi
}

# Health check do cluster
health_check() {
    log "🏥 Verificando saúde do cluster Tomcat..."
    
    cd "$ANSIBLE_DIR"
    
    echo -e "${BLUE}
╔════════════════════════════════════════════════════════╗
║                   🏥 Health Check                     ║
╚════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "${CYAN}1. 🔗 Conectividade SSH:${NC}"
    if ansible -i inventory.yml frontend_servers -m ping --one-line; then
        log "✓ Conectividade SSH OK"
    else
        error "✗ Problemas de conectividade SSH"
    fi
    echo
    
    echo -e "${CYAN}2. ⚙️  Status do Tomcat:${NC}"
    if ansible -i inventory.yml frontend_servers -m shell -a "systemctl is-active tomcat" --one-line; then
        log "✓ Serviços Tomcat OK"
    else
        warn "⚠ Alguns serviços Tomcat podem estar com problemas"
    fi
    echo
    
    echo -e "${CYAN}3. 💾 Espaço em Disco:${NC}"
    ansible -i inventory.yml frontend_servers -m shell -a "df -h /opt/tomcat | tail -1" --one-line
    echo
    
    echo -e "${CYAN}4. 🧠 Memória:${NC}"
    ansible -i inventory.yml frontend_servers -m shell -a "free -h | head -2" --one-line
    echo
    
    echo -e "${CYAN}5. 🔍 Processos Java:${NC}"
    ansible -i inventory.yml frontend_servers -m shell -a "pgrep -f java | wc -l" --one-line
}

# Deploy de WAR
deploy_war() {
    local update_path=$1
    local full_path="$FSX_MOUNT/staging/$update_path"
    
    if [ ! -d "$full_path" ]; then
        error "Update não encontrado: $update_path"
        return 1
    fi
    
    echo -e "${PURPLE}
╔════════════════════════════════════════════════════════╗
║                   🚀 Deploy WAR                       ║
╚════════════════════════════════════════════════════════╝${NC}"
    
    log "Iniciando deploy de WAR: $update_path"
    info "Source: $full_path"
    info "Projeto: $PROJECT_NAME"
    
    # Preparar variáveis
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$LOG_DIR/deploy-war-$timestamp.log"
    
    # Confirmação
    echo
    warn "Deploy WAR será executado em 2 servidores simultâneos"
    read -p "Continuar com o deploy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deploy cancelado pelo usuário"
        return 1
    fi
    
    # Executar playbook
    cd "$ANSIBLE_DIR"
    log "Executando playbook update-war.yml..."
    
    if ansible-playbook -i inventory.yml playbooks/update-war.yml \
        -e "update_source=$full_path" \
        -e "deploy_timestamp=$timestamp" \
        -e "project_name=$PROJECT_NAME" \
        | tee "$log_file"; then
        
        local result=${PIPESTATUS[0]}
        
        if [ $result -eq 0 ]; then
            echo -e "${GREEN}
╔════════════════════════════════════════════════════════╗
║                  ✅ DEPLOY SUCESSO                    ║
╚════════════════════════════════════════════════════════╝${NC}"
            
            log "Deploy WAR concluído com sucesso!"
            
            # Mover para histórico
            [ -d "$FSX_MOUNT/deployed" ] || mkdir -p "$FSX_MOUNT/deployed"
            mv "$full_path" "$FSX_MOUNT/deployed/$(basename "$update_path")-deployed-$timestamp"
            
            # Remover trigger correspondente
            rm -f "$FSX_MOUNT/triggers/"*"$(basename "$update_path")"*.json
            
            info "Log salvo em: $log_file"
            return 0
        else
            error "Deploy falhou! Verifique o log: $log_file"
            return 1
        fi
    fi
}

# Deploy de versão
deploy_version() {
    local update_path=$1
    local full_path="$FSX_MOUNT/staging/$update_path"
    
    if [ ! -d "$full_path" ]; then
        error "Update não encontrado: $update_path"
        return 1
    fi
    
    echo -e "${RED}
╔════════════════════════════════════════════════════════╗
║                ⚠️  DEPLOY VERSÃO COMPLETA             ║
╚════════════════════════════════════════════════════════╝${NC}"
    
    warn "ATENÇÃO: DEPLOY DE VERSÃO COMPLETA!"
    warn "Isso irá atualizar webapps, Datasul-report e lib"
    warn "Será executado 1 servidor por vez (sequencial)"
    warn "Tempo estimado: 30-45 minutos"
    
    echo
    log "Source: $full_path"
    log "Projeto: $PROJECT_NAME"
    
    read -p "⚠️  Tem certeza? Digite 'CONFIRMAR' para continuar: " confirmation
    if [ "$confirmation" != "CONFIRMAR" ]; then
        log "Deploy cancelado pelo usuário"
        return 1
    fi
    
    log "🚀 Iniciando deploy de versão: $update_path"
    
    # Preparar variáveis
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$LOG_DIR/deploy-version-$timestamp.log"
    
    # Executar playbook
    cd "$ANSIBLE_DIR"
    log "Executando playbook update-version.yml..."
    
    if ansible-playbook -i inventory.yml playbooks/update-version.yml \
        -e "update_source=$full_path" \
        -e "deploy_timestamp=$timestamp" \
        -e "project_name=$PROJECT_NAME" \
        | tee "$log_file"; then
        
        local result=${PIPESTATUS[0]}
        
        if [ $result -eq 0 ]; then
            echo -e "${GREEN}
╔════════════════════════════════════════════════════════╗
║               ✅ DEPLOY VERSÃO SUCESSO                ║
╚════════════════════════════════════════════════════════╝${NC}"
            
            log "Deploy de versão concluído com sucesso!"
            
            # Mover para histórico
            [ -d "$FSX_MOUNT/deployed" ] || mkdir -p "$FSX_MOUNT/deployed"
            mv "$full_path" "$FSX_MOUNT/deployed/$(basename "$update_path")-deployed-$timestamp"
            
            # Remover trigger correspondente
            rm -f "$FSX_MOUNT/triggers/"*"$(basename "$update_path")"*.json
            
            info "Log salvo em: $log_file"
            return 0
        else
            error "Deploy de versão falhou! Verifique o log: $log_file"
            return 1
        fi
    fi
}

# Menu principal
show_menu() {
    echo -e "${BLUE}
╔════════════════════════════════════════════════════════╗
║                      📋 MENU                          ║
╚════════════════════════════════════════════════════════╝${NC}"
    echo "1. 📦 Listar updates disponíveis"
    echo "2. 🏥 Health check do cluster"
    echo "3. 🚀 Deploy WAR"
    echo "4. 🔄 Deploy Versão Completa"
    echo "5. ↩️  Rollback"
    echo "6. 📄 Ver logs recentes"
    echo "7. 📊 Status do projeto"
    echo "0. 🚪 Sair"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
}

# Status do projeto
show_project_status() {
    echo -e "${CYAN}
╔════════════════════════════════════════════════════════╗
║                   📊 Status Projeto                   ║
╚════════════════════════════════════════════════════════╝${NC}"
    
    echo "🏷️  Projeto: $PROJECT_NAME"
    echo "📁 Diretório: $ANSIBLE_DIR"
    echo "💾 FSx Mount: $FSX_MOUNT"
    echo "👤 Usuário: $(whoami)"
    echo "🏠 Home: $HOME"
    echo
    
    echo "📈 Estatísticas:"
    echo "  • Logs: $(find "$LOG_DIR" -name "*.log" 2>/dev/null | wc -l) arquivos"
    echo "  • Backups: $(find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | wc -l) arquivos"
    echo "  • Deploys: $(ls "$FSX_MOUNT/deployed" 2>/dev/null | wc -l) realizados"
    echo "  • Triggers: $(ls "$FSX_MOUNT/triggers"/*.json 2>/dev/null | wc -l) pendentes"
    echo
    
    echo "🔗 Conectividade:"
    if ansible -i "$ANSIBLE_DIR/inventory.yml" frontend_servers -m ping -o >/dev/null 2>&1; then
        echo "  • SSH: ✅ OK"
    else
        echo "  • SSH: ❌ Problemas"
    fi
    
    if mountpoint -q "$FSX_MOUNT"; then
        echo "  • FSx: ✅ Montado"
    else
        echo "  • FSx: ❌ Não montado"
    fi
}

# Programa principal
main() {
    # Mostrar banner
    show_banner
    
    # Verificar pré-requisitos
    if ! check_prerequisites; then
        error "Pré-requisitos não atendidos. Verifique a instalação."
        exit 1
    fi
    
    if [ $# -eq 0 ]; then
        # Modo interativo
        while true; do
            echo
            show_menu
            read -p "Escolha uma opção: " choice
            echo
            
            case $choice in
                1) list_updates ;;
                2) health_check ;;
                3) 
                    list_updates
                    echo
                    read -p "Digite o path do WAR update: " war_path
                    if [ -n "$war_path" ]; then
                        deploy_war "$war_path"
                    else
                        warn "Path não informado"
                    fi
                    ;;
                4)
                    list_updates
                    echo
                    read -p "Digite o path do version update: " version_path
                    if [ -n "$version_path" ]; then
                        deploy_version "$version_path"
                    else
                        warn "Path não informado"
                    fi
                    ;;
                5)
                    log "Iniciando rollback..."
                    cd "$ANSIBLE_DIR"
                    ansible-playbook -i inventory.yml playbooks/rollback.yml
                    ;;
                6)
                    echo -e "${BLUE}📄 Logs Recentes:${NC}"
                    if [ -d "$LOG_DIR" ]; then
                        ls -la "$LOG_DIR" | tail -10
                        echo
                        read -p "Ver conteúdo de algum log? (filename ou Enter): " log_choice
                        if [ -n "$log_choice" ] && [ -f "$LOG_DIR/$log_choice" ]; then
                            less "$LOG_DIR/$log_choice"
                        fi
                    else
                        warn "Diretório de logs não encontrado"
                    fi
                    ;;
                7) show_project_status ;;
                0) 
                    echo -e "${GREEN}
╔════════════════════════════════════════════════════════╗
║                    👋 Até logo!                       ║
╚════════════════════════════════════════════════════════╝${NC}"
                    exit 0 
                    ;;
                *) error "Opção inválida! Tente novamente." ;;
            esac
            
            echo
            read -p "Pressione Enter para continuar..." -r
        done
    else
        # Modo comando
        case "$1" in
            "list"|"ls") list_updates ;;
            "health"|"check") health_check ;;
            "status") show_project_status ;;
            "deploy-war") 
                [ -z "$2" ] && { error "Uso: $0 deploy-war <path>"; exit 1; }
                deploy_war "$2" 
                ;;
            "deploy-version")
                [ -z "$2" ] && { error "Uso: $0 deploy-version <path>"; exit 1; }
                deploy_version "$2"
                ;;
            "rollback")
                cd "$ANSIBLE_DIR"
                ansible-playbook -i inventory.yml playbooks/rollback.yml
                ;;
            *) 
                echo "Uso:"
                echo "  $0                           # Modo interativo"
                echo "  $0 list                      # Listar updates"
                echo "  $0 health                    # Health check"
                echo "  $0 status                    # Status do projeto"
                echo "  $0 deploy-war <path>         # Deploy WAR"
                echo "  $0 deploy-version <path>     # Deploy versão"
                echo "  $0 rollback                  # Rollback"
                ;;
        esac
    fi
}

# Executar função principal
main "$@"