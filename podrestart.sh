#/bin/bash
#用于批量重启自定义容器并检查它们的状态，重启会根据输入提示选择启动的优先级顺序以及哪类容器
#这里以容器elk+filebeat为例，使用时需修改优先启动的 前置容器变量：$frontend_pattern 以及普通容器变量：$other_pattern
# 颜色定义
red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
nc='\033[0m'

# 容器匹配模式（精确匹配开头）
frontend_pattern="elasticsearch|logstash"
other_pattern="kibana|filebeat"

# 静默获取容器列表
get_container_list() {
    docker ps -a --filter "name=($frontend_pattern|$other_pattern)" --format "{{.Names}}" 2>/dev/null
}

# 重启函数
graceful_restart() {
    local pattern=$1
    local service_type=$2
    local success=0 failure=0

    echo -e "${yellow}正在重启${service_type}容器...${nc}"
    mapfile -t containers < <(get_container_list "$pattern")

    [ ${#containers[@]} -eq 0 ] && echo -e "${blue}未找到匹配容器${nc}" && return

    for container in "${containers[@]}"; do
        if [[ "$container" =~ ^($frontend_pattern) ]]; then
          printf "${blue}➜ %-25s" "${container}..."
          if docker restart "$container" >/dev/null; then
              ((success++))
              echo -e "${green}成功${nc}"
          else
              ((failure++))
              echo -e "${red}失败${nc}"
          fi
	fi
    done

    echo -e "\n${green}成功: ${success}${nc}"
    [ $failure -ne 0 ] && echo -e "${red}失败: ${failure}${nc}"
}

graceful_other_restart() {
    local pattern=$1
    local service_type=$2
    local success=0 failure=0

    echo -e "${yellow}正在重启${service_type}容器...${nc}"
    mapfile -t containers < <(get_container_list "$pattern")

    [ ${#containers[@]} -eq 0 ] && echo -e "${blue}未找到匹配容器${nc}" && return

    for container in "${containers[@]}"; do
        if [[ "$container" =~ ^($other_pattern) ]]; then
          printf "${blue}➜ %-25s" "${container}..."
          if docker restart "$container" >/dev/null; then
              ((success++))
              echo -e "${green}成功${nc}"
          else
              ((failure++))
              echo -e "${red}失败${nc}"
          fi
	fi
    done

    echo -e "\n${green}成功: ${success}${nc}"
    [ $failure -ne 0 ] && echo -e "${red}失败: ${failure}${nc}"
}
# 用户输入处理
read -p "$(echo -e "${blue}是否重启前置服务容器? (y/n) ➜ ${nc}")" -r restart_frontend
restart_frontend=$(echo "$restart_frontend" | tr '[:upper:]' '[:lower:]')

case ${restart_frontend} in
    y)
        echo -e "\n${green}✅  优先重启前置服务容器${nc}"
        graceful_restart "$frontend_pattern" "前置"
        graceful_other_restart "$other_pattern" "非前置"
        ;;
    n)
        echo -e "\n${yellow}⚠ 仅重启非前置服务容器${nc}"
        graceful_other_restart "$other_pattern" "非前置"
        ;;
    *|"")
        # 获取容器的状态
        echo -e "${red}❌  无效输入 ${nc}"
        echo -e "\n${blue}============== 容器状态 ==============${nc}"
        all_containers=($(get_container_list "$frontend_pattern|$other_pattern"))

        normal_count=0
        abnormal_containers=()

        for container in "${all_containers[@]}"; do
            status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
            if [[ "$status" == "running" ]]; then
                ((normal_count++))
            else
                abnormal_containers+=("${container} - ${status^}")
            fi
        done

        # 显示运行正常的容器数
        echo -e "${green}运行正常的容器数: ${normal_count}${nc}"

        # 显示异常容器及状态
        if [ ${#abnormal_containers[@]} -gt 0 ]; then
            echo -e "${red}异常容器: ${nc}"
            printf '%s\n' "${abnormal_containers[@]}"
        fi

        exit 1
        ;;
esac

# 状态检查函数
check_status() {
    local all_containers=($(get_container_list ""))
    local running=0
    local stopped=()

    [ ${#all_containers[@]} -eq 0 ] && return

    for container in "${all_containers[@]}"; do
        status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null) ||  status="unknown"
        if [[ $status == "running" ]]; then
            ((running++))
        else
            stopped+=("${container} - ${red}状态: ${status^}${nc}")
        fi
    done

    echo -e "\n${blue}============== 最终状态 ==============${nc}"
    echo -e "${green}运行正常: ${running}${nc}"
    if [ ${#stopped[@]} -gt 0 ]; then
        echo -e "${red}异常容器:"
        printf ' %s\n' "${stopped[@]}"
    fi
    echo -e "${nc}"
}

# 执行最终检查
check_status

# 自动退出
exit 0
