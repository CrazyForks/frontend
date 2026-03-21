#!/bin/bash

# 下载 CanvasKit 字体 fallback 所需的字体文件
# 包括：
# - Roboto：英文字体（CanvasKit fallback 机制使用）
# - NotoSansSC-Regular.otf：通过 pubspec.yaml 绑定的完整中文字体

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"
FONTS_DIR="$FRONTEND_DIR/web/fonts"
PUBSPEC_FONTS_DIR="$FRONTEND_DIR/fonts"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}下载 CanvasKit 字体文件${NC}"
echo -e "${BLUE}========================================${NC}"

# 创建目录结构
mkdir -p "$FONTS_DIR/roboto/v32"
mkdir -p "$PUBSPEC_FONTS_DIR"

# ========================================
# 下载 NotoSansSC-Regular.otf（pubspec.yaml 绑定字体）
# ========================================
echo -e "${BLUE}[1/2] 下载 NotoSansSC-Regular.otf...${NC}"

NOTO_OTF_FILE="$PUBSPEC_FONTS_DIR/NotoSansSC-Regular.otf"
if [ -f "$NOTO_OTF_FILE" ]; then
    echo -e "  [跳过] NotoSansSC-Regular.otf (已存在)"
else
    NOTO_OTF_URL="https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf"
    echo -e "  [下载] NotoSansSC-Regular.otf"
    if curl -s -f -L -o "$NOTO_OTF_FILE" "$NOTO_OTF_URL" 2>/dev/null; then
        echo -e "    ${GREEN}\u2713${NC} 成功"
    else
        rm -f "$NOTO_OTF_FILE"
        echo -e "    ${RED}\u2717${NC} 下载失败"
    fi
fi

# ========================================
# 下载 Roboto 字体
# ========================================
echo -e "${BLUE}[2/2] 下载 Roboto 字体..${NC}"

ROBOTO_FILES=(
    "KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"
)

for filename in "${ROBOTO_FILES[@]}"; do
    OUTPUT_FILE="$FONTS_DIR/roboto/v32/$filename"
    if [ -f "$OUTPUT_FILE" ]; then
        echo -e "  [跳过] $filename (已存在)"
    else
        URL="https://fonts.gstatic.com/s/roboto/v32/$filename"
        echo -e "  [下载] $filename"
        if curl -s -f -o "$OUTPUT_FILE" "$URL" 2>/dev/null; then
            echo -e "    ${GREEN}✓${NC} 成功"
        else
            rm -f "$OUTPUT_FILE"
            echo -e "    ${RED}✗${NC} 下载失败"
        fi
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ 字体下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
