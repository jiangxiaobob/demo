#!/bin/bash
#同步至指定服务器和路径

# 定义服务器和路径
# 因配置了socks5所以需 proxychains 
SERVER_EG="IP"
SERVER_NIRI="IP"
SERVER_Hdi="IP"
TARGET_PATH="app/tmp"
RSYNC_USER="rsync"
RSYNC_PASSWD="/root/rsync-tak/formal-rsync.passwd"
LOG_FILE="/root/rsync-tak/arsync.log"

info()    { echo -e "\033[1;34m[$(date +%T)] $1\033[0m"; }
success() { echo -e "\033[1;32m[$(date +%T)] ✅ $1\033[0m"; }
error()   { echo -e "\033[1;31m[$(date +%T)] ❌ $1\033[0m"; }

# 检查源文件是否存在
check_file_or_directory() {
    local path="$1"
    if [[ -f "$path" || -d "$path" ]]; then
        return 0
    else
        return 1
    fi
}

# 提示用户输入源文件路径，并检查两次
attempts=0
while [ $attempts -lt 2 ]; do
    read -e -p $'\033[1;34m请输入源文件或目录完整路径: \033[0m' SOURCE_FILE

    if check_file_or_directory $SOURCE_FILE; then
        break
    else
        info "路径 $SOURCE_FILE 不存在，请重新输入"
        attempts=$((attempts + 1))
    fi
done

if [ $attempts -eq 2 ]; then
    error "错误：两次输入均无效，脚本已退出。"
    exit 1
fi

# 函数：同步到指定服务器
sync_to_server() {
    local server="$1"
    local server_name="$2"
    info "正在同步到 $server_name ($server) ..."
    proxychains rsync -avz --password-file="$RSYNC_PASSWD" --info=progress2 "$SOURCE_FILE" "rsync://$RSYNC_USER@$server/$TARGET_PATH" 2>&1 | sed 's/\r//g; s/\x1B\[[0-9;]*[a-zA-Z]//g' | tee -a $LOG_FILE | while read line; do 
        # 提取进度信息
        if [[ "$line" =~ ([0-9]+)% ]]; then
            PERCENT=${BASH_REMATCH[1]}
            # 动态更新进度条
            echo -ne "\033[1;32m进度: ["
            for ((i=0; i<100; i+=5)); do
                if ((i < PERCENT)); then
                    echo -n "#"
                else
                    echo -n " "
                fi
            done
            echo -ne "] $PERCENT% \033[0m\r"
        fi
    done

    #获取状态码
    RSYNC_EXIT_CODE=${PIPESTATUS[0]}

    if [ $RSYNC_EXIT_CODE -eq 0 ]; then
        success "源目录文件 $SOURCE_FILE"
        success "成功同步到 $server_name ($server/$TARGET_PATH)"
    else
        error "同步到 $server_name ($server) 失败 日志：$LOG_FILE"
    fi
}

# 显示菜单并处理选择
show_menu() {
    PS3=$'\033[1;34m请选择操作编号 (1-4): \033[0m'
    options=("同步至埃及 ($SERVER_EG)" "同步至尼日 ($SERVER_NIRI)" "同步至印尼 ($SERVER_Hdi)" "退出")
    select opt in "${options[@]}"; do
        case $opt in
            "同步至埃及 ($SERVER_EG)")
                sync_to_server "$SERVER_EG" "埃及服务器"
                exit 0
                ;;
            "同步至尼日 ($SERVER_NIRI)")
                sync_to_server "$SERVER_NIRI" "尼日服务器"
                exit 0
                ;;
            "同步至印尼 ($SERVER_Hdi)")
                sync_to_server "$SERVER_Hdi" "印尼服务器"
                exit 0
                ;;
            "退出")
                info "未选择同步任何服务器，脚本已退出。"
                exit 0
                ;;
            *)
                INVALID_COUNT=$((INVALID_COUNT + 1))
                info "无效输入，请输入 1-4 的数字"

                if [ $INVALID_COUNT -ge 2 ]; then
                    info "两次输入无效，脚本已退出。"
                    exit 1
                fi
                continue
                ;;
        esac
        break
    done
}

# 主菜单循环
INVALID_COUNT=0
while true; do
    show_menu
done


