#!/bin/bash

ppp_dir="/etc/ppp" # 定义安装目录

# 创建目录并进入
mkdir -p $ppp_dir
cd $ppp_dir

# 定义安装和管理PPP的函数
function install_ppp() {
    echo "更新系统和安装依赖..."
    apt update -y && apt install -y sudo screen unzip wget

    echo "创建目录并进入..."
    mkdir -p $ppp_dir
    cd $ppp_dir

    kernel_version=$(uname -r)
    arch=$(dpkg --print-architecture)
    echo "系统架构: $arch, 内核版本: $kernel_version"

    compare_kernel_version=$(echo -e "5.10\n$kernel_version" | sort -V | head -n1)

    if [[ $arch == "amd64" ]]; then
        if [[ $compare_kernel_version == "5.10" ]] && [[ $kernel_version != "5.10" ]]; then
            default_url="https://github.com/liulilittle/openppp2/releases/latest/download/openppp2-linux-amd64-io-uring.zip"
        else
            default_url="https://github.com/liulilittle/openppp2/releases/latest/download/openppp2-linux-amd64.zip"
        fi
    elif [[ $arch == "arm64" ]]; then
        if [[ $compare_kernel_version == "5.10" ]] && [[ $kernel_version != "5.10" ]]; then
            default_url="https://github.com/liulilittle/openppp2/releases/latest/download/openppp2-linux-aarch64-io-uring.zip"
        else
            default_url="https://github.com/liulilittle/openppp2/releases/latest/download/openppp2-linux-aarch64.zip"
        fi
    fi

    echo "默认下载地址: $default_url"
    echo "您是否想使用默认下载地址? 输入 'no' 以输入新的下载地址: "
    read use_default

    if [[ "$use_default" != "no" ]]; then
        download_url="$default_url"
    else
        echo "请输入新的下载地址:"
        read download_url
    fi

    echo "下载文件中..."
    wget "$download_url"
    echo "解压下载的文件..."
    unzip -o '*.zip' -x 'appsettings.json' && rm *.zip # 不解压appsettings.json
    chmod +x ppp

    echo "配置系统服务..."
    cat > /etc/systemd/system/ppp.service << EOF
[Unit]
Description=PPP Service with Screen
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$ppp_dir
ExecStart=/usr/bin/screen -DmS ppp $ppp_dir/ppp -m -s
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    create_or_modify_config
    echo "启用并启动PPP服务..."
    sudo systemctl enable ppp.service
    sudo systemctl daemon-reload
    sudo systemctl start ppp.service
    sudo systemctl status ppp.service
    echo "PPP服务已配置并启动。"
}

function start_ppp() {
    sudo systemctl start ppp.service
    echo "PPP服务已启动。"
}

function stop_ppp() {
    sudo systemctl stop ppp.service
    echo "PPP服务已停止。"
}

function restart_ppp() {
    sudo systemctl restart ppp.service
    echo "PPP服务已重启。"
}

function update_ppp() {
    echo "正在停止PPP服务以进行更新..."
    stop_ppp

    echo "更新PPP服务中..."
    install_ppp

    echo "重启PPP服务..."
    restart_ppp
    echo "PPP服务已更新并重启。"
}

function view_ppp_session() {
    echo "查看PPP会话..."
    screen -r ppp
}

