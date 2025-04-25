#!/bin/bash

gvinstall(){
  # 安装screen
  echo "正在安装screen..."
  if command -v apt &> /dev/null; then
    apt update && apt install -y screen
  elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y screen
  elif command -v yum &> /dev/null; then
    yum install -y screen
  elif command -v pkg &> /dev/null; then
    pkg install -y screen
  else
    echo "无法安装screen，请手动安装后再运行脚本"
    exit 1
  fi
  
  # 设置默认端口
  socks_port=1080
  http_port=8082
  
  # 下载GOST
  if [ ! -e gost ]; then
    echo "下载中……"
    curl -L -o gost_3.0.0_linux_arm64.tar.gz -# --retry 2 --insecure https://raw.githubusercontent.com/Knowitall-wiki/argosb/main/gost_3.0.0_linux_arm64.tar.gz
    tar zxvf gost_3.0.0_linux_arm64.tar.gz
  fi
  
  # 如果下载失败，尝试中转下载
  if [ ! -e gost ]; then
    echo "当前网络无法链接Github，切换中转下载"
    curl -L -o gost_3.0.0_linux_arm64.tar.gz -# --retry 2 --insecure https://gh-proxy.com/https://raw.githubusercontent.com/Knowitall-wiki/argosb/main/gost_3.0.0_linux_arm64.tar.gz
    tar zxvf gost_3.0.0_linux_arm64.tar.gz
  fi
  
  # 检查下载结果
  if [ ! -e gost ]; then
    echo "下载失败，请在代理环境下运行脚本" && exit 1
  fi
  
  # 清理不需要的文件
  rm -f gost_3.0.0_linux_arm64.tar.gz README* LICENSE* config.yaml
  
  echo "使用 Socks5 端口：$socks_port 和 Http 端口：$http_port"
  
  # 创建配置文件
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
  
  # 检测是否为Termux环境
  if [ -d "/data/data/com.termux/files/usr/etc/profile.d" ]; then
    # Termux环境
    cd /data/data/com.termux/files/usr/etc/profile.d
    cat > gost.sh <<EOF
#!/data/data/com.termux/files/usr/bin/bash
screen -wipe 2>/dev/null
screen -ls | grep Detached | cut -d. -f1 | awk '{print \$1}' | xargs kill 2>/dev/null
cd \$HOME
screen -dmS myscreen bash -c './gost -C config.yaml'
EOF
    chmod +x gost.sh
    # 立即启动
    cd $HOME
    screen -wipe 2>/dev/null
    screen -ls | grep Detached | cut -d. -f1 | awk '{print $1}' | xargs kill 2>/dev/null
    screen -dmS myscreen bash -c './gost -C config.yaml'
  else
    # 非Termux环境，创建启动脚本
    cat > gost_start.sh <<EOF
#!/bin/bash
screen -wipe 2>/dev/null
screen -ls | grep Detached | cut -d. -f1 | awk '{print \$1}' | xargs kill 2>/dev/null
screen -dmS gost_screen ./gost -C config.yaml
echo "GOST代理已启动"
EOF
    chmod +x gost_start.sh
    
    # 创建状态查询脚本
    cat > gv.sh <<EOF
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
    chmod +x gv.sh
    
    # 启动GOST
    ./gost_start.sh
  fi
  
  # 获取本机IP地址
  local_ip=$(ip -4 addr | grep -v "127.0.0.1" | grep "inet" | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
  if [[ -z "$local_ip" ]]; then
    local_ip="无法获取，请手动查看"
  fi
  
  echo "安装完毕" 
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo "本机IP: $local_ip"
  echo "Socks5代理: $local_ip:$socks_port"
  echo "HTTP代理: $local_ip:$http_port"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo "快捷方式：bash gv.sh  可查看Socks5端口与Http端口"
  echo "退出脚本运行：exit"
  sleep 2
}

uninstall(){
  screen -ls | grep Detached | cut -d. -f1 | awk '{print $1}' | xargs kill 2>/dev/null
  rm -f gost config.yaml gv.sh gost_start.sh
  
  # 如果是Termux环境，删除profile.d中的启动脚本
  if [ -f "/data/data/com.termux/files/usr/etc/profile.d/gost.sh" ]; then
    rm -f /data/data/com.termux/files/usr/etc/profile.d/gost.sh
  fi
  
  echo "卸载完毕"
}

# 直接执行安装
gvinstall
