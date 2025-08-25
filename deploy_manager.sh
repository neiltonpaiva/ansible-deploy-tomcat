#!/bin/bash
# Deploy Manager Script

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="/opt/ansible-deploys"
FSX_MOUNT="/mnt/ansible"
LOG_DIR="$ANSIBLE_DIR/logs"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se FSx está montado
check_fsx_mount() {
    if ! mountpoint -q "$FSX_MOUNT"; then
        error "FSx não está montado em $FSX_MOUNT"
        return 1
    fi
    log "FSx mount verificado: $FSX_MOUNT"
}

# Listar updates disponíveis
list_updates() {
    echo -e "${BLUE}=== Updates Disponíveis no FSx ===${NC}"
    echo
    
    # WAR Updates
    if [ -d "$FSX_MOUNT/staging" ]; then
        echo -e "${GREEN}📦 WAR Updates:${NC}"
        find "$FSX_MOUNT/staging" -maxdepth 2 -name "war-*" -type d -printf "  %P\n" 2>/dev/null | sort -r
        echo
        
        echo -e "${GREEN}🔄 Version Updates:${NC}"
        find "$FSX_MOUNT/staging" -maxdepth 2 -name "version-*" -type d -printf "  %P\n" 2>/dev/null | sort -r
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
                echo "     Type: $(jq -r '.UpdateType' "$trigger")"
                echo "     Size: $(numfmt --to=iec "$(jq -r '.Size' "$trigger")")"
                echo "     User: $(jq -r '.User' "$trigger")"
                echo "     Time: $(jq -r '.Timestamp' "$trigger")"
            fi
            echo
        done
    fi
}

# Health check do cluster
health_check() {
    log "Verificando saúde do cluster..."
    
    cd "$ANSIBLE_DIR"
    
    echo -e "${BLUE}=== Conectividade ===${NC}"
    ansible -i inventory.yml frontend_servers -m ping --one-line
    
    echo -e "${BLUE}=== Status do Tomcat ===${NC}"
    ansible -i inventory.yml frontend_servers -m shell -a "systemctl is-active tomcat" --one-line
    
    echo -e "${BLUE}=== Espaço em Disco ===${NC}"
    ansible -i inventory.yml frontend_servers -m shell -a "df -h /opt/tomcat | tail -1" --one-line
    
    echo -e "${BLUE}=== Memória ===${NC}"
    ansible -i inventory.yml frontend_servers -m shell -a "free -h | head -2" --one-line
}

# Deploy de WAR
deploy_war() {
    local update_path=$1
    local full_path="$FSX_MOUNT/staging/$update_path"
    
    if [ ! -d "$full_path" ]; then
        error "Update não encontrado: $update_path"
        return 1
    fi
    
    log "Iniciando deploy de WAR: $update_path"
    
    # Preparar variáveis
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$LOG_DIR/deploy-version-$timestamp.log"
    
    # Executar playbook
    cd "$ANSIBLE_DIR"
    ansible-playbook -i inventory.yml playbooks/update-version.yml \
        -e "update_source=$full_path" \
        -e "deploy_timestamp=$timestamp" \
        | tee "$log_file"
    
    local result=${PIPESTATUS[0]}
    
    if [ $result -eq 0 ]; then
        log "Deploy de versão concluído com sucesso!"
        # Mover para histórico
        [ -d "$FSX_MOUNT/deployed" ] || mkdir -p "$FSX_MOUNT/deployed"
        mv "$full_path" "$FSX_MOUNT/deployed/$(basename "$update_path")-deployed-$timestamp"
        
        # Remover trigger correspondente
        rm -f "$FSX_MOUNT/triggers/"*"$(basename "$update_path")"*.json
    else
        error "Deploy de versão falhou! Verifique o log: $log_file"
        return 1
    fi
}

# Menu principal
show_menu() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}        Deploy Manager - Tomcat${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo "1. Listar updates disponíveis"
    echo "2. Health check do cluster"
    echo "3. Deploy WAR"
    echo "4. Deploy Versão"
    echo "5. Rollback"
    echo "6. Ver logs recentes"
    echo "0. Sair"
    echo -e "${BLUE}===========================================${NC}"
}

# Programa principal
main() {
    # Verificar pré-requisitos
    check_fsx_mount || exit 1
    
    if [ $# -eq 0 ]; then
        # Modo interativo
        while true; do
            show_menu
            read -p "Escolha uma opção: " choice
            
            case $choice in
                1) list_updates ;;
                2) health_check ;;
                3) 
                    list_updates
                    read -p "Digite o path do WAR update: " war_path
                    deploy_war "$war_path"
                    ;;
                4)
                    list_updates
                    read -p "Digite o path do version update: " version_path
                    deploy_version "$version_path"
                    ;;
                5)
                    cd "$ANSIBLE_DIR"
                    ansible-playbook -i inventory.yml playbooks/rollback.yml
                    ;;
                6)
                    echo -e "${BLUE}=== Logs Recentes ===${NC}"
                    ls -la "$LOG_DIR" | tail -10
                    read -p "Ver conteúdo de algum log? (filename ou Enter para voltar): " log_choice
                    if [ -n "$log_choice" ] && [ -f "$LOG_DIR/$log_choice" ]; then
                        less "$LOG_DIR/$log_choice"
                    fi
                    ;;
                0) log "Saindo..."; exit 0 ;;
                *) error "Opção inválida!" ;;
            esac
            
            echo
            read -p "Pressione Enter para continuar..." -r
        done
    else
        # Modo comando
        case "$1" in
            "list") list_updates ;;
            "health") health_check ;;
            "deploy-war") 
                [ -z "$2" ] && { error "Uso: $0 deploy-war <path>"; exit 1; }
                deploy_war "$2" 
                ;;
            "deploy-version")
                [ -z "$2" ] && { error "Uso: $0 deploy-version <path>"; exit 1; }
                deploy_version "$2"
                ;;
            *) 
                echo "Uso:"
                echo "  $0                           # Modo interativo"
                echo "  $0 list                      # Listar updates"
                echo "  $0 health                    # Health check"
                echo "  $0 deploy-war <path>         # Deploy WAR"
                echo "  $0 deploy-version <path>     # Deploy versão"
                ;;
        esac
    fi
}

# Executar função principal
main "$@"$LOG_DIR/deploy-war-$timestamp.log"
    
    # Executar playbook
    cd "$ANSIBLE_DIR"
    ansible-playbook -i inventory.yml playbooks/update-war.yml \
        -e "update_source=$full_path" \
        -e "deploy_timestamp=$timestamp" \
        | tee "$log_file"
    
    local result=${PIPESTATUS[0]}
    
    if [ $result -eq 0 ]; then
        log "Deploy WAR concluído com sucesso!"
        # Mover para histórico
        [ -d "$FSX_MOUNT/deployed" ] || mkdir -p "$FSX_MOUNT/deployed"
        mv "$full_path" "$FSX_MOUNT/deployed/$(basename "$update_path")-deployed-$timestamp"
        
        # Remover trigger correspondente
        rm -f "$FSX_MOUNT/triggers/"*"$(basename "$update_path")"*.json
    else
        error "Deploy falhou! Verifique o log: $log_file"
        return 1
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
    
    warn "DEPLOY DE VERSÃO COMPLETA!"
    warn "Isso irá atualizar webapps, Datasul-report e lib"
    read -p "Continuar? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deploy cancelado pelo usuário"
        return 1
    fi
    
    log "Iniciando deploy de versão: $update_path"
    
    # Preparar variáveis
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="