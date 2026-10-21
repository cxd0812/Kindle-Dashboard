# Kindle Dashboard

[English](README-en.md)

一个简单的 KUAL 插件，能够将你的越狱版 Kindle 变成一个低功耗的电子墨水仪表盘。它会定期自动从指定的 URL 下载图片并显示在屏幕上。

![Real Shot](demo_shot.avif)

## ✨ 功能特点

*   **独占模式**：自动关闭 Kindle 原生 Framework，防止原生界面干扰或进入休眠，完全接管屏幕控制权。
*   **自动联网**：每次更新前强制唤醒 WiFi，确保图片能够成功下载。
*   **定时刷新**：可自定义刷新间隔（默认 1 小时）。
*   **高质量渲染**：集成 [FBInk](https://github.com/NiLuJe/FBInk)，支持高质量波形刷新 (GC16)，减少残影。
*   **错误处理**：如果网络请求失败，会在屏幕上显示错误提示，而不是黑屏或卡死。
*   **本地时钟叠加**：支持在图片上方叠加显示当前时间，每分钟自动局部刷新，无需联网。
*   **智能休眠**：脚本会自动对齐系统时间，在每分钟的 00 秒唤醒刷新时钟，最大程度节省电量。
*   **图片预处理工具**：附带 Python 脚本，用于将普通图片转换为最适合 Kindle 显示的 16 级灰度抖动图像。

## 🖥️ 配套服务端

为了充分发挥本插件的潜力，建议配合专门开发的 **Kindle Dashboard Server** 使用：

*   **项目地址**: [https://github.com/t0saki/Kindle-Dashboard-Server](https://github.com/t0saki/Kindle-Dashboard-Server)
*   **功能**:
    *   **专为 Kindle 优化**: 渲染 1680x1264 高分辨率、16级灰度抖动图像，完美适配 E-ink 屏。
    *   **丰富数据**: 集成天气、空气质量、日历、股票/加密货币走势、Hacker News 等信息。
    *   **高度定制**: 支持多语言、全球天气、自定义布局。
    *   **易于部署**: 支持 Docker 一键部署。

## �🛠️ 前置要求

1.  **Kindle 已越狱**。
2.  已安装 **KUAL** (Kindle Unified Application Launcher)。
3.  (可选) 已安装 MRPI (MobileRead Package Installer) 以便管理提取。

## 📥 安装步骤

1.  将本项目中的 `extensions` 文件夹复制到你的 Kindle 根目录。
    *   如果提示合并，请选择确认。
    *   最终路径结构应为：`Kindle磁盘根目录/extensions/Kindle-Dashboard/...`
2.  断开 USB 连接。

## ⚙️ 配置方法

默认配置位于 `extensions/Kindle-Dashboard/bin/run_daemon.sh` 文件中。你需要修改以下变量：

```bash
# 图片地址 (请修改为你服务端的实际地址)
IMG_URL="https://your-server.com/dashboard.png"

# 图片刷新间隔 (秒)
INTERVAL=300

# 全刷周期 (多少次局刷后执行一次全刷以清除残影)
FULL_REFRESH_CYCLE=12

# 屏幕旋转 (0=0°, 1=90°, 2=180°, 3=270°)
ROTATE=3

# =============== 本地时钟配置 ===============
# 是否开启本地时钟 (1=开启, 0=关闭)
ENABLE_LOCAL_CLOCK=1

# 800×600 横屏学习看板的时钟（坐标为旋转后的屏幕坐标）
CLOCK_X=24
CLOCK_Y=51
# FBInk px 字体行高；IBM Plex Mono 的 78px 约对应网页 60px 字号
CLOCK_SIZE=78
TIME_FORMAT=24

# 字体路径 (可选，留空则使用 fbink 默认字体)
# CLOCK_FONT="${BASE_DIR}/IBMPlexMono-SemiBold.ttf"
```

**建议**：请确保你的服务端生成的图片分辨率与你的 Kindle 屏幕分辨率一致（例如 Kindle Oasis 2/3 为 1264x1680），以获得最佳显示效果。

学习看板版默认按 **800×600 横屏图片**定位本地时钟，每分钟先擦除左上角的旧时间，再绘制本机时间，不需要每分钟下载整张图。请将 `IMG_URL` 改为自己服务端的 `/render` 地址；仓库中的示例地址不是你的学习看板。`ROTATE` 仍需沿用自己设备上可正常横屏的值。若服务端输出尺寸或设备旋转后的分辨率不同，需要同步调整这些坐标，不能直接套用 800×600 参数。插件使用 IBM Plex Mono，字形会与服务端的中文无衬线字体略有区别。

## 🚀 使用方法

1.  在 Kindle 上打开 **KUAL**。
2.  点击 **Kindle-Dashboard** 菜单。
3.  点击 **Start Dashboard (No GUI)**。
4.  此时 Kindle 的原生界面将会消失，屏幕将开始刷新你的仪表盘图片。

> **⚠️ 注意**：启动时，屏幕可能会多次闪烁，并可能出现一些临时的报错信息（脚本正在清理后台进程）。这是正常现象，请耐心等待约 **1 分钟** 让服务完全启动。

**已验证设备**：本项目已在 **Kindle Oasis 2** 和 **Kindle Paperwhite 3** 上通过测试。请注意 **Kindle Paperwhite 3** 旋转参数不同，2为横屏。

**如何退出？**
单指在屏幕任意位置保持不动，长按至少 **3 秒后松手**，插件会停止刷新并恢复 Kindle 原生界面，无需重启整机。若回到主页，点开书即可继续阅读。新版会在关闭原生界面前检查触摸监听是否可用。

此修改为 Kindle 7 / 固件 5.12.2.2.2 准备，尚待真实设备验证。安装、备用退出方式和排查步骤见 [退出手势说明](退出手势说明.md)。从旧版升级时，先重启退出旧进程，再覆盖整个插件目录并从 KUAL 重新启动。

## 🖼️ 图片转换工具

为了在 E-Ink 屏幕上获得最佳显示效果（避免严重的色阶断层），建议使用本仓库提供的 `convert_kindle_image.py` 脚本处理你的图片。

该脚本会自动执行：
1.  调整大小至目标分辨率 (默认 1264x1680)。
2.  转换为 16 级灰度。
3.  应用 Floyd-Steinberg 抖动算法。

**依赖安装：**
```bash
pip install pillow
```

**使用示例：**
```bash
python convert_kindle_image.py your_image.png
# 输出文件将命名为: your_image_k_fixed.png
```

## 📜 鸣谢 & 声明

*   **FBInk**: 本项目使用了 `FBInk` 工具用于屏幕刷新。
    *   文件路径: `extensions/Kindle-Dashboard/bin/fbink`
    *   该二进制文件编译自: [https://github.com/NiLuJe/FBInk](https://github.com/NiLuJe/FBInk)
    *   感谢 **NiLuJe** 开发了这个强大的 E-Ink 屏幕控制库。

## ⚠️ 免责声明

本项目需要越狱设备并修改系统进程。虽然一般来说是安全的，但请自行承担修改系统带来的风险。作者不对设备损坏负责。

## 📄 许可证

本项目采用 MIT License 许可证。其中FBInk的许可证请参考 [FBInk](https://github.com/NiLuJe/FBInk)。
