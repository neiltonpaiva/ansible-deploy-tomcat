#!/bin/bash
# Script de instalação e configuração automática do ambiente Ansible

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se é Amazon Linux
check_os() {
    if [ ! -f /etc/amazon-linux-release ] && [ ! -f /etc/amzn-release ]; then
        warn "Este script foi otimizado para Amazon Linux"
        read -p "Continuar mesmo assim? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# Instalar dependências
install_dependencies() {
    log "Instalando dependências..."
    
    # Atualizar sistema
    sudo yum update -y
    
    # Instalar EPEL se necessário
    if ! rpm -qa | grep -q epel-release; then
        sudo yum install -y epel-release
    fi
    
    # Instalar Ansible
    if ! command -v ansible &> /dev/null; then
        log "Instalando Ansible..."
        sudo yum install -y ansible
    else
        log "Ansible já instalado: $(ansible --version | head -1)"
    fi
    
    # Instalar jq para JSON
    if ! command -v jq &> /dev/null; then
        sudo yum install -y jq
    fi
    
    # Instalar cifs-utils para FSx
    if ! rpm -qa | grep -q cifs-utils; then
        sudo yum install -y cifs-utils
    fi
    
    log "Dependências instaladas com sucesso!"
}

# Configurar SSH
setup_ssh() {
    log "Configurando SSH..."
    
    # Verificar se chave SSH existe
    if [ ! -f ~/.ssh/id_rsa ]; then
        warn "Chave SSH não encontrada. Gerando nova chave..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        log "Chave SSH gerada: ~/.ssh/id_rsa"
        warn "IMPORTANTE: Você precisa copiar esta chave para os servidores frontend!"
    else
        log "Chave SSH encontrada: ~/.ssh/id_rsa"
    fi
    
    # Configurar SSH para não verificar host keys (ambiente controlado)
    if [ ! -f ~/.ssh/config ]; then
        cat > ~/.ssh/config << EOF
Host 172.16.3.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
        chmod 600 ~/.ssh/config
        log "Configuração SSH criada"
    fi
}

# Configurar estrutura do Ansible
setup_ansible_structure() {
    log "Criando estrutura do Ansible..."
    
    # Criar diretórios
    sudo mkdir -p /opt/ansible-deploys/{playbooks,group_vars,host_vars,roles,scripts,logs,backups}
    
    # Definir proprietário
    sudo chown -R ec2-user:ec2-user /opt/ansible-deploys
    chmod 755 /opt/ansible-deploys
    
    # Criar estrutura de logs
    mkdir -p /opt/ansible-deploys/logs
    mkdir -p /opt/ansible-deploys/backups
    
    log "Estrutura criada em /opt/ansible-deploys/"
}

# Configurar FSx mount point
setup_fsx_mount() {
    log "Configurando mount point para FSx..."
    
    # Criar diretório de mount
    sudo mkdir -p /mnt/ansible
    sudo chown ec2-user:ec2-user /mnt/ansible
    
    warn "ATENÇÃO: Você precisa configurar manualmente o FSx:"
    echo "1. Substitua 'fs-xxxxx' pelo ID do seu FSx"
    echo "2. Configure as credenciais corretas"
    echo
    echo "Exemplo de mount manual:"
    echo "sudo mount -t cifs //fs-xxxxx.fsx.us-east-1.amazonaws.com/share /mnt/ansible \\"
    echo "    -o username=admin,password=SuaSenha,uid=ec2-user,gid=ec2-user"
    echo
    echo "Para mount automático, adicione ao /etc/fstab:"
    echo "//fs-xxxxx.fsx.us-east-1.amazonaws.com/share /mnt/ansible cifs credentials=/etc/cifs-credentials,uid=ec2-user,gid=ec2-user,iocharset=utf8 0 0"
}

# Testar conectividade com servidores
test_connectivity() {
    log "Testando conectividade com servidores frontend..."
    
    SERVERS=(172.16.3.54 172.16.3.188 172.16.3.121 172.16.3.57 172.16.3.254 172.16.3.127 172.16.3.19)
    
    for server in "${SERVERS[@]}"; do
        echo -n "Testando $server... "
        if timeout 5 ssh -o ConnectTimeout=3 ec2-user@$server "echo 'OK'" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            warn "Falha na conectividade com $server"
        fi
    done
}

# Criar arquivo de exemplo de configuração
create_example_configs() {
    log "Criando arquivos de exemplo..."
    
    # Criar arquivo de exemplo para credenciais FSx
    cat > /tmp/fsx-credentials-example << EOF
# Exemplo de arquivo /etc/cifs-credentials
# Substitua pelos valores corretos do seu FSx

username=admin
password=SuaSenhaFSx
domain=fsx.amazonaws.com
EOF
    
    warn "Arquivo de exemplo criado: /tmp/fsx-credentials-example"
    warn "Configure as credenciais reais antes de usar!"
}

# Validar instalação
validate_installation() {
    log "Validando instalação..."
    
    # Verificar comandos essenciais
    local commands=("ansible" "jq" "mount.cifs")
    for cmd in "${commands[@]}"; do
        if command -v $cmd &> /dev/null; then
            echo -e "  ✓ $cmd: ${GREEN}OK${NC}"
        else
            echo -e "  ✗ $cmd: ${RED}FALTANDO${NC}"
        fi
    done
    
    # Verificar estrutura de diretórios
    if [ -d "/opt/ansible-deploys" ]; then
        echo -e "  ✓ Estrutura Ansible: ${GREEN}OK${NC}"
    else
        echo -e "  ✗ Estrutura Ansible: ${RED}FALTANDO${NC}"
    fi
    
    # Verificar chave SSH
    if [ -f ~/.ssh/id_rsa ]; then
        echo -e "  ✓ Chave SSH: ${GREEN}OK${NC}"
    else
        echo -e "  ✗ Chave SSH: ${RED}FALTANDO${NC}"
    fi
}

# Menu principal
show_menu() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}    Setup Ansible - Ambiente Tomcat${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo "1. Instalação completa (recomendado)"
    echo "2. Instalar apenas dependências"
    echo "3. Configurar apenas SSH"
    echo "4. Testar conectividade"
    echo "5. Validar instalação"
    echo "0. Sair"
    echo -e "${BLUE}============================================${NC}"
}

