#!/bin/bash
# Script de instalação e configuração do Ansible

set -euo pipefail

# Variáveis
ANSIBLE_DIR="/opt/ansible-deploys"
FSX_MOUNT="/mnt/ansible"
FSX_ENDPOINT="fs-xxxxx.fsx.us-east-1.amazonaws.com"  # SUBSTITUIR pelo seu endpoint
FSX_SHARE="share"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para instalar dependências
install_dependencies() {
    log "Instalando dependências..."
    
    # Detectar sistema operacional
    if [ -f /etc/amazon-linux-release ]; then
        log "Amazon Linux detectado"
        sudo yum update -y
        sudo yum install -y epel-release
        sudo yum install -y ansible jq cifs-utils rsync
    elif [ -f /etc/redhat-release ]; then
        log "RedHat/CentOS detectado"
        sudo yum install -y epel-release
        sudo yum install -y ansible jq cifs-utils rsync
    elif [ -f /etc/debian_version ]; then
        log "Debian/Ubuntu detectado"
        sudo apt update
        sudo apt install -y ansible jq cifs-utils rsync
    else
        error "Sistema operacional não suportado"
        exit 1
    fi
    
    log "Dependências instaladas com sucesso"
}

# Função para configurar FSx
setup_fsx() {
    log "Configurando FSx mount..."
    
    # Criar ponto de montagem
    sudo mkdir -p "$FSX_MOUNT"
    
    # Solicitar credenciais FSx
    echo
    warn "Configuração do FSx necessária:"
    read -p "Endpoint FSx (ex: fs-xxxxx.fsx.us-east-1.amazonaws.com): " fsx_endpoint
    read -p "Username FSx: " fsx_username
    read -s -p "Password FSx: " fsx_password
    echo
    
    # Criar arquivo de credenciais
    sudo tee /etc/cifs-credentials > /dev/null << EOF
username=$fsx_username
password=$fsx_password
domain=fsx
EOF
    sudo chmod 600 /etc/cifs-credentials
    
    # Testar mount
    log "Testando mount FSx..."
    sudo mount -t cifs "//$fsx_endpoint/$FSX_SHARE" "$FSX_MOUNT" \
        -o credentials=/etc/cifs-credentials,uid=$(id -u),gid=$(id -g),iocharset=utf8
    
    if mountpoint -q "$FSX_MOUNT"; then
        log "FSx montado com sucesso em $FSX_MOUNT"
        
        # Adicionar ao fstab
        if ! grep -q "$FSX_MOUNT" /etc/fstab; then
            echo "//$fsx_endpoint/$FSX_SHARE $FSX_MOUNT cifs credentials=/etc/cifs-credentials,uid=$(id -u),gid=$(id -g),iocharset=utf8 0 0" | sudo tee -a /etc/fstab
            log "FSx adicionado ao /etc/fstab para mount automático"
        fi
    else
        error "Falha ao montar FSx"
        exit 1
    fi
}

# Função para configurar SSH
setup_ssh() {
    log "Configurando SSH..."
    
    if [ ! -f ~/.ssh/id_rsa ]; then
        warn "Chave SSH não encontrada. Gerando nova chave..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        log "Chave SSH gerada em ~/.ssh/id_rsa"
        warn "IMPORTANTE: Copie a chave pública para os servidores frontend:"
        cat ~/.ssh/id_rsa.pub
    fi
    
    # Testar conectividade
    log "Testando conectividade SSH com servidores frontend..."
    SERVERS=(172.16.3.54 172.16.3.188 172.16.3.121 172.16.3.57 172.16.3.254 172.16.3.127 172.16.3.19)
    
    for server in "${SERVERS[@]}"; do
        if ssh -o ConnectTimeout=5 -o BatchMode=yes ec2-user@$server "echo 'OK'" >/dev/null 2>&1; then
            log "✓ Conectividade OK: $server"
        else
            warn "✗ Problema de conectividade: $server"
        fi
    done
}

# Função para criar estrutura de diretórios
create_structure() {
    log "Criando estrutura de diretórios..."
    
    # Criar diretório principal
    sudo mkdir -p "$ANSIBLE_DIR"
    sudo chown $(id -u):$(id -g) "$ANSIBLE_DIR"
    
    # Criar subdiretórios
    mkdir -p "$ANSIBLE_DIR"/{playbooks,group_vars,host_vars,roles,scripts,logs,backups}
    
    # Criar estrutura FSx
    mkdir -p "$FSX_MOUNT"/{staging,triggers,deployed,history,logs}
    
    log "Estrutura de diretórios criada"
}

# Função para instalar configurações Ansible
install_ansible_config() {
    log "Instalando configurações do Ansible..."
    
    cd "$ANSIBLE_DIR"
    
    # Aqui você copiaria os arquivos de configuração
    # Por enquanto, apenas criamos as estruturas básicas
    
    log "IMPORTANTE: Copie os arquivos de configuração para os seguintes locais:"
    echo "  - ansible.cfg -> $ANSIBLE_DIR/ansible.cfg"
    echo "  - inventory.yml -> $ANSIBLE_DIR/inventory.yml"
    echo "  - group_vars/all.yml -> $ANSIBLE_DIR/group_vars/all.yml"
    echo "  - group_vars/frontend_servers.yml -> $ANSIBLE_DIR/group_vars/frontend_servers.yml"
    echo "  - playbooks/*.yml -> $ANSIBLE_DIR/playbooks/"
    echo "  - scripts/*.sh -> $ANSIBLE_DIR/scripts/"
}

# Função para testar configuração
test_setup() {
    log "Testando configuração..."
    
    cd "$ANSIBLE_DIR"
    
    if [ -f "inventory.yml" ]; then
        log "Testando conectividade Ansible..."
        ansible -i inventory.yml all -m ping
    else
        warn "arquivo inventory.yml não encontrado. Teste manual necessário."
    fi
}

# Menu principal
main() {
    echo "========================================"
    echo "    Setup Ansible Deploy Environment"
    echo "========================================"
    echo
    
    log "Iniciando configuração do ambiente..."
    
    # 1. Instalar dependências
    install_dependencies
    
    # 2. Configurar FSx
    setup_fsx
    
    # 3. Configurar SSH
    setup_ssh
    
    # 4. Criar estrutura
    create_structure
    
    # 5. Instalar configurações
    install_ansible_config
    
    # 6. Tornar scripts executáveis
    if [ -d "$ANSIBLE_DIR/scripts" ]; then
        chmod +x "$ANSIBLE_DIR/scripts"/*.sh 2>/dev/null || true
    fi
    
    echo
    log "Setup concluído!"
    echo
    echo "Próximos passos:"
    echo "1. Copie os arquivos de configuração para $ANSIBLE_DIR"
    echo "2. Execute: cd $ANSIBLE_DIR && ansible -i inventory.yml all -m ping"
    echo "3. Teste o deploy manager: $ANSIBLE_DIR/scripts/deploy-manager.sh"
    echo
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi