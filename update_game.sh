#!/bin/bash
#从tmp/下同步 更新 SRC_EXEC 和 SRC_CONFIG，并根据旧镜像启动新容器 -e 变量中 tag 自增长

# 定义容器列表
APP_LIST=("app1" "app2" "app3") 

# 错误记录
SYNC_ERRORS=()
MISSING_SOURCES=()
MISSING_TARGETS=()

# 无效容器名称
INVALID_APPS=()

# 容器统计
UPDATED_APP_COUNT=0
STARTED_APP_COUNT=0

# 日志相关配置
LOG_FILE="/var/log/APP_update.log"

# 时间戳函数
log() {
    local msg="$1"
    echo -e "\033[34m[$(date +'%Y-%m-%d %H:%M:%S')] $msg\033[0m"
}


# 处理单个容器的函数
process_APP() {
    local APP_NAME=$1
    local MAX_NUM=$(docker ps -a --filter "name=${APP_NAME}_" --format "{{.Names}}" | grep -Eo "${APP_NAME}_[0-9]+" | awk -F_ '{print $NF}' | sort -n | tail -n 1)
    local NEXT_NUM=$(( MAX_NUM + 1 ))
    local HAS_ERROR=0
    local EXEC_SYNC_SUCCESS=0 # 用于标记执行文件同步是否成功
    log "正在处理 $APP_NAME..."

    UPDATED_APP_COUNT=$((UPDATED_APP_COUNT + 1))
    
    # 定义源目录和目标目录
    local SRC_EXEC="/app/tmp/$APP_NAME/$APP_NAME"
    local TARGET_DIR="/app/$APP_NAME"
    local SRC_CONFIG="/app/tmp/$APP_NAME/configfile"
    
    # 记录缺失的目录
    local MISSING_SRC=()
    local MISSING_TARGET=()
    
    # 检查执行文件同步
    if [ ! -f "$SRC_EXEC" ]; then
        MISSING_SRC+=("执行文件源:$SRC_EXEC  ")
        HAS_ERROR=1
    else
        if [ ! -d "$TARGET_DIR" ]; then
            MISSING_TARGET+=("目标目录:$TARGET_DIR  ")
            HAS_ERROR=1
        else
	        if [ ! -f $TARGET_DIR/$APP_NAME ];then
                MISSING_TARGET+=("目标执行文件:$TARGET_DIR/$APP_NAME")
		        HAS_ERROR=1
	        else
                log "同步执行文件..."
                rsync -avz --info=progress2 "$SRC_EXEC" "$TARGET_DIR"/ >> "$LOG_FILE"
                echo -e "$(date '+%Y-%m-%d %H:%M:%S') rsync completed" >> "$LOG_FILE"
                if [ $? -eq 0 ]; then
                    EXEC_SYNC_SUCCESS=1 # 标记执行文件同步成功
                else
                    log "执行文件同步失败"
                    HAS_ERROR=1
                fi
            fi
        fi
    fi
    
    # 检查配置文件同步
    if [ ! -d "$SRC_CONFIG" ]; then
        MISSING_SRC+=("配置文件源:$SRC_CONFIG")
        HAS_ERROR=1
    else
        if [ ! -d "$TARGET_DIR/configfile" ]; then
            MISSING_TARGET+=("目标配置文件:$TARGET_DIR/configfile")
            HAS_ERROR=1
        else
            log "同步配置文件..."
            rsync -avz --info=progress2 "$SRC_CONFIG"/ "$TARGET_DIR/configfile"/ >> "$LOG_FILE"
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') rsync completed" >> "$LOG_FILE"
            if [ $? -ne 0 ]; then
                log "配置文件同步失败"
                HAS_ERROR=1
            else
               EXEC_SYNC_SUCCESS=1
            fi
        fi
    fi
    
    # 记录错误信息
    if [ $HAS_ERROR -eq 1 ]; then
        if [ ${#MISSING_SRC[@]} -gt 0 ]; then
            MISSING_SOURCES+=("$APP_NAME: ${MISSING_SRC[*]}")
        fi
        if [ ${#MISSING_TARGET[@]} -gt 0 ]; then
            MISSING_TARGETS+=("$APP_NAME: ${MISSING_TARGET[*]}")
        fi
    fi
    
    # 启动Docker容器
    if [ $EXEC_SYNC_SUCCESS -eq 1 ]; then
        log "启动容器 $APP_NAME..."
	echo -ne "\033[34m"
	local CONTAINER_NAME="${APP_NAME}_${NEXT_NUM}"
        docker run -e RoomId="${APP_NAME}_${NEXT_NUM}" -e SCREENID=1 -it \
            --name "${APP_NAME}_${NEXT_NUM}" -v /app/"$APP_NAME":/app -d "$APP_NAME"
	echo -ne "\033[0m"
	 STARTED_APP_COUNT=$((STARTED_APP_COUNT + 1))
	 STARTED_CONTAINERS+=("$CONTAINER_NAME")
    else
        echo -e "\033[31m由于执行文件同步失败，容器未启动\033[0m"
    fi
}

# 报告同步错误
report_errors() {
    if [ ${#MISSING_SOURCES[@]} -gt 0 ] || [ ${#MISSING_TARGETS[@]} -gt 0 ] || [ ${#INVALID_APPS[@]} -gt 0 ]; then
        echo -e "\n\033[31m========== 同步错误报告 ==========\033[0m"

	# 输出无效的容器名称
        if [ ${#INVALID_APPS[@]} -gt 0 ]; then
            echo -e "\033[33m无效的容器名称:\033[0m"
            for error in "${INVALID_APPS[@]}"; do
                echo "  - $error"
            done
        fi
        
        if [ ${#MISSING_SOURCES[@]} -gt 0 ]; then
            echo -e "\033[33m以下容器的源目录不存在:\033[0m"
            for error in "${MISSING_SOURCES[@]}"; do
                echo "  - $error"
            done
        fi
        
        if [ ${#MISSING_TARGETS[@]} -gt 0 ]; then
            echo -e "\n\033[33m以下容器的目标目录不存在:\033[0m"
            for error in "${MISSING_TARGETS[@]}"; do
                echo "  - $error"
            done
        fi
        
        echo -e "\n\033[32m其他操作已成功完成\033[0m"
    else
        echo -e "\n\033[32m所有操作已成功完成，没有发现目录错误\033[0m"
    fi

    echo -e "\n\033[34m========== 容器更新统计 ==========\033[0m"
    echo -e "\033[32m尝试更新的容器数量: $UPDATED_APP_COUNT\033[0m"
    echo -e "\033[32m尝试启动的容器数量: $STARTED_APP_COUNT\033[0m"

    if [ ${#STARTED_CONTAINERS[@]} -gt 0 ]; then
        echo -e "\033[32m更新的容器名称:\033[0m"
        echo -e "\033[32m${STARTED_CONTAINERS[*]}\033[0m" | sed 's/ /  /g'
    fi

}

# 参数处理
if [ $# -gt 0 ]; then
    for i in "$@"; do
        if [[ "${APP_LIST[*]}" =~ "${i}" ]]; then
            process_APP "${i}"
	        echo "----------------------------------------------------------------"
        else
	        INVALID_APPS+=("${i}")
        fi
    done
    report_errors
    exit 0
fi

# 无参数时显示交互菜单
echo -ne "\033[34m"
echo "未指定容器名称，请选择操作："
PS3='请选择操作编号: '
options=("更新所有容器" "选择特定容器" "退出")
select opt in "${options[@]}"; do
    case $opt in
        "更新所有容器")
            echo "开始更新所有容器..."
            for APP in "${APP_LIST[@]}"; do
                process_APP "$APP"
                echo "----------------------------------------------------------------"
            done
            report_errors
            break
            ;;
        "选择特定容器")
            read -e -p "请输入容器名称（多个用空格分隔）: " -a selected_APPs
            
            # 验证输入的容器
            for APP in "${selected_APPs[@]}"; do
                if [[ "${APP_LIST[*]}" =~ "${APP}" ]]; then
                    process_APP "$APP"
                    echo "----------------------------------------------------------------"
                else
		            echo -e "\033[33m警告: 跳过无效容器 '$APP'\033[0m"
                fi
            done
            report_errors
            break
            ;;
        "退出")
            echo "操作已取消"
            exit 0
            ;;
        *) 
            echo "无效选项，请重新选择"
            ;;
    esac
done
echo -ne "\033[0m"