# Função principal
main() {
    if [ $# -eq 0 ]; then
        # Modo interativo
        while true; do
            show_menu
            read -p "Escolha uma opção: " choice
            
            case $choice in
                1)
                    check_os
                    install_dependencies
                    setup_ssh
                    setup_ansible_structure
                    setup_fsx_mount
                    create_example_configs
                    test_connectivity
                    validate_installation
                    log "Instalação completa finalizada!"
                    ;;
                2) install_dependencies ;;
                3) setup_ssh ;;
                4) test_connectivity ;;
                5) validate_installation ;;
                0) log "Saindo..."; exit 0 ;;
                *) error "Opção inválida!" ;;
            esac
            
            echo
            read -p "Pressione Enter para continuar..." -r
        done
    else
        # Modo comando
        case "$1" in
            "full") 
                check_os
                install_dependencies
                setup_ssh
                setup_ansible_structure
                setup_fsx_mount
                create_example_configs
                validate_installation
                ;;
            "deps") install_dependencies ;;
            "ssh") setup_ssh ;;
            "test") test_connectivity ;;
            "validate") validate_installation ;;
            *) 
                echo "Uso:"
                echo "  $0           # Modo interativo"
                echo "  $0 full      # Instalação completa"
                echo "  $0 deps      # Apenas dependências"
                echo "  $0 ssh       # Apenas SSH"
                echo "  $0 test      # Testar conectividade"
                echo "  $0 validate  # Validar instalação"
                ;;
        esac
    fi
}

# Executar
main "$@"