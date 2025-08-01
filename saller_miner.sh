#!/bin/bash

APP_NAME="my-worker"
APP_SCRIPT="new.js"
ERROR_LOG="./error.log"
OUTPUT_LOG="./output.log"
CRON_RESTART="0 */5 * * *"

set -e
LOG_DATE=$(date '+%Y-%m-%d %H:%M:%S')

ask_memory_size() {
    echo "[$LOG_DATE] 🧠 请输入你希望分配的最大内存（单位：GB，例如 8 或 12）："
    read -p "➤ 内存大小（GB）: " MEM_GB

    if ! [[ "$MEM_GB" =~ ^[0-9]+$ ]]; then
        echo "❌ 输入错误，必须是整数（GB）"
        exit 1
    fi

    # 精确计算 NODE_ARGS（单位：MB）
    MEM_MB=$((MEM_GB * 1024))
    NODE_ARGS="--max-old-space-size=$MEM_MB"

    # MEMORY_RESTART 向下规整到最接近的 1000 的整数（单位：M）
    MEM_RESTART_MB=$(( (MEM_MB / 1000) * 1000 ))
    MEMORY_RESTART="${MEM_RESTART_MB}M"

    echo "[$LOG_DATE] ✅ 分配内存设置为："
    echo "NODE_ARGS=$NODE_ARGS"
    echo "MEMORY_RESTART=$MEMORY_RESTART"
}


install_pm2_and_config() {
    ask_memory_size

    echo "[$LOG_DATE] 🚀 安装 PM2 和系统资源限制..."
    npm install pm2@latest -g

    sudo grep -Fxq '* soft nofile 100000' /etc/security/limits.conf || echo '* soft nofile 100000' | sudo tee -a /etc/security/limits.conf
    sudo grep -Fxq '* hard nofile 100000' /etc/security/limits.conf || echo '* hard nofile 100000' | sudo tee -a /etc/security/limits.conf
    sudo grep -Fxq 'session required pam_limits.so' /etc/pam.d/common-session || echo 'session required pam_limits.so' | sudo tee -a /etc/pam.d/common-session

    pm2 startup systemd
    sudo env PATH=$PATH pm2 startup systemd -u $(whoami) --hp $HOME

    sudo mkdir -p /etc/systemd/system/pm2-$(whoami).service.d
    echo -e '[Service]\nLimitNOFILE=100000' | sudo tee /etc/systemd/system/pm2-$(whoami).service.d/override.conf

    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl restart pm2-$(whoami)

    echo "[$LOG_DATE] ✅ 启动 PM2 项目并保存状态..."

    pm2 start $APP_SCRIPT --name $APP_NAME \
      --node-args="$NODE_ARGS" \
      --max-memory-restart "$MEMORY_RESTART" \
      --cron "$CRON_RESTART" \
      --error "$ERROR_LOG" \
      --output "$OUTPUT_LOG"

    pm2 save
    echo "[$LOG_DATE] ✅ 安装和配置完成"
}

restart_project() {
    echo "[$LOG_DATE] ♻️ 正在重启项目 [$APP_NAME]..."
    pm2 restart $APP_NAME
}

view_logs() {
    echo "[$LOG_DATE] 📖 实时查看日志 [$APP_NAME]..."
    pm2 logs $APP_NAME
}

view_error_file() {
    echo "[$LOG_DATE] ⚠️ 查看错误日志文件: $ERROR_LOG"
    tail -n 100 "$ERROR_LOG" | sed "s/^/[$(date '+%Y-%m-%d %H:%M:%S')] /"
}

show_menu() {
    echo ""
    echo "🛠️  黑奴挖矿 PM2 管理脚本"
    echo "=============================="
    echo "  1. 安装并配置 PM2 Saller 项目"
    echo "  2. 重启该项目"
    echo "  3. 实时查看日志"
    echo "  4. 查看错误日志（从文件）"
    echo "=============================="
    read -p "➤ 请输入数字选项 [1-4]: " choice
    echo ""
}

# 主逻辑入口
while true; do
    show_menu

    case "$choice" in
        1)
            install_pm2_and_config
            break
            ;;
        2)
            restart_project
            break
            ;;
        3)
            view_logs
            break
            ;;
        4)
            view_error_file
            break
            ;;
        *)
            echo "❌ 无效选项，请输入 1 到 4。"
            ;;
    esac
done
