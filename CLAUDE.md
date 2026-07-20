# Sotto

macOS 菜单栏听写应用（Swift Package + AppKit）。

## 构建与验证改动

- 用户平时从 /Applications 启动 Sotto，光 `swift build` 不会更新它。
- **每次改完代码后，必须跑 `make install` 重新安装到 /Applications，然后重启 app**（退出旧进程再 `open /Applications/Sotto.app`），用户才能看到效果。
- 快速本地验证也可以用 `make run`（直接运行项目目录里的 Sotto.app，不经过 /Applications）。
