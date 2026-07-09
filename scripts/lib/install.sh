# ============================================================
#  lib/install.sh — 注册/卸载全局命令
# ============================================================

install_command() {
    local target="${SCRIPT_PATH}"

    echo
    echo -e "${BOLD}  安装 ${CMD_NAME} 全局命令${NC}"
    echo

    if [[ -d "/usr/local/bin" ]]; then
        if command -v sudo &>/dev/null; then
            echo -e "  ${DIM}使用 sudo 安装到 /usr/local/bin/${CMD_NAME} ...${NC}"
            if sudo ln -sf "$target" "/usr/local/bin/${CMD_NAME}" 2>/dev/null && \
               sudo chmod +x "/usr/local/bin/${CMD_NAME}" 2>/dev/null; then
                echo
                echo -e "  ${GREEN}✓${NC} 已安装: ${BOLD}/usr/local/bin/${CMD_NAME}${NC}"
                echo
                echo -e "  使用方法: ${BOLD}sudo ${CMD_NAME} [backup|restore|deploy]${NC}"
                return 0
            else
                echo -e "  ${RED}sudo 执行失败，请手动运行:${NC}"
                echo -e "    ${BOLD}sudo ln -sf \"$target\" /usr/local/bin/${CMD_NAME}${NC}"
            fi
        else
            echo -e "  ${YELLOW}未找到 sudo，请手动执行:${NC}"
            echo -e "    ${BOLD}ln -sf \"$target\" /usr/local/bin/${CMD_NAME}${NC}"
        fi
    else
        echo -e "  ${RED}/usr/local/bin 目录不存在${NC}"
    fi

    echo -e "  ${RED}无法自动安装，请手动执行:${NC}"
    echo
    echo -e "    ${BOLD}sudo ln -sf \"$target\" /usr/local/bin/${CMD_NAME}${NC}"
    return 1
}

uninstall_command() {
    echo
    echo -e "${BOLD}  卸载 ${CMD_NAME} 全局命令${NC}"
    echo

    local removed=0
    for dir in "/usr/local/bin" "${HOME}/.local/bin"; do
        local link="${dir}/${CMD_NAME}"
        if [[ -L "$link" ]]; then
            echo -e "  ${BLUE}→${NC} 删除 ${link}"
            rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
            ((removed++)) || true
        fi
    done

    if [[ $removed -eq 0 ]]; then
        echo -e "  ${YELLOW}未找到已安装的 ${CMD_NAME}${NC}"
    else
        echo
        echo -e "  ${GREEN}✓${NC} 已卸载"
    fi
    echo
    echo -e "  ${DIM}本地使用方式: bash ${SCRIPT_PATH}${NC}"
}
