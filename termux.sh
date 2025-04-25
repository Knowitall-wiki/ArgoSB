#!/data/data/com.termux/files/usr/bin/bash

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo "knowitall 谷歌手机pixel Termux专用一键节点生成脚本"
echo "当前版本：25.4.25 Termux专用版"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# Termux目录
TERMUX_HOME="/data/data/com.termux/files/home"
TERMUX_PREFIX="/data/data/com.termux/files/usr"
INSTALL_DIR="$TERMUX_HOME/argo-sb"

# 创建安装目录
mkdir -p $INSTALL_DIR

# 检测CPU架构
case $(uname -m) in
    aarch64) cpu=arm64;;
    x86_64) cpu=amd64;;
    *) echo "目前脚本不支持$(uname -m)架构" && exit;;
esac

# 安装依赖
pkg update -y
pkg install -y curl wget tar gzip jq openssl coreutils procps

# 生成随机端口和UUID
port_vm_ws=$(shuf -i 10000-65535 -n 1)
UUID=$(cat /proc/sys/kernel/random/uuid)

echo "当前vmess主协议端口：$port_vm_ws"
echo "当前uuid密码：$UUID"

# 下载sing-box
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
sbname="sing-box-$sbcore-linux-$cpu"
echo "下载sing-box最新正式版内核：$sbcore"
curl -L -o $INSTALL_DIR/sing-box.tar.gz -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz

if [[ -f "$INSTALL_DIR/sing-box.tar.gz" ]]; then
    tar xzf $INSTALL_DIR/sing-box.tar.gz -C $INSTALL_DIR
    mv $INSTALL_DIR/$sbname/sing-box $INSTALL_DIR
    rm -rf $INSTALL_DIR/{sing-box.tar.gz,$sbname}
else
    echo "下载失败，请检测网络"
    exit 1
fi

# 创建配置文件 - 使用系统代理
cat > $INSTALL_DIR/sb.json <<EOF
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
                "certificate_path": "$INSTALL_DIR/cert.pem",
                "key_path": "$INSTALL_DIR/private.key"
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

# 下载cloudflared
echo "下载cloudflared-argo最新正式版内核"
curl -L -o $INSTALL_DIR/cloudflared -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
chmod +x $INSTALL_DIR/cloudflared

# 创建启动脚本
cat > $INSTALL_DIR/start.sh <<EOF
#!/data/data/com.termux/files/usr/bin/bash

cd $INSTALL_DIR

# 启动sing-box
./sing-box run -c sb.json > sing-box.log 2>&1 &
echo \$! > sing-box.pid

# 等待sing-box启动
sleep 3

# 启动cloudflared
./cloudflared tunnel --url http://localhost:$port_vm_ws --edge-ip-version auto --no-autoupdate --protocol http2 > argo.log 2>&1 &
echo \$! > cloudflared.pid

echo "服务已启动"
echo "查看Argo域名请运行: cat $INSTALL_DIR/argo.log | grep trycloudflare.com"
EOF

chmod +x $INSTALL_DIR/start.sh

# 创建停止脚本
cat > $INSTALL_DIR/stop.sh <<EOF
#!/data/data/com.termux/files/usr/bin/bash

cd $INSTALL_DIR

if [ -f cloudflared.pid ]; then
    kill \$(cat cloudflared.pid) 2>/dev/null
    rm cloudflared.pid
fi

if [ -f sing-box.pid ]; then
    kill \$(cat sing-box.pid) 2>/dev/null
    rm sing-box.pid
fi

echo "服务已停止"
EOF

chmod +x $INSTALL_DIR/stop.sh

# 启动服务
$INSTALL_DIR/start.sh

# 等待Argo隧道建立
echo "申请Argo临时隧道中……请稍等"
sleep 10


# 获取Argo域名
argodomain=$(cat $INSTALL_DIR/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')

if [[ -n $argodomain ]]; then
    echo "Argo临时隧道申请成功，域名为：$argodomain"
    
    # 生成节点信息
    hostname=$(hostname)
    
    # 创建节点文件
    touch $INSTALL_DIR/node.txt
    
    # 生成多个节点配置
    # 443端口TLS节点
    vmatls_link1="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-443\", \"add\": \"104.16.0.0\", \"port\": \"443\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
    echo "$vmatls_link1" > $INSTALL_DIR/node.txt
    
    # 8443端口TLS节点
    vmatls_link2="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-8443\", \"add\": \"104.17.0.0\", \"port\": \"8443\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
    echo "$vmatls_link2" >> $INSTALL_DIR/node.txt
    
    # 2053端口TLS节点
    vmatls_link3="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-tls-argo-$hostname-2053\", \"add\": \"104.18.0.0\", \"port\": \"2053\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)"
    echo "$vmatls_link3" >> $INSTALL_DIR/node.txt
    
    # 80端口非TLS节点
    vma_link7="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-80\", \"add\": \"104.21.0.0\", \"port\": \"80\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
    echo "$vma_link7" >> $INSTALL_DIR/node.txt
    
    # 8080端口非TLS节点
    vma_link8="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"vmess-ws-argo-$hostname-8080\", \"add\": \"104.22.0.0\", \"port\": \"8080\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$UUID-vm?ed=2048\", \"tls\": \"\"}" | base64 -w0)"
    echo "$vma_link8" >> $INSTALL_DIR/node.txt
    
    # 生成聚合分享链接
    baseurl=$(base64 -w 0 < $INSTALL_DIR/node.txt)
    
    echo "脚本安装完毕"
    echo "---------------------------------------------------------"
    echo "输出配置信息"
    echo
    echo "443端口的vmess-ws-tls-argo节点，默认优选IPV4：104.16.0.0"
    sed -n '1p' $INSTALL_DIR/node.txt
    echo
    echo "80端口的vmess-ws-argo节点，默认优选IPV4：104.21.0.0"
    sed -n '4p' $INSTALL_DIR/node.txt
    echo
    echo "---------------------------------------------------------"
    echo "聚合分享Argo节点链接："
    echo
    echo $baseurl
    echo
    echo "---------------------------------------------------------"
    echo "启动命令: $INSTALL_DIR/start.sh"
    echo "停止命令: $INSTALL_DIR/stop.sh"
    echo "节点信息保存在: $INSTALL_DIR/node.txt"
else
    echo "Argo临时隧道申请失败，请稍后再试"
    $INSTALL_DIR/stop.sh
fi
