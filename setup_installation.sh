#!/bin/bash
# Script de instalação e configuração automática
# Projeto: ansible-deploy-tomcat
# Usuário dedicado: ansible

set -euo pipefail

# Configurações do projeto
PROJECT_NAME="ansible-deploy-tomcat"
ANSIBLE_USER="ansible"
PROJECT_DIR="/home/$ANSIBLE_USER/$PROJECT_NAME"
GITHUB_REPO="your-username/$PROJECT_NAME"  # Atualizar com seu repo

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

# Banner
show_banner() {
    echo -e "${PURPLE}
╔════════════════════════════════════════════════════════╗
║                                                        ║
║        🛠️  Setup Ansible Tomcat Deploy Environment    ║
║                                                        ║
║  Projeto: ${PROJECT_NAME}                    ║
║  Usuário: ${ANSIBLE_USER}                              ║
║  Target: ${PROJECT_DIR}           ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
${NC}"
}

# Verificar se é Amazon Linux
check_os() {
    info "Verificando sistema operacional..."
    
    if [ -f /etc/amazon-linux-release ] || [ -f /etc/amzn-release ]; then
        log "✓ Amazon Linux detectado"
        return 0
    elif [ -f /etc/redhat-release ]; then
        log "✓ RedHat/CentOS detectado"
        return 0
    elif [ -f /etc/debian_version ]; then
        log "✓ Debian/Ubuntu detectado"
        warn "Script otimizado para Amazon Linux, mas pode funcionar"
        return 0
    else
        warn "Sistema operacional não identificado"
        read -p "Continuar mesmo assim? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
    fi
}

# Instalar dependências
install_dependencies() {
    log "Instalando dependências do sistema..."
    
    # Detectar gerenciador de pacotes
    if command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum update -y"
    elif command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update && apt-get upgrade -y"
    else
        error "Gerenciador de pacotes não suportado"
        return 1
    fi
    
    info "Usando gerenciador de pacotes: $PKG_MANAGER"
    
    # Atualizar sistema
    log "Atualizando sistema..."
    sudo $PKG_UPDATE
    
    # Instalar EPEL se necessário (RedHat/CentOS)
    if [ "$PKG_MANAGER" = "yum" ]; then
        if ! rpm -qa | grep -q epel-release; then
            log "Instalando EPEL repository..."
            sudo $PKG_INSTALL epel-release
        fi
    fi
    
    # Lista de pacotes necessários
    local packages=""
    
    if [ "$PKG_MANAGER" = "yum" ]; then
        packages="ansible jq cifs-utils git rsync curl wget"
    else
        packages="ansible jq cifs-utils git rsync curl wget"
    fi
    
    # Instalar Ansible
    if ! command -v ansible &> /dev/null; then
        log "Instalando Ansible..."
        sudo $PKG_INSTALL ansible
    else
        log "✓ Ansible já instalado: $(ansible --version | head -1)"
    fi
    
    # Instalar outros pacotes
    for pkg in jq cifs-utils git rsync curl wget; do
        if ! command -v $pkg &> /dev/null && ! rpm -qa | grep -q $pkg; then
            log "Instalando $pkg..."
            sudo $PKG_INSTALL $pkg
        else
            log "✓ $pkg já instalado"
        fi
    done
    
    log "✅ Dependências instaladas com sucesso!"
}

# Criar usuário ansible
create_ansible_user() {
    log "Configurando usuário $ANSIBLE_USER..."
    
    # Verificar se usuário já existe
    if id "$ANSIBLE_USER" &>/dev/null; then
        log "✓ Usuário $ANSIBLE_USER já existe"
    else
        log "Criando usuário $ANSIBLE_USER..."
        sudo useradd -m -s /bin/bash "$ANSIBLE_USER"
        sudo usermod -aG wheel "$ANSIBLE_USER" 2>/dev/null || sudo usermod -aG sudo "$ANSIBLE_USER"
    fi
    
    # Configurar sudo sem senha para comandos específicos
    log "Configurando permissões sudo..."
    sudo tee /etc/sudoers.d/$ANSIBLE_USER << EOF
# Ansible user permissions for $PROJECT_NAME
$ANSIBLE_USER ALL=(ALL) NOPASSWD: /bin/systemctl, /bin/mount, /bin/umount, /bin/chown, /bin/chmod, /usr/bin/rsync
Defaults:$ANSIBLE_USER !requiretty
EOF
    
    log "✅ Usuário $ANSIBLE_USER configurado"
}

