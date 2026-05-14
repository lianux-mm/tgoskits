#!/bin/bash
# 遇到错误立即停止执行
set -e

# 1. 依赖检查
if ! command -v mkimage &> /dev/null; then
    echo "❌ 致命错误: 未找到 mkimage 命令！请先执行: brew install u-boot-tools"
    exit 1
fi

if ! command -v picocom &> /dev/null; then
    echo "❌ 致命错误: 未找到 picocom 命令！请先在 Mac 终端执行: brew install picocom"
    exit 1
fi

MAC_IFACE="en7"

echo "[1/5] 配置 Mac 宿主机网络 ($MAC_IFACE)..."
sudo ifconfig $MAC_IFACE 192.168.1.100 netmask 255.255.255.0 up

echo "[2/5] 初始化 TFTP 容器环境..."
mkdir -p ~/tftpboot
chmod -R 777 ~/tftpboot
docker rm -f tftp-server 2>/dev/null || true
docker run -d --name tftp-server --restart unless-stopped -p 69:69/udp -v ~/tftpboot:/var/tftpboot 3x3cut0r/tftpd-hpa:latest

echo "[3/5] 编译 StarryOS (aarch64)..."
cargo xtask starry quick-start orangepi-5-plus build
cargo xtask starry build --config os/StarryOS/configs/board/orangepi-5-plus.toml

echo "[4/5] 部署镜像与设备树并打包 uImage..."
cp target/aarch64-unknown-none-softfloat/release/starryos.bin ~/tftpboot/

# 🌟 精确制导：直接拷贝源码树里的静态 DTB 文件
cp os/StarryOS/configs/board/orangepi-5-plus.dtb ~/tftpboot/

cd ~/tftpboot
mkimage -A arm64 -O linux -T kernel -C none -a 0x40000000 -e 0x40000000 -n "StarryOS" -d starryos.bin uImage

echo "========================================"
echo "🎉 宿主机编译与网络部署已 100% 完成！"
echo "========================================"

echo "[5/5] 自动寻找并连接开发板串口..."
SERIAL_DEV=$(ls /dev/cu.usbserial* 2>/dev/null | head -n 1)

if [ -n "$SERIAL_DEV" ]; then
    echo "👉 发现串口设备: $SERIAL_DEV"
    echo "⚠️  注意: 进入终端后如果黑屏，请给开发板【重新上电/按复位键】"
    echo "⚠️  出现字幕时请【疯狂按回车键】打断启动，进入 U-Boot 命令行！"
    echo "👉 退出 picocom 请按: Ctrl+A 然后按 Ctrl+X"
    sleep 3
    # 🌟 自动拉起 picocom，动态对接识别到的开发板！
    picocom -b 1500000  $SERIAL_DEV
else
    echo "❌ 未检测到 USB 串口设备 (/dev/cu.usbserial*)，请检查串口线是否插好！"
    echo "如果你确认插好了，请手动使用 picocom 命令连接对应的设备号。"
fi