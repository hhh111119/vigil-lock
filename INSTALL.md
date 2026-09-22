# 安装 Vigil

macOS 13 或更新，Apple Silicon（M 系列）。没有经过 Apple 公证，所以第一次打开要手动放行。

## 下载

打开 [最新发布](https://github.com/hhh111119/vigil-lock/releases/latest)，下载其中一个：

- [Vigil.app.zip](https://github.com/hhh111119/vigil-lock/releases/latest/download/Vigil.app.zip)
- [Vigil.dmg](https://github.com/hhh111119/vigil-lock/releases/latest/download/Vigil.dmg)

## 装到这台 Mac

1. 解压 zip，或打开 dmg。
2. 把 `Vigil` 拖进「应用程序」。
3. 第一次打开不要双击。按住 Control 点图标，选「打开」，再点「打开」。
4. 如果系统说已损坏或来自身份不明的开发者：

   ```bash
   xattr -dr com.apple.quarantine /Applications/Vigil.app
   ```

   然后再按住 Control 点图标 → 打开。

Vigil 不出现在 Dock 里。菜单栏上有一个圆圈图标。点它可以看到「打开」「锁定」「退出」。

## 第一次使用

1. 打开后设解锁密码。密码只存在这台 Mac 上，存的是 Argon2id 哈希，不是登录密码。
2. 点「立即锁定」，或点菜单栏图标 → 锁定。
3. 每块屏幕都会被盖住，包括正在全屏的软件。输入密码才能回来。
4. 默认会在锁定期间运行 `caffeinate -di`，避免空闲休眠和熄屏。合上盖仍然会按 macOS 的规则休眠。

这不是内核级锁。旁边的人打不开屏幕，但 SSH 或恢复模式仍然能碰到这台电脑。

## 从源码构建

需要 Xcode 命令行工具里的 Swift。

```bash
git clone https://github.com/hhh111119/vigil-lock.git
cd vigil-lock
scripts/build-app.sh
open build/Vigil.app
```

`scripts/build-app.sh` 会编出 `build/Vigil.app` 并做临时签名。要装进「应用程序」：

```bash
cp -R build/Vigil.app /Applications/
```
