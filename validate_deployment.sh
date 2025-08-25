#!/bin/bash
# Validate deployment across all servers

SERVERS=(172.16.3.54 172.16.3.188 172.16.3.121 172.16.3.57 172.16.3.254 172.16.3.127 172.16.3.19)
ANSIBLE_DIR="/opt/ansible-deploys"

validate_deployment() {
    echo "🔍 Validando deployment em todos os servidores..."
    
    cd "$ANSIBLE_DIR"
    
    # Test connectivity
    echo "1. Testando conectividade..."
    ansible -i inventory.yml frontend_servers -m ping
    
    # Check Tomcat status
    echo "2. Verificando status do Tomcat..."
    ansible -i inventory.yml frontend_servers -m shell -a "systemctl is-active tomcat"
    
    # Check application response
    echo "3. Testando resposta da aplicação..."
    for server in "${SERVERS[@]}"; do
        echo "Testing $server..."
        curl -k -s -o /dev/null -w "%{http_code}" "https://$server:8080/totvs-menu" || echo "FAILED"
    done
    
    # Check for errors in logs
    echo "4. Verificando erros nos logs..."
    ansible -i inventory.yml frontend_servers -m shell -a "tail -20 /opt/tomcat/current/logs/catalina.out | grep -i error" --one-line
}

validate_deployment