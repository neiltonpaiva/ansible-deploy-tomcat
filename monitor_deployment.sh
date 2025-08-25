#!/bin/bash
# Monitor deployment in real-time

TOMCAT_LOG="/opt/tomcat/current/logs/catalina.out"
DEPLOY_LOG="/opt/ansible-deploys/logs/current-deploy.log"

# Monitor logs durante deploy
monitor_deploy() {
    local server=$1
    echo "Monitorando deploy em $server..."
    
    # Conectar via SSH e monitorar logs
    ssh ec2-user@$server "tail -f $TOMCAT_LOG | grep -E 'Deployment|ERROR|startup|Exception'" &
    local ssh_pid=$!
    
    # Aguardar conclusão ou timeout
    sleep 300  # 5 minutos
    kill $ssh_pid 2>/dev/null
}

# Monitorar todos os servidores
for server in 172.16.3.54 172.16.3.188 172.16.3.121 172.16.3.57 172.16.3.254 172.16.3.127 172.16.3.19; do
    monitor_deploy $server &
done

wait