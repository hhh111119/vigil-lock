# Vigil · 守夜

锁屏不停机。人去休息，Mac 上的 Agent 继续跑。

- 一键盖住全部屏幕，包括正在全屏的软件。输入密码才能回来
- 锁定期间调用系统自带的 `caffeinate -di`，阻止空闲休眠和熄屏
- 后台进程、终端、Agent 全部继续跑
- **不申请**辅助功能、屏幕录制、管理员或完全磁盘访问

[下载 Vigil.app.zip](https://github.com/hhh111119/vigil-lock/releases/latest/download/Vigil.app.zip) · [Vigil.dmg](https://github.com/hhh111119/vigil-lock/releases/latest/download/Vigil.dmg) · [安装步骤](INSTALL.md)

macOS 13 或更新，Apple Silicon。第一次打开：按住 Control 点图标 → 打开。

## 用法

1. 打开 Vigil，设置解锁密码（只存在本机，Argon2id 哈希）
2. 点「立即锁定」，或点菜单栏图标 → 锁定
3. 去休息。Agent 继续跑，屏幕保持醒着
4. 回来输入密码

合上盖仍会按 macOS 规则休眠。关掉这个需要管理员权限，Vigil 故意不做。

这不是内核级保险：SSH 或恢复模式仍然能碰到这台电脑。它挡的是「旁边的人不要动」。
