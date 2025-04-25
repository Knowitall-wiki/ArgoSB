#!/data/data/com.termux/files/usr/bin/bash

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo "knowitall 谷歌手机pixel一键节点生成脚本走系统代理改Termux版"
echo "当前版本：25.4.25 Termux适配版"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

export LANG=en_US.UTF-8

# Termux环境检测
if [ ! -d "/data/data/com.termux" ]; then
    echo "当前不是Termux环境，请在Termux中运行此脚本"
    exit 1
fi

# 创建工作目录
WORK_DIR="$HOME/argo-sb"
mkdir -p $WORK_DIR

# 参数设置
export UUID=${uuid:-''}
export port_vm_ws=${vmpt:-''}
export ARGO_DOMAIN=${agn:-''}   
export ARGO_AUTH=${agk:-''} 

# 卸载函数
del(){
    if [[ -n $(ps -ef | grep cloudflared | grep -v grep) ]]; then
        kill -15 $(cat $WORK_DIR/sbargopid.log 2>/dev/null) >/dev/null 2>&1
    fi
    
    pkill -f "sing-box" >/dev/null 2>&1
    
    crontab -l > /tmp/crontab.tmp
    sed -i '/sbargopid/d' /tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp
    
    rm -rf $WORK_DIR
    echo "卸载完成" 
    exit
}

# 查看Argo域名函数
agn(){
    argoname=$(cat $WORK_DIR/sbargoym.log 2>/dev/null)
    if [ -z $argoname ]; then
        argodomain=$(cat $WORK_DIR/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
        if [ -z $argodomain ]; then
            echo "当前argo临时域名未生成，建议卸载重装" 
        else
            echo "当前argo最新临时域名：$argodomain"
        fi
    else
        echo "当前argo固定域名：$argoname"
        echo "当前argo固定域名token：$(cat $WORK_DIR/sbargotoken.log 2>/dev/null)"
    fi
    exit
}

# 处理命令行参数
if [[ "$1" == "del" ]]; then
    del
elif [[ "$1" == "agn" ]]; then
    agn
fi

# 检查是否已运行
if [[ -n $(ps -ef | grep sing-box | grep -v grep) && -f "$WORK_DIR/sb.json" ]]; then
    echo "ArgoSB脚本已在运行中" && exit
elif [[ -z $(ps -ef | grep sing-box | grep -v grep) && -f "$WORK_DIR/sb.json" ]]; then
    echo "ArgoSB脚本已安装，但未启动，请卸载重装" && exit
else
    echo "Termux环境"
    echo "CPU架构：$(uname -m)"
    echo "ArgoSB脚本未安装，开始安装…………" && sleep 3
    echo
fi

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl wget tar python3 jq openssl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "正在安装必要的依赖..."
        pkg update -y || { echo "更新软件源失败"; exit 1; }
        pkg install -y ${missing_deps[@]} || { echo "安装依赖失败"; exit 1; }
        echo "依赖安装完成"
    fi
}

check_dependencies

# 检查网络连接
check_network() {
    echo "检查网络连接..."
    if ! curl -s -m 4 https://www.google.com >/dev/null; then
        if ! curl -s -m 4 https://www.baidu.com >/dev/null; then
            echo "网络连接失败，请检查网络设置"
            exit 1
        fi
    fi
}

check_network

# 检查网络环境
warpcheck(){
    wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v4orv6(){
    if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
        echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > $PREFIX/etc/resolv.conf
    fi
}

warpcheck

# 处理WARP环境
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
    v4orv6
else
    # Termux中不支持systemctl命令，如果有WARP可能需要手动处理
    v4orv6
fi

# 确定CPU架构
case $(uname -m) in
    aarch64) cpu=arm64;;
    arm*)    cpu=arm;;
    x86_64)  cpu=amd64;;
    *)       echo "不支持的CPU架构: $(uname -m)" && exit 1;;
esac

# 设置随机端口和UUID
if [ -z $port_vm_ws ]; then
    port_vm_ws=$(python3 -c "import random; print(random.randint(10000, 65535))")
    echo "$port_vm_ws" > "$WORK_DIR/port.txt"
fi

generate_uuid() {
    if command -v python3 >/dev/null 2>&1; then
        # 优先使用 Python 生成 UUID
        UUID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
    elif command -v uuidgen >/dev/null 2>&1; then
        # 如果有 uuidgen 命令则使用
        UUID=$(uuidgen)
    elif [ -f "/proc/sys/kernel/random/uuid" ]; then
        # 如果存在系统 UUID 文件则使用
        UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        # 如果以上方法都不可用，使用 OpenSSL 生成
        UUID=$(openssl rand -hex 16 | awk '{print substr($0,1,8)-substr($0,9,4)-substr($0,13,4)-substr($0,17,4)-substr($0,21,12)}')
    fi
    echo "$UUID" > "$WORK_DIR/uuid.txt"
}

if [ -z $UUID ]; then
    # 生成新的 UUID
    generate_uuid
    echo "生成新的 UUID: $UUID"