# Configurar SSH
setup_ssh() {
    log "Configurando SSH para usuário $ANSIBLE_USER..."
    
    # Criar diretório .ssh
    sudo mkdir -p /home/$ANSIBLE_USER/.ssh
    sudo chown $ANSIBLE_USER:$ANSIBLE_USER /home/$ANSIBLE_USER/.ssh
    sudo chmod 700 /home/$ANSIBLE_USER/.ssh
    
    # Verificar se chave SSH existe
    if [ ! -f /home/$ANSIBLE_USER/.ssh/id_rsa ]; then
        log "Gerando chave SSH para $ANSIBLE_USER..."
        sudo -u $ANSIBLE_USER ssh-keygen -t rsa -b 4096 -f /home/$ANSIBLE_USER/.ssh/id_rsa -N "" -C "$ANSIBLE_USER@$(hostname)"
        log "✓ Chave SSH gerada: /home/$ANSIBLE_USER/.ssh/id_rsa"
    else
        log "✓ Chave SSH já existe: /home/$ANSIBLE_USER/.ssh/id_rsa"
    fi
    
    # Copiar chaves autorizadas do ec2-user (se existir)
    if [ -f /home/ec2-user/.ssh/authorized_keys ]; then
        log "Copiando authorized_keys do ec2-user..."
        sudo cp /home/ec2-user/.ssh/authorized_keys /home/$ANSIBLE_USER/.ssh/
        sudo chown $ANSIBLE_USER:$ANSIBLE_USER /home/$ANSIBLE_USER/.ssh/authorized_keys
        sudo chmod 600 /home/$ANSIBLE_USER/.ssh/authorized_keys
    fi
    
    # Configurar SSH config
    sudo -u $ANSIBLE_USER tee /home/$ANSIBLE_USER/.ssh/config << EOF
# SSH Configuration for $PROJECT_NAME
Host 172.16.3.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    User ec2-user
    IdentityFile /home/$ANSIBLE_USER/.ssh/id_rsa
    ConnectTimeout 10
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
    
    sudo chmod 600 /home/$ANSIBLE_USER/.ssh/config
    log "✅ SSH configurado"
}

# Criar estrutura do projeto
setup_project_structure() {
    log "Criando estrutura do projeto $PROJECT_NAME..."
    
    # Criar diretório principal
    sudo mkdir -p "$PROJECT_DIR"
    
    # Criar estrutura de subdiretórios
    local dirs=(
        "playbooks"
        "group_vars" 
        "host_vars"
        "roles"
        "scripts"
        "logs"
        "windows"
        "setup"
        "docs"
    )
    
    for dir in "${dirs[@]}"; do
        sudo mkdir -p "$PROJECT_DIR/$dir"
        log "✓ Criado: $PROJECT_DIR/$dir"
    done
    
    # Criar diretório de backups
    sudo mkdir -p /home/$ANSIBLE_USER/backups/tomcat
    
    # Definir proprietário
    sudo chown -R $ANSIBLE_USER:$ANSIBLE_USER "$PROJECT_DIR"
    sudo chown -R $ANSIBLE_USER:$ANSIBLE_USER /home/$ANSIBLE_USER/backups
    
    log "✅ Estrutura do projeto criada em $PROJECT_DIR"
}

