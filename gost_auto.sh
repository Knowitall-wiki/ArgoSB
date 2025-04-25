#!/bin/bash

# 自动安装GOST局域网共享代理
gvinstall(){
  echo "正在安装GOST局域网共享代理 (Socks5端口:1080 / HTTP端口:8082)"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  
  # 设置固定端口
  socks_port=1080
  http_port=8082
  
  # 下载GOST
  echo "下载GOST中..."
  curl -L -o gost_3.0.0_linux_arm64.tar.gz -# --retry 2 --insecure https://raw.githubusercontent.com/Knowitall-wiki/argosb/main/gost_3.0.0_linux_arm64.tar.gz
  
  # 检查下载是否成功
  if [ ! -f gost_3.0.0_linux_arm64.tar.gz ]; then
    echo "GOST下载失败，尝试备用链接..."
    curl -L -o gost_3.0.0_linux_arm64.tar.gz -# --retry 2 --insecure https://gh-proxy.com/https://raw.githubusercontent.com/Knowitall-wiki/argosb/main/gost_3.0.0_linux_arm64.tar.gz
  fi
  
  # 再次检查下载
  if [ ! -f gost_3.0.0_linux_arm64.tar.gz ]; then
    echo "GOST下载失败，请检查网络连接后重试" && exit 1
  fi
  
  # 解压
  tar zxvf gost_3.0.0_linux_arm64.tar.gz
  rm -f gost_3.0.0_linux_arm64.tar.gz README* LICENSE* config.yaml
  
  # 创建配置文件
  echo "创建GOST配置..."
  cat > config.yaml <<EOF
services:
  - name: service-socks5
    addr: :${socks_port}
    resolver: resolver-0
    handler:
      type: socks5
      metadata:
        udp: true
        udpbuffersize: 4096
    listener:
      type: tcp
  - name: service-http
    addr: :${http_port}
    resolver: resolver-0
    handler:
      type: http
      metadata:
        udp: true
        udpbuffersize: 4096
    listener:
      type: tcp
resolvers:
  - name: resolver-0
    nameservers:
      - addr: tls://8.8.8.8:853
        prefer: ipv4
        ttl: 5m0s
        async: true
      - addr: tls://8.8.4.4:853
        prefer: ipv4
        ttl: 5m0s
        async: true
      - addr: tls://[2001:4860:4860::8888]:853
        prefer: ipv6
        ttl: 5m0s
        async: true
      - addr: tls://[2001:4860:4860::8844]:853
        prefer: ipv6
        ttl: 5m0s
        async: true
EOF
  
  # 创建启动脚本
  echo "创建启动脚本..."
  cat > gost_start.sh <<EOF
#!/bin/bash
screen -wipe
screen -ls | grep Detached | cut -d. -f1 | awk '{print \$1}' | xargs kill
screen -dmS gost_screen ./gost -C config.yaml
echo "GOST代理已启动"
EOF
  chmod +x gost_start.sh
  
  # 创建状态查询脚本
  cat > gost_status.sh <<EOF
#!/bin/bash
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "GOST代理状态："

if screen -ls | grep -q "gost_screen"; then
  echo "运行状态: 正在运行"
else
  echo "运行状态: 未运行"
fi

# 获取本机IP地址
local_ip=\$(ip -4 addr | grep -v "127.0.0.1" | grep "inet" | awk '{print \$2}' | cut -d'/' -f1 | head -n 1)
if [[ -z "\$local_ip" ]]; then
  local_ip="无法获取，请手动查看"
fi

echo "本机IP: \$local_ip"
echo "Socks5代理: \$local_ip:${socks_port}"
echo "HTTP代理: \$local_ip:${http_port}"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
EOF
  chmod +x gost_status.sh
  
  # 启动GOST
  echo "启动GOST代理服务..."
  ./gost_start.sh
  
  # 获取本机IP地址
  local_ip=$(ip -4 addr | grep -v "127.0.0.1" | grep "inet" | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
  if [[ -z "$local_ip" ]]; then
    local_ip="无法获取，请手动查看"
  fi
  
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo "GOST代理安装完成！"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo "本机IP: $local_ip"
  echo "Socks5代理: $local_ip:$socks_port"
  echo "HTTP代理: $local_ip:$http_port"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo "快捷命令："
  echo "./gost_start.sh - 启动GOST代理"
  echo "./gost_status.sh - 查看GOST代理状态"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

# 卸载GOST代理
uninstall(){
  echo "正在卸载GOST代理服务..."
  screen -ls | grep gost_screen | cut -d. -f1 | awk '{print $1}' | xargs kill 2>/dev/null
  rm -f gost config.yaml gost_start.sh gost_status.sh
  echo "GOST代理服务已卸载完成"
}

# 自动安装GOST
gvinstall

exit 0