else
    echo "使用提供的 UUID: $UUID"
    echo "$UUID" > "$WORK_DIR/uuid.txt"
fi

# UUID 持久化
if [ ! -f "$WORK_DIR/uuid.txt" ]; then
    generate_uuid
fi
UUID=$(cat "$WORK_DIR/uuid.txt")

# 端口持久化
if [ ! -f "$WORK_DIR/port.txt" ]; then
    echo "$port_vm_ws" > "$WORK_DIR/port.txt"
fi
port_vm_ws=$(cat "$WORK_DIR/port.txt")

echo
echo "当前vmess主协议端口：$port_vm_ws"
echo
echo "当前uuid密码：$UUID"
echo
sleep 3

# 下载sing-box
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
sbname="sing-box-$sbcore-android-$cpu"
echo "下载sing-box最新正式版内核：$sbcore"
curl -L -o $WORK_DIR/sing-box.tar.gz -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
if [[ -f "$WORK_DIR/sing-box.tar.gz" ]]; then
    tar xzf $WORK_DIR/sing-box.tar.gz -C $WORK_DIR
    mv $WORK_DIR/$sbname/sing-box $WORK_DIR
    rm -rf $WORK_DIR/{sing-box.tar.gz,$sbname}
    chmod +x $WORK_DIR/sing-box
else
    echo "下载失败，请检测网络"
    exit 1
fi

# 创建sing-box配置文件
cat > $WORK_DIR/sb.json <<EOF
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
                "certificate_path": "$WORK_DIR/cert.pem",
                "key_path": "$WORK_DIR/private.key"
            }
    }
    ],
"outbounds": [{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 1080
}
]
}
EOF

# 启动sing-box
$WORK_DIR/sing-box run -c $WORK_DIR/sb.json > /dev/null 2>&1 &
echo $! > $WORK_DIR/sing-box.pid

# 下载cloudflared
argocore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
echo "下载cloudflared-argo最新正式版内核：$argocore"
curl -L -o $WORK_DIR/cloudflared -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-android-$cpu
chmod +x $WORK_DIR/cloudflared

# 启动Argo隧道
if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
    name='固定'
    $WORK_DIR/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH} >/dev/null 2>&1 & 
    echo "$!" > $WORK_DIR/sbargopid.log
    echo ${ARGO_DOMAIN} > $WORK_DIR/sbargoym.log
    echo ${ARGO_AUTH} > $WORK_DIR/sbargotoken.log
else
    name='临时'
    $WORK_DIR/cloudflared tunnel --url http://localhost:$port_vm_ws --edge-ip-version auto --no-autoupdate --protocol http2 > $WORK_DIR/argo.log 2>&1 &
    echo "$!" > $WORK_DIR/sbargopid.log
fi

echo "申请Argo$name隧道中……请稍等"
sleep 8

# 获取Argo域名
if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
    argodomain=$(cat $WORK_DIR/sbargoym.log 2>/dev/null)
