#!/bin/bash
# Monitor deployment in real-time
# Projeto: ansible-deploy-tomcat
# Usuário: ansible

set -euo pipefail

# Configurações
PROJECT_NAME="ansible-deploy-tomcat"
TOMCAT_LOG="/opt/tomcat/current/logs/catalina.out"
PROJECT_DIR="/home/ansible/ansible-deploy-tomcat"
DEPLOY_LOG="$PROJECT_DIR/logs/current-deploy.log"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Servidores frontend
SERVERS=(172.16.3.54 172.16.3.188 172.16.3.121 172.16.3.57 172.16.3.254 172.16.3.127 172.16.3.19)

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
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

# Banner
show_banner() {
    echo -e "${CYAN}
╔════════════════════════════════════════════════════════╗
║              📊 Deployment Monitor                    ║
║              Projeto: $PROJECT_NAME           ║
╚════════════════════════════════════════════════════════╝${NC}"
}

# Monitor logs durante deploy - versão melhorada
monitor_server_deploy() {
    local server=$1
    local duration=${2:-300}  # 5 minutos default
    local log_file="/tmp/monitor_${server}_$$.log"
    
    info "🔍 Monitorando $server por $duration segundos..."
    
    # Conectar via SSH e monitorar logs
    {
        ssh ec2-user@$server "
            echo '[$(date)] Iniciando monitoramento em $server'
            
            # Monitorar logs do Tomcat com timeout
            timeout $duration tail -f $TOMCAT_LOG 2>/dev/null | while read line; do
                timestamp=\$(date '+%H:%M:%S')
                
                # Filtrar linhas importantes
                if echo \"\$line\" | grep -qE 'Deployment|ERROR|startup|Exception|SEVERE|WARNING|Started|Stopped'; then
                    echo \"[\$timestamp] \$line\"
                fi
                
                # Parar se detectar conclusão
                if echo \"\$line\" | grep -q 'Server startup in'; then
                    echo \"[\$timestamp] ✅ Startup completo detectado\"
                    break
                fi
                
                if echo \"\$line\" | grep -q 'Deployment of web application.*has finished'; then
                    echo \"[\$timestamp] ✅ Deploy de aplicação completo\"
                    break
                fi
            done
        " 2>/dev/null | while IFS= read -r line; do
        echo -e "${CYAN}[$server]${NC} $line"
    done > "$log_file" 2>&1 &
    
    local ssh_pid=$!
    echo $ssh_pid > "/tmp/monitor_${server}_pid.tmp"
    
    # Aguardar conclusão ou timeout
    sleep $duration
    
    # Finalizar processo SSH se ainda estiver rodando
    if kill -0 $ssh_pid 2>/dev/null; then
        kill $ssh_pid 2>/dev/null
        wait $ssh_pid 2>/dev/null || true
    fi
    
    # Mostrar resumo do servidor
    if [ -f "$log_file" ]; then
        local lines=$(wc -l < "$log_file")
        if [ $lines -gt 0 ]; then
            log "📋 Servidor $server: $lines eventos capturados"
        else
            warn "📋 Servidor $server: nenhum evento capturado"
        fi
    fi
    
    # Limpeza
    rm -f "$log_file" "/tmp/monitor_${server}_pid.tmp"
}

# Monitor específico para deploy WAR
monitor_war_deploy() {
    local duration=${1:-600}  # 10 minutos para WAR
    
    log "🚀 Iniciando monitoramento de Deploy WAR"
    info "⏱️  Duração: $duration segundos"
    info "🎯 Servidores: ${#SERVERS[@]}"
    
    echo ""
    
    # Monitorar 3 servidores simultâneos (WAR deploy usa paralelismo)
    for i in "${!SERVERS[@]}"; do
        monitor_server_deploy "${SERVERS[$i]}" $duration &
        
        # Pausa entre inicializações para não sobrecarregar
        sleep 2
        
        # Máximo de 3 processos simultâneos
        if [ $(((i + 1) % 3)) -eq 0 ]; then
            wait
        fi
    done
    
    wait
    log "✅ Monitoramento WAR concluído"
}

# Monitor específico para deploy de versão
monitor_version_deploy() {
    local duration=${1:-1200}  # 20 minutos para versão completa
    
    log "🔄 Iniciando monitoramento de Deploy Versão"
    info "⏱️  Duração: $duration segundos (versão completa)"
    info "🎯 Modo: Sequencial (um servidor por vez)"
    
    echo ""
    
    # Deploy de versão é sequencial, monitorar um por vez
    for server in "${SERVERS[@]}"; do
        echo -e "${YELLOW}▶️  Focando no servidor: $server${NC}"
        monitor_server_deploy "$server" $((duration / ${#SERVERS[@]}))
        echo ""
        sleep 5
    done
    
    log "✅ Monitoramento Versão concluído"
}

# Monitor em tempo real simples
monitor_realtime() {
    log "📡 Monitor em tempo real - Pressione Ctrl+C para parar"
    
    echo ""
    echo "Servidores monitorados:"
    for i in "${!SERVERS[@]}"; do
        echo "  $((i+1)). ${SERVERS[$i]}"
    done
    echo ""
    
    # Trap para limpeza
    trap 'echo -e "\n${YELLOW}🛑 Parando monitoramento...${NC}"; cleanup_monitoring; exit 0' INT
    
    # Monitorar todos os servidores indefinidamente
    for server in "${SERVERS[@]}"; do
        {
            ssh ec2-user@$server "tail -f $TOMCAT_LOG 2>/dev/null" | while IFS= read -r line; do
                if echo "$line" | grep -qE 'ERROR|SEVERE|Exception|Deployment|startup'; then
                    timestamp=$(date '+%H:%M:%S')
                    echo -e "${CYAN}[$server $timestamp]${NC} $line"
                fi
            done
        } &
    done
    
    # Aguardar indefinidamente
    wait
}

# Cleanup de processos de monitoramento
cleanup_monitoring() {
    info "🧹 Limpando processos de monitoramento..."
    
    # Matar processos SSH em background
    pkill -f "ssh.*tail.*catalina.out" 2>/dev/null || true
    
    # Remover arquivos temporários
    rm -f /tmp/monitor_*_pid.tmp /tmp/monitor_*.log
    
    log "✅ Limpeza concluída"
}

# Mostrar ajuda
show_help() {
    echo "Uso: $0 [OPÇÃO] [DURAÇÃO]"
    echo ""
    echo "Opções:"
    echo "  war         Monitor para deploy WAR (default: 600s)"
    echo "  version     Monitor para deploy Versão (default: 1200s)"
    echo "  realtime    Monitor contínuo em tempo real"
    echo "  health      Verificação rápida de saúde"
    echo "  help        Mostrar esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  $0 war 300              # Monitor WAR por 5 minutos"
    echo "  $0 version 1800         # Monitor Versão por 30 minutos"
    echo "  $0 realtime             # Monitor contínuo"
    echo ""
}

# Verificação rápida de saúde
health_check() {
    log "🏥 Verificação rápida de saúde dos servidores"
    
    echo ""
    for i in "${!SERVERS[@]}"; do
        local server="${SERVERS[$i]}"
        echo -n "  $((i+1)). $server ... "
        
        # Teste rápido de conectividade e status Tomcat
        if timeout 5 ssh ec2-user@$server "systemctl is-active tomcat >/dev/null 2>&1" 2>/dev/null; then
            echo -e "${GREEN}✅ OK${NC}"
        else
            echo -e "${RED}❌ PROBLEMA${NC}"
        fi
    done
    echo ""
}

# Função principal
main() {
    show_banner
    
    local mode=${1:-"help"}
    local duration=${2:-""}
    
    case $mode in
        "war")
            [ -n "$duration" ] && monitor_war_deploy $duration || monitor_war_deploy
            ;;
        "version")
            [ -n "$duration" ] && monitor_version_deploy $duration || monitor_version_deploy
            ;;
        "realtime"|"rt")
            monitor_realtime
            ;;
        "health"|"check")
            health_check
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Opção inválida: $mode"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Executar apenas se chamado diretamente
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi