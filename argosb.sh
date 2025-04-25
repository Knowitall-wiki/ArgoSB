#!/bin/bash

# gost局域网共享代理安装函数
install_gost_proxy() {
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
  echo "正在安装GOST局域网共享代理 (Socks5端口:1080 / HTTP端口:8082)"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  
  mkdir -p /etc/gost
  cd /etc/gost
  
  # 设置固定端口
  socks_port=1080
  http_port=8082
  
  # 下载GOST
  echo "下载GOST中..."
  if [[ "$cpu" == "arm64" ]]; then
    curl -L -o gost.tar.gz -# --retry 2 --insecure https://raw.githubusercontent.com/Knowitall-wiki/argosb/main/gost_3.0.0_linux_arm64.tar.gz
  else
    curl -L -o gost.tar.gz -# --retry 2 --insecure https://github.com/go-gost/gost/releases/download/v3.0.0/gost_3.0.0_linux_amd64.tar.gz
  fi
  
  # 检查下载是否成功
  if [[ ! -f gost.tar.gz ]]; then
    echo "GOST下载失败，尝试备用链接..."
    if [[ "$cpu" == "arm64" ]]; then
      curl -L -o gost.tar.gz -# --retry 2 --insecure https://gh-proxy.com/https://raw.githubusercontent.com/Knowitall-wiki/argosb/main/gost_3.0.0_linux_arm64.tar.gz
    else
      curl -L -o gost.tar.gz -# --retry 2 --insecure https://gh-proxy.com/https://github.com/go-gost/gost/releases/download/v3.0.0/gost_3.0.0_linux_amd64.tar.gz
    fi
  fi
  
  # 再次检查下载
  if [[ ! -f gost.tar.gz ]]; then
    echo "GOST下载失败，请检查网络连接后重试" && return 1
  fi
  
  # 解压
  tar zxvf gost.tar.gz
  rm -f gost.tar.gz README* LICENSE* config.yaml
  
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
  
  # 创建系统服务
  if [[ x"${release}" == x"alpine" ]]; then
    cat > /etc/init.d/gost <<EOF
#!/sbin/openrc-run
description="GOST proxy service"
command="/etc/gost/gost"
command_args="-C /etc/gost/config.yaml"
command_background=true
pidfile="/var/run/gost.pid"
EOF
    chmod +x /etc/init.d/gost
    rc-update add gost default
    rc-service gost start
  else
    cat > /etc/systemd/system/gost.service <<EOF
[Unit]
Description=GOST Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/gost
ExecStart=/etc/gost/gost -C /etc/gost/config.yaml
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gost
    systemctl start gost
  fi
  
  # 检查GOST是否成功启动
  sleep 2
  if [[ x"${release}" == x"alpine" ]]; then
    if rc-service gost status | grep -q "started"; then
      echo "GOST代理服务启动成功！"
    else
      echo "GOST代理服务启动失败，请检查日志"
      return 1
    fi
  else
    if systemctl is-active --quiet gost; then
      echo "GOST代理服务启动成功！"
    else
      echo "GOST代理服务启动失败，请检查日志"
      return 1
    fi
  fi
  
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
}

# GOST代理卸载函数
uninstall_gost_proxy() {
  echo "正在卸载GOST代理服务..."
  
  if [[ x"${release}" == x"alpine" ]]; then
    rc-service gost stop
    rc-update del gost default
    rm /etc/init.d/gost -f
  else
    systemctl stop gost
    systemctl disable gost
    rm -f /etc/systemd/system/gost.service
  fi
  
  rm -rf /etc/gost
  echo "GOST代理服务已卸载完成"
}