else
    argodomain=$(cat $WORK_DIR/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
fi

if [[ -n $argodomain ]]; then
    echo "Argo$name隧道申请成功，域名为：$argodomain"
else
    echo "Argo$name隧道申请失败，请稍后再试" && exit
fi

# 设置开机自启
mkdir -p $HOME/.termux/boot
cat > $HOME/.termux/boot/start-argo-sb.sh <<EOF
#!/data/data/com.termux/files/usr/bin/bash
$WORK_DIR/sing-box run -c $WORK_DIR/sb.json > /dev/null 2>&1 &
echo \$! > $WORK_DIR/sing-box.pid

if [[ -n "\$(cat $WORK_DIR/sbargotoken.log 2>/dev/null)" ]]; then
    $WORK_DIR/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token \$(cat $WORK_DIR/sbargotoken.log) >/dev/null 2>&1 &
    echo \$! > $WORK_DIR/sbargopid.log
else
    $WORK_DIR/cloudflared tunnel --url http://localhost:$port_vm_ws --edge-ip-version auto --no-autoupdate --protocol http2 > $WORK_DIR/argo.log 2>&1 &
    echo \$! > $WORK_DIR/sbargopid.log
fi
EOF
chmod +x $HOME/.termux/boot/start-argo-sb.sh

# 生成节点链接
hostname=$(hostname 2>/dev/null || echo "termux")

vmatls_link1="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-443\", \"add\": \"104.16.0.0\", \"port\": \"443\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link1" > $WORK_DIR/jh.txt
vmatls_link2="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-8443\", \"add\": \"104.17.0.0\", \"port\": \"8443\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link2" >> $WORK_DIR/jh.txt
vmatls_link3="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2053\", \"add\": \"104.18.0.0\", \"port\": \"2053\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link3" >> $WORK_DIR/jh.txt
vmatls_link4="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2083\", \"add\": \"104.19.0.0\", \"port\": \"2083\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link4" >> $WORK_DIR/jh.txt
vmatls_link5="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2087\", \"add\": \"104.20.0.0\", \"port\": \"2087\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link5" >> $WORK_DIR/jh.txt
vmatls_link6="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2096\", \"add\": \"[2606:4700::]\", \"port\": \"2096\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
echo "$vmatls_link6" >> $WORK_DIR/jh.txt
vma_link7="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-80\", \"add\": \"104.21.0.0\", \"port\": \"80\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link7" >> $WORK_DIR/jh.txt
vma_link8="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-8080\", \"add\": \"104.22.0.0\", \"port\": \"8080\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link8" >> $WORK_DIR/jh.txt
vma_link9="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-8880\", \"add\": \"104.24.0.0\", \"port\": \"8880\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link9" >> $WORK_DIR/jh.txt
vma_link10="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2052\", \"add\": \"104.25.0.0\", \"port\": \"2052\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link10" >> $WORK_DIR/jh.txt
vma_link11="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2082\", \"add\": \"104.26.0.0\", \"port\": \"2082\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link11" >> $WORK_DIR/jh.txt
vma_link12="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2086\", \"add\": \"104.27.0.0\", \"port\": \"2086\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link12" >> $WORK_DIR/jh.txt
vma_link13="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-2095\", \"add\": \"[2400:cb00:2049::]\", \"port\": \"2095\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link13" >> $WORK_DIR/jh.txt
baseurl=$(base64 -w 0 < $WORK_DIR/jh.txt)

# 生成保活脚本
cat > $HOME/keepalive.sh <<EOF
#!/data/data/com.termux/files/usr/bin/bash

# 配置
CHECK_INTERVAL_SECONDS=300  # 检查间隔（5分钟）
LOG_FILE="$HOME/keepalive.log"  # 日志文件路径

echo "启动保活脚本..." > \$LOG_FILE
echo "检查间隔: \${CHECK_INTERVAL_SECONDS} 秒" >> \$LOG_FILE

while true; do
  TIMESTAMP=\$(date "+%Y-%m-%d %H:%M:%S")
  echo "\$TIMESTAMP: 执行保活操作..." >> \$LOG_FILE
  
  # 检查sing-box是否运行
  if ! pgrep -f "sing-box" > /dev/null; then
    echo "\$TIMESTAMP: sing-box未运行，尝试启动..." >> \$LOG_FILE
    $WORK_DIR/sing-box run -c $WORK_DIR/sb.json > /dev/null 2>&1 &
    echo \$! > $WORK_DIR/sing-box.pid
  else
    echo "\$TIMESTAMP: sing-box正在运行" >> \$LOG_FILE
  fi
  
  # 检查cloudflared是否运行
  if ! pgrep -f "cloudflared" > /dev/null; then
    echo "\$TIMESTAMP: cloudflared未运行，尝试启动..." >> \$LOG_FILE
    if [[ -n "\$(cat $WORK_DIR/sbargotoken.log 2>/dev/null)" ]]; then
      $WORK_DIR/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token \$(cat $WORK_DIR/sbargotoken.log) >/dev/null 2>&1 &
    else
      $WORK_DIR/cloudflared tunnel --url http://localhost:$port_vm_ws --edge-ip-version auto --no-autoupdate --protocol http2 > $WORK_DIR/argo.log 2>&1 &
    fi
    echo \$! > $WORK_DIR/sbargopid.log
  else
    echo "\$TIMESTAMP: cloudflared正在运行" >> \$LOG_FILE
  fi
  
  # 执行一些基本命令保持活动
  ls -la $HOME > /dev/null
  ps -ef > /dev/null
  
  echo "\$TIMESTAMP: 保活操作完成，休眠 \${CHECK_INTERVAL_SECONDS} 秒..." >> \$LOG_FILE
  sleep \$CHECK_INTERVAL_SECONDS
done
EOF

chmod +x $HOME/keepalive.sh
nohup $HOME/keepalive.sh > /dev/null 2>&1 &

# 输出结果
echo "ArgoSB脚本安装完毕"
echo "---------------------------------------------------------"
echo "---------------------------------------------------------"
echo "输出配置信息" && sleep 3
echo
echo "443端口的vmess-ws-tls-argo节点，默认优选IPV4：104.16.0.0"
sed -n '1p' $WORK_DIR/jh.txt
echo
echo "2096端口的vmess-ws-tls-argo节点，默认优选IPV6：[2606:4700::]（本地网络支持IPV6才可用）"
sed -n '6p' $WORK_DIR/jh.txt
echo
echo "80端口的vmess-ws-argo节点，默认优选IPV4：104.21.0.0"
sed -n '7p' $WORK_DIR/jh.txt
echo
echo "2095端口的vmess-ws-argo节点，默认优选IPV6：[2400:cb00:2049::]（本地网络支持IPV6才可用）"
sed -n '13p' $WORK_DIR/jh.txt
echo
echo "---------------------------------------------------------"
echo "聚合分享Argo节点13个端口及不死IP全覆盖：7个关tls 80系端口节点、6个开tls 443系端口节点" && sleep 3
echo
echo $baseurl
echo
echo "---------------------------------------------------------"
echo "节点信息已保存到: $WORK_DIR/jh.txt"
echo "保活脚本已启动，日志保存到: $HOME/keepalive.log"
echo "---------------------------------------------------------"