# Configurar ambiente do usuário ansible
setup_ansible_environment() {
    log "Configurando ambiente do usuário $ANSIBLE_USER..."
    
    # Criar .bashrc personalizado
    sudo -u $ANSIBLE_USER tee /home/$ANSIBLE_USER/.bashrc << EOF
# Ansible Tomcat Deploy Environment
# Project: $PROJECT_NAME

# Environment variables
export ANSIBLE_HOME="$PROJECT_DIR"
export PATH="\$ANSIBLE_HOME/scripts:\$PATH"
export ANSIBLE_CONFIG="\$ANSIBLE_HOME/ansible.cfg"
export ANSIBLE_INVENTORY="\$ANSIBLE_HOME/inventory.yml"
export ANSIBLE_LOG_PATH="\$ANSIBLE_HOME/logs/ansible.log"

# Project info
export PROJECT_NAME="$PROJECT_NAME"
export DEPLOYMENT_USER="$ANSIBLE_USER"

# Welcome banner
echo "
╔════════════════════════════════════════════════════════╗
║              🚀 Ansible Tomcat Deploy                 ║
║              Projeto: $PROJECT_NAME           ║
║              Usuário: $ANSIBLE_USER                    ║
╚════════════════════════════════════════════════════════╝
"

echo "📋 Informações do ambiente:"
echo "   • Home: \$HOME"
echo "   • Projeto: \$ANSIBLE_HOME"
echo "   • Logs: \$ANSIBLE_LOG_PATH"
echo "   • Data: \$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

echo "🚀 Comandos disponíveis:"
echo "   • deploy-manager.sh  → Interface principal"
echo "   • dp                 → Shortcut para deploy-manager"
echo "   • health             → Health check rápido"
echo "   • logs               → Ver logs em tempo real"
echo "   • cdp                → Ir para diretório do projeto"
echo "   • status             → Status do projeto"
echo ""

# Useful aliases
alias dp='deploy-manager.sh'
alias health='deploy-manager.sh health'
alias status='deploy-manager.sh status'
alias logs='tail -f \$ANSIBLE_LOG_PATH'
alias cdp='cd \$ANSIBLE_HOME'
alias ll='ls -la'
alias la='ls -la'

# Auto-complete para ansible (se disponível)
if [ -f /usr/share/bash-completion/completions/ansible ]; then
    source /usr/share/bash-completion/completions/ansible
fi

# Prompt customizado
PS1='[\u@tomcat-deploy \W]\$ '

# Auto-cd para projeto ao logar
if [ "\$PWD" = "\$HOME" ]; then
    cd "\$ANSIBLE_HOME"
fi
EOF
    
    # Criar profile personalizado
    sudo -u $ANSIBLE_USER tee /home/$ANSIBLE_USER/.bash_profile << EOF
# .bash_profile for $ANSIBLE_USER
# Project: $PROJECT_NAME

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# User specific environment and startup programs
PATH="\$PATH:\$HOME/.local/bin:\$HOME/bin"
export PATH
EOF
    
    log "✅ Ambiente do usuário configurado"
}

# Configurar FSx mount point
setup_fsx_mount() {
    log "Configurando mount point para FSx..."
    
    # Criar diretório de mount
    sudo mkdir -p /mnt/ansible
    sudo chown $ANSIBLE_USER:$ANSIBLE_USER /mnt/ansible
    
    # Criar exemplo de script de mount
    sudo -u $ANSIBLE_USER tee /home/$ANSIBLE_USER/mount-fsx.sh << 'EOF'
#!/bin/bash
# Script para montar FSx
# Substitua fs-xxxxx pelo ID real do seu FSx

FSX_ID="fs-xxxxx"  # ALTERAR AQUI
FSX_PASSWORD="SuaSenhaFSx"  # ALTERAR AQUI
MOUNT_POINT="/mnt/ansible"

echo "Montando FSx: $FSX_ID"
sudo mount -t cifs //$FSX_ID.fsx.us-east-1.amazonaws.com/share $MOUNT_POINT \
    -o username=admin,password=$FSX_PASSWORD,uid=$(id -u),gid=$(id -g),iocharset=utf8

if mountpoint -q $MOUNT_POINT; then
    echo "✅ FSx montado com sucesso em $MOUNT_POINT"
    
    # Criar estrutura necessária
    mkdir -p $MOUNT_POINT/{staging,triggers,deployed,history,logs}
    echo "✅ Estrutura FSx criada"
else
    echo "❌ Erro ao montar FSx"
    exit 1
fi
EOF
    
    chmod +x /home/$ANSIBLE_USER/mount-fsx.sh
    
    warn "IMPORTANTE: Configure o FSx manualmente:"
    echo "   1. Edite o arquivo: /home/$ANSIBLE_USER/mount-fsx.sh"
    echo "   2. Substitua 'fs-xxxxx' pelo ID do seu FSx"
    echo "   3. Configure a senha correta"
    echo "   4. Execute: ./mount-fsx.sh"
    echo ""
    echo "Para mount automático, adicione ao /etc/fstab:"
    echo "//fs-xxxxx.fsx.amazonaws.com/share /mnt/ansible cifs credentials=/etc/cifs-credentials,uid=1001,gid=1001,iocharset=utf8 0 0"
}