# GOST代理状态查询函数
check_gost_status() {
  if [[ ! -d "/etc/gost" ]]; then
    echo "GOST代理未安装"
    return
  fi
  
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo "GOST代理状态："
  
  if [[ x"${release}" == x"alpine" ]]; then
    if rc-service gost status | grep -q "started"; then
      echo "运行状态: 正在运行"
    else
      echo "运行状态: 未运行"
    fi
  else
    if systemctl is-active --quiet gost; then
      echo "运行状态: 正在运行"
    else
      echo "运行状态: 未运行"
    fi
  fi
  
  # 获取本机IP地址
  local_ip=$(ip -4 addr | grep -v "127.0.0.1" | grep "inet" | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
  if [[ -z "$local_ip" ]]; then
    local_ip="无法获取，请手动查看"
  fi
  
  echo "本机IP: $local_ip"
  echo "Socks5代理: $local_ip:1080"
  echo "HTTP代理: $local_ip:8082"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

# 处理gost相关命令
if [[ "$1" == "gost" ]]; then
  export LANG=en_US.UTF-8
  [[ $EUID -ne 0 ]] && echo "请以root模式运行脚本" && exit
  if [[ -f /etc/redhat-release ]]; then
    release="Centos"
  elif cat /etc/issue | grep -q -E -i "alpine"; then
    release="alpine"
  elif cat /etc/issue | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  elif cat /proc/version | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  else 
    echo "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
  fi
  case $(uname -m) in
  aarch64) cpu=arm64;;
  x86_64) cpu=amd64;;
  *) echo "目前脚本不支持$(uname -m)架构" && exit;;
  esac
  install_gost_proxy
  exit
elif [[ "$1" == "gost_del" ]]; then
  export LANG=en_US.UTF-8
  [[ $EUID -ne 0 ]] && echo "请以root模式运行脚本" && exit
  if [[ -f /etc/redhat-release ]]; then
    release="Centos"
  elif cat /etc/issue | grep -q -E -i "alpine"; then
    release="alpine"
  elif cat /etc/issue | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  elif cat /proc/version | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  else 
    echo "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
  fi
  uninstall_gost_proxy
  exit
elif [[ "$1" == "gost_status" ]]; then
  export LANG=en_US.UTF-8
  [[ $EUID -ne 0 ]] && echo "请以root模式运行脚本" && exit
  if [[ -f /etc/redhat-release ]]; then
    release="Centos"
  elif cat /etc/issue | grep -q -E -i "alpine"; then
    release="alpine"
  elif cat /etc/issue | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  elif cat /proc/version | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  else 
    echo "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
  fi
  check_gost_status
  exit
fi

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo "knowitall 谷歌手机pixel一键节点生成脚本走系统代理改197行"
echo "当前版本：25.4.22 测试beta2版"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "gost        - 安装GOST局域网共享代理(Socks5:1080/HTTP:8082)"
echo "gost_del    - 卸载GOST局域网共享代理"
echo "gost_status - 查看GOST代理状态"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
export LANG=en_US.UTF-8
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "目前脚本不支持$(uname -m)架构" && exit;;
esac
hostname=$(hostname)
export UUID=${uuid:-''}
export port_vm_ws=${vmpt:-''}
export ARGO_DOMAIN=${agn:-''}   
export ARGO_AUTH=${agk:-''} 

del(){
if [[ -n $(ps -e | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box-ag/sbargopid.log 2>/dev/null) >/dev/null 2>&1
fi
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box stop
rc-update del sing-box default
rm /etc/init.d/sing-box -f
else
systemctl stop sing-box >/dev/null 2>&1
systemctl disable sing-box >/dev/null 2>&1
rm -f /etc/systemd/system/sing-box.service
fi
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
rm -rf /etc/s-box-ag
echo "卸载完成" 
exit
}

agn(){
argoname=$(cat /etc/s-box-ag/sbargoym.log 2>/dev/null)
if [ -z $argoname ]; then
argodomain=$(cat /etc/s-box-ag/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
if [ -z $argodomain ]; then
echo "当前argo临时域名未生成，建议卸载重装" 
else
echo "当前argo最新临时域名：$argodomain"
fi
else
echo "当前argo固定域名：$argoname"
echo "当前argo固定域名token：$(cat /etc/s-box-ag/sbargotoken.log 2>/dev/null)"
fi
exit
}

if [[ "$1" == "del" ]]; then
del
elif [[ "$1" == "agn" ]]; then
agn
fi

if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box-ag/sb.json' ]]; then
echo "ArgoSB脚本已在运行中" && exit
elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box-ag/sb.json' ]]; then
echo "ArgoSB脚本已安装，但未启动，请卸载重装" && exit
else
echo "VPS系统：$op"
echo "CPU架构：$cpu"
echo "ArgoSB脚本未安装，开始安装…………" && sleep 3
echo
fi

if [[ x"${release}" == x"alpine" ]]; then
apk update
apk add wget curl tar jq tzdata openssl expect git socat iproute2 iptables grep dcron
apk add virt-what
else
apt update -y
apt install curl wget tar gzip cron -y
fi

warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}
v4orv6(){
if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
fi
}
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4orv6
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
v4orv6
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
mkdir -p /etc/s-box-ag
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
sbname="sing-box-$sbcore-linux-$cpu"
echo "下载sing-box最新正式版内核：$sbcore"
curl -L -o /etc/s-box-ag/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
if [[ -f '/etc/s-box-ag/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box-ag/sing-box.tar.gz -C /etc/s-box-ag
mv /etc/s-box-ag/$sbname/sing-box /etc/s-box-ag
rm -rf /etc/s-box-ag/{sing-box.tar.gz,$sbname}
else
echo "下载失败，请检测网络"
fi

if [ -z $port_vm_ws ]; then
port_vm_ws=$(shuf -i 10000-65535 -n 1)
fi
if [ -z $UUID ]; then
UUID=$(/etc/s-box-ag/sing-box generate uuid)
fi
echo
echo "当前vmess主协议端口：$port_vm_ws"
echo
echo "当前uuid密码：$UUID"
echo
sleep 3

cat > /etc/s-box-ag/sb.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
{
        "type": "vmess",
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${UUID}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${UUID}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": false,
                "server_name": "www.bing.com",
                "certificate_path": "/etc/s-box-ag/cert.pem",
                "key_path": "/etc/s-box-ag/private.key"
            }
    }
    ],
"outbounds": [{
"type": "socks",
"tag": "socks-out",
"server": "192.168.0.1",
"server_port": 1080
}
]
}
EOF

if [[ x"${release}" == x"alpine" ]]; then
echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box-ag/sing-box"
command_args="run -c /etc/s-box-ag/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box start
else
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box-ag/sing-box run -c /etc/s-box-ag/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl start sing-box
systemctl restart sing-box
fi
argocore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
echo "下载cloudflared-argo最新正式版内核：$argocore"
curl -L -o /etc/s-box-ag/cloudflared -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
chmod +x /etc/s-box-ag/cloudflared
if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
name='固定'
/etc/s-box-ag/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH} >/dev/null 2>&1 & echo "$!" > /etc/s-box-ag/sbargopid.log
echo ${ARGO_DOMAIN} > /etc/s-box-ag/sbargoym.log
echo ${ARGO_AUTH} > /etc/s-box-ag/sbargotoken.log
else
name='临时'
/etc/s-box-ag/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box-ag/sb.json | jq -r '.inbounds[0].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box-ag/argo.log 2>&1 &
echo "$!" > /etc/s-box-ag/sbargopid.log
fi
echo "申请Argo$name隧道中……请稍等"
sleep 8
if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
argodomain=$(cat /etc/s-box-ag/sbargoym.log 2>/dev/null)
else
argodomain=$(cat /etc/s-box-ag/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
fi
if [[ -n $argodomain ]]; then
echo "Argo$name隧道申请成功，域名为：$argodomain"
else
echo "Argo$name隧道申请失败，请稍后再试" && exit
fi
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
echo '@reboot /bin/bash -c "/etc/s-box-ag/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token $(cat /etc/s-box-ag/sbargotoken.log 2>/dev/null) >/dev/null 2>&1 & pid=\$! && echo \$pid > /etc/s-box-ag/sbargopid.log"' >> /tmp/crontab.tmp
else
echo '@reboot /bin/bash -c "/etc/s-box-ag/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box-ag/sb.json | jq -r '.inbounds[0].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box-ag/argo.log 2>&1 & pid=\$! && echo \$pid > /etc/s-box-ag/sbargopid.log"' >> /tmp/crontab.tmp
fi
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp

vmatls_link1="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-443\", \"add\": \"104.16.0.0\", \"port\": \"443\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link1" > /etc/s-box-ag/jh.txt
vmatls_link2="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-8443\", \"add\": \"104.17.0.0\", \"port\": \"8443\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link2" >> /etc/s-box-ag/jh.txt
vmatls_link3="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2053\", \"add\": \"104.18.0.0\", \"port\": \"2053\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link3" >> /etc/s-box-ag/jh.txt
vmatls_link4="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2083\", \"add\": \"104.19.0.0\", \"port\": \"2083\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link4" >> /etc/s-box-ag/jh.txt
vmatls_link5="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2087\", \"add\": \"104.20.0.0\", \"port\": \"2087\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link5" >> /etc/s-box-ag/jh.txt
vmatls_link6="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2096\", \"add\": \"[2606:4700::]\", \"port\": \"2096\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link6" >> /etc/s-box-ag/jh.txt
vma_link7="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-80\", \"add\": \"104.21.0.0\", \"port\": \"80\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link7" >> /etc/s-box-ag/jh.txt
vma_link8="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-8080\", \"add\": \"104.22.0.0\", \"port\": \"8080\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link8" >> /etc/s-box-ag/jh.txt
vma_link9="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-8880\", \"add\": \"104.24.0.0\", \"port\": \"8880\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link9" >> /etc/s-box-ag/jh.txt
vma_link10="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2052\", \"add\": \"104.25.0.0\", \"port\": \"2052\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link10" >> /etc/s-box-ag/jh.txt
vma_link11="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2082\", \"add\": \"104.26.0.0\", \"port\": \"2082\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link11" >> /etc/s-box-ag/jh.txt
vma_link12="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2086\", \"add\": \"104.27.0.0\", \"port\": \"2086\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link12" >> /etc/s-box-ag/jh.txt
vma_link13="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2095\", \"add\": \"[2400:cb00:2049::]\", \"port\": \"2095\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link13" >> /etc/s-box-ag/jh.txt
baseurl=$(base64 -w 0 < /etc/s-box-ag/jh.txt)
echo "ArgoSB脚本安装完毕"
echo "---------------------------------------------------------"
echo "---------------------------------------------------------"
echo "输出配置信息" && sleep 3
echo
echo "443端口的vmess-ws-tls-argo节点，默认优选IPV4：104.16.0.0"
sed -n '1p' /etc/s-box-ag/jh.txt
echo
echo "2096端口的vmess-ws-tls-argo节点，默认优选IPV6：[2606:4700::]（本地网络支持IPV6才可用）"
sed -n '6p' /etc/s-box-ag/jh.txt
echo
echo "80端口的vmess-ws-argo节点，默认优选IPV4：104.21.0.0"
sed -n '7p' /etc/s-box-ag/jh.txt
echo
echo "2095端口的vmess-ws-argo节点，默认优选IPV6：[2400:cb00:2049::]（本地网络支持IPV6才可用）"
sed -n '13p' /etc/s-box-ag/jh.txt
echo
echo "---------------------------------------------------------"
echo "聚合分享Argo节点13个端口及不死IP全覆盖：7个关tls 80系端口节点、6个开tls 443系端口节点" && sleep 3
echo
echo $baseurl
echo
echo "---------------------------------------------------------"
echo