function create_or_modify_config() {
    echo "配置或修改PPP配置文件..."
    ppp_config="$ppp_dir/appsettings.json"
    if [[ -f "$ppp_config" ]]; then
        echo "已存在配置文件：$ppp_config"
        echo "是否要编辑现有的配置文件？ (y/n)"
        read edit_choice
        if [[ "$edit_choice" == "y" ]]; then
            vim "$ppp_config"
            echo "配置文件已修改。"
            restart_ppp
        else
            echo "跳过修改。"
            retun
        fi
    else
    # 如果配置文件不存在，则重新生成配置文件
    echo -e "${yellow}重新生成${ppp_config}。${plain}"
    # 检测公网出口/内网IP来提示用户
    curl -m 10 -s ip.sb
    ip addr show eth0 | grep inet | awk '{print $2}' | cut -d/ -f1
    
    read -p "请输入VPS IP: " vps_ip
    read -p "请输入VPS 端口: " port
    # 设置监听Interface的默认值::用于ipv6
    default_lan_ip="::"
    read -p "请输入内网IP地址（默认为${default_lan_ip}，服务端保持默认值即可）: " lan_ip
    lan_ip=${lan_ip:-$default_lan_ip}
    # 设置线程数，随机uuid，避免多客户端时候冲突。
    concurrent=$(nproc)
    random_guid=$(uuidgen)
    
    echo -e "${yellow} 节点 ${vps_ip}:${port} 线程数 ${concurrent} 用户ID ${random_guid} ${plain}"
    
    cat >"${ppp_config}" <<EOF
{
    "concurrent": ${concurrent},
    "cdn": [2080, 2443],
    "key": {
        "kf": 154543927,
        "kx": 128,
        "kl": 10,
        "kh": 12,
        "protocol": "aes-128-cfb",
        "protocol-key": "N6HMzdUs7IUnYHwq",
        "transport": "aes-256-cfb",
        "transport-key": "HWFweXu2g5RVMEpy",
        "masked": false,
        "plaintext": false,
        "delta-encode": false,
        "shuffle-data": false
    },
    "ip": {
        "public": "${vps_ip}",
        "interface": "${lan_ip}"
    },
    "vmem": {
        "size": 0,
        "path": "./"
    },
    "tcp": {
        "inactive": {
            "timeout": 300
        },
        "connect": {
            "timeout": 5
        },
        "listen": {
            "port": ${port}
        },
        "turbo": true,
        "backlog": 511,
        "fast-open": true
    },
    "udp": {
        "inactive": {
            "timeout": 72
        },
        "dns": {
            "timeout": 4,
            "redirect": "0.0.0.0"
        },
        "listen": {
            "port": ${port}
        },
        "static": {
            "keep-alive": [1, 5],
            "dns": true,
            "quic": true,
            "icmp": true,
            "servers": ["${vps_ip}:${port}"]
        }
    },
    "websocket": {
        "host": "starrylink.net",
        "path": "/tun",
        "listen": {
            "ws": 20080,
            "wss": 20443
        },
        "ssl": {
            "certificate-file": "starrylink.net.pem",
            "certificate-chain-file": "starrylink.net.pem",
            "certificate-key-file": "starrylink.net.key",
            "certificate-key-password": "test",
            "ciphersuites": "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"
        },
        "verify-peer": true,
        "http": {
            "error": "Status Code: 404; Not Found",
            "request": {
                "Cache-Control": "no-cache",
                "Pragma": "no-cache",
                "Accept-Encoding": "gzip, deflate",
                "Accept-Language": "zh-CN,zh;q=0.9",
                "Origin": "http://www.websocket-test.com",
                "Sec-WebSocket-Extensions": "permessage-deflate; client_max_window_bits",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0"
            },
            "response": {
                "Server": "Kestrel"
            }
        }
    },
    "server": {
        "log": "./ppp.log",
        "node": 1,
        "subnet": true,
        "mapping": true,
        "backend": "",
        "backend-key": "HaEkTB55VcHovKtUPHmU9zn0NjFmC6tff"
    },
    "client": {
        "guid": "{${random_guid}}",
        "server": "ppp://${vps_ip}:${port}/",
        "bandwidth": 0,
        "reconnections": {
            "timeout": 5
        },
        "paper-airplane": {
            "tcp": true
        },
        "http-proxy": {
            "bind": "${lan_ip}",
            "port": 8080
        },
        "mappings": [
            {
                "local-ip": "${lan_ip}",
                "local-port": 80,
                "protocol": "tcp",
                "remote-ip": "::",
                "remote-port": 10001
            },
            {
                "local-ip": "${lan_ip}",
                "local-port": 7000,
                "protocol": "udp",
                "remote-ip": "::",
                "remote-port": 10002
            }
        ]
    }
}
EOF
        echo "新配置文件已创建。"
    fi
}

# 显示菜单并处理用户输入
PS3='请选择一个操作: '
options=("安装PPP" "启动PPP" "停止PPP" "重启PPP" "更新PPP" "查看PPP会话" "配置或修改配置文件" "退出")
select opt in "${options[@]}"
do
    case $opt in
        "安装PPP")
            install_ppp
            ;;
        "启动PPP")
            start_ppp
            ;;
        "停止PPP")
            stop_ppp
            ;;
        "重启PPP")
            restart_ppp
            ;;
        "更新PPP")
            update_ppp
            ;;
        "查看PPP会话")
            view_ppp_session
            ;;
        "配置或修改配置文件")
            create_or_modify_config
            ;;
        "退出")
            break
            ;;
        *) echo "无效选项 $REPLY";;
    esac
done