# Testar conectividade com servidores
test_connectivity() {
    log "Testando conectividade com servidores frontend..."
    
    local servers=(
        "172.16.3.54"
        "172.16.3.188" 
        "172.16.3.121"
        "172.16.3.57"
        "172.16.3.254"
        "172.16.3.127"
        "172.16.3.19"
    )
    
    local success=0
    local total=${#servers[@]}
    
    echo "🔍 Testando $total servidores..."
    
    for server in "${servers[@]}"; do
        echo -n "   Testing $server... "
        if timeout 10 sudo -u $ANSIBLE_USER ssh -o ConnectTimeout=5 -o BatchMode=yes ec2-user@$server "echo 'OK'" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
            ((success++))
        else
            echo -e "${RED}✗${NC}"
        fi
    done
    
    echo ""
    log "Conectividade: $success/$total servidores OK"
    
    if [ $success -eq $total ]; then
        log "✅ Todos os servidores acessíveis"
    elif [ $success -gt 0 ]; then
        warn "⚠ Alguns servidores não acessíveis - verifique chaves SSH"
    else
        error "❌ Nenhum servidor acessível - configure chaves SSH"
        echo ""
        echo "Para configurar acesso SSH aos servidores:"
        echo "1. Copie a chave pública:"
        echo "   sudo -u $ANSIBLE_USER cat /home/$ANSIBLE_USER/.ssh/id_rsa.pub"
        echo ""
        echo "2. Em cada servidor frontend, adicione ao authorized_keys:"
        echo "   echo 'CHAVE_PUBLICA_AQUI' >> ~/.ssh/authorized_keys"
    fi
}

# Criar arquivos de exemplo
create_example_configs() {
    log "Criando arquivos de exemplo e documentação..."
    
    # Exemplo de credenciais FSx
    sudo -u $ANSIBLE_USER tee /home/$ANSIBLE_USER/fsx-credentials-example << EOF
# Exemplo de arquivo /etc/cifs-credentials
# Substitua pelos valores reais do seu FSx

username=admin
password=SuaSenhaFSx
domain=fsx.amazonaws.com
EOF
    
    # README básico
    sudo -u $ANSIBLE_USER tee "$PROJECT_DIR/README.md" << EOF
# $PROJECT_NAME

Projeto de automação de deploys Tomcat usando Ansible.

## Estrutura

- \`playbooks/\` - Playbooks Ansible
- \`group_vars/\` - Variáveis de grupo
- \`scripts/\` - Scripts utilitários
- \`windows/\` - Scripts Windows (PowerShell)
- \`logs/\` - Logs de execução

## Uso Rápido

\`\`\`bash
# Interface principal
./scripts/deploy-manager.sh

# Health check
deploy-manager.sh health

# Deploy WAR
deploy-manager.sh deploy-war war-2025-08-25_14-30
\`\`\`

## Configuração

1. Configure FSx: edite ~/mount-fsx.sh
2. Monte FSx: ./mount-fsx.sh  
3. Teste conectividade: deploy-manager.sh health

EOF
    
    log "✅ Arquivos de exemplo criados"
}

# Validar instalação
validate_installation() {
    log "🔍 Validando instalação..."
    
    local errors=0
    
    echo -e "${CYAN}Verificando componentes:${NC}"
    
    # Verificar comandos essenciais
    local commands=("ansible" "jq" "git" "rsync")
    for cmd in "${commands[@]}"; do
        if command -v $cmd &> /dev/null; then
            echo -e "  ✓ $cmd: ${GREEN}OK${NC}"
        else
            echo -e "  ✗ $cmd: ${RED}AUSENTE${NC}"
            ((errors++))
        fi
    done
    
    # Verificar usuário ansible
    if id "$ANSIBLE_USER" &>/dev/null; then
        echo -e "  ✓ Usuário $ANSIBLE_USER: ${GREEN}OK${NC}"
    else
        echo -e "  ✗ Usuário $ANSIBLE_USER: ${RED}AUSENTE${NC}"
        ((errors++))
    fi
    
    # Verificar estrutura de diretórios
    if [ -d "$PROJECT_DIR" ]; then
        echo -e "  ✓ Estrutura projeto: ${GREEN}OK${NC}"
    else
        echo -e "  ✗ Estrutura projeto: ${RED}AUSENTE${NC}"
        ((errors++))
    fi
    
    # Verificar chave SSH
    if [ -f /home/$ANSIBLE_USER/.ssh/id_rsa ]; then
        echo -e "  ✓ Chave SSH: ${GREEN}OK${NC}"
    else
        echo -e "  ✗ Chave SSH: ${RED}AUSENTE${NC}"
        ((errors++))
    fi
    
    # Verificar mount point
    if [ -d /mnt/ansible ]; then
        echo -e "  ✓ Mount point: ${GREEN}OK${NC}"
    else
        echo -e "  ✗ Mount point: ${RED}AUSENTE${NC}"
        ((errors++))
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        log "✅ Validação concluída - tudo OK!"
        return 0
    else
        error "❌ $errors problemas encontrados"
        return 1
    fi
}

# Menu principal
show_menu() {
    echo -e "${BLUE}
╔════════════════════════════════════════════════════════╗
║                      📋 MENU SETUP                    ║
╚════════════════════════════════════════════════════════╝${NC}"
    echo "1. 🚀 Instalação completa (recomendado)"
    echo "2. 📦 Instalar apenas dependências"
    echo "3. 👤 Configurar usuário ansible"
    echo "4. 🔑 Configurar SSH"
    echo "5. 📁 Criar estrutura projeto"
    echo "6. 🌐 Testar conectividade"
    echo "7. ✅ Validar instalação"
    echo "8. 📋 Mostrar informações"
    echo "0. 🚪 Sair"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
}

# Mostrar informações pós-instalação
show_post_install_info() {
    echo -e "${GREEN}
╔════════════════════════════════════════════════════════╗
║                 ✅ INSTALAÇÃO COMPLETA                ║
╚════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "${CYAN}📋 Informações do sistema:${NC}"
    echo "   • Projeto: $PROJECT_NAME"
    echo "   • Usuário: $ANSIBLE_USER" 
    echo "   • Diretório: $PROJECT_DIR"
    echo "   • Host: $(hostname)"
    echo "   • IP: $(hostname -I | awk '{print $1}')"
    echo ""
    
    echo -e "${CYAN}🚀 Próximos passos:${NC}"
    echo "   1. Configure FSx:"
    echo "      sudo -u $ANSIBLE_USER nano /home/$ANSIBLE_USER/mount-fsx.sh"
    echo ""
    echo "   2. Monte FSx:"
    echo "      sudo -u $ANSIBLE_USER /home/$ANSIBLE_USER/mount-fsx.sh"
    echo ""
    echo "   3. Copie arquivos de configuração Ansible para:"
    echo "      $PROJECT_DIR/"
    echo ""
    echo "   4. Faça login como usuário ansible:"
    echo "      sudo su - $ANSIBLE_USER"
    echo ""
    echo "   5. Execute o deploy manager:"
    echo "      deploy-manager.sh"
    echo ""
    
    echo -e "${YELLOW}📝 Notas importantes:${NC}"
    echo "   • Chave SSH pública está em: /home/$ANSIBLE_USER/.ssh/id_rsa.pub"
    echo "   • Copie esta chave para os 7 servidores frontend"
    echo "   • Configure credenciais FSx antes de montar"
    echo "   • Logs de instalação em: /tmp/ansible-setup.log"
}

# Função principal
main() {
    # Mostrar banner
    show_banner
    
    if [ $# -eq 0 ]; then
        # Modo interativo
        while true; do
            echo
            show_menu
            read -p "Escolha uma opção: " choice
            echo
            
            case $choice in
                1)
                    check_os || exit 1
                    install_dependencies
                    create_ansible_user
                    setup_ssh
                    setup_project_structure
                    setup_ansible_environment
                    setup_fsx_mount
                    create_example_configs
                    test_connectivity
                    validate_installation
                    show_post_install_info
                    ;;
                2) install_dependencies ;;
                3) create_ansible_user ;;
                4) setup_ssh ;;
                5) setup_project_structure ;;
                6) test_connectivity ;;
                7) validate_installation ;;
                8) show_post_install_info ;;
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
                check_os || exit 1
                install_dependencies
                create_ansible_user
                setup_ssh
                setup_project_structure
                setup_ansible_environment
                setup_fsx_mount
                create_example_configs
                validate_installation
                show_post_install_info
                ;;
            "deps") install_dependencies ;;
            "user") create_ansible_user ;;
            "ssh") setup_ssh ;;
            "structure") setup_project_structure ;;
            "test") test_connectivity ;;
            "validate") validate_installation ;;
            "info") show_post_install_info ;;
            *) 
                echo "Uso:"
                echo "  $0           # Modo interativo"
                echo "  $0 full      # Instalação completa"
                echo "  $0 deps      # Apenas dependências"
                echo "  $0 user      # Apenas usuário ansible"
                echo "  $0 ssh       # Apenas SSH"
                echo "  $0 structure # Apenas estrutura"
                echo "  $0 test      # Testar conectividade"
                echo "  $0 validate  # Validar instalação"
                echo "  $0 info      # Informações pós-install"
                ;;
        esac
    fi
}

# Executar com log
main "$@" 2>&1 | tee /tmp/ansible-setup.log