# 开发笔记 / 踩坑记录

## 改了代码看不到效果?先确认跑的是哪个 app

`swift build` / `make build` 只会更新**项目目录里**的二进制和 `Sotto.app` bundle。
但日常运行的往往是 `/Applications/Sotto.app`(已安装的版本)。直接退出再重启
`/Applications/Sotto.app`,跑的还是**旧代码**,改动不会生效。

正确流程:

```sh
make install          # 重新编译 + 拷贝到 /Applications/Sotto.app
pkill -x Sotto        # 退出正在运行的实例
open /Applications/Sotto.app
```

排查时可以用 `ps aux | grep -i sotto` 看当前跑的到底是哪个路径的二进制。

## 仪表盘历史卡片:按钮错位的坑

`DashboardWindow.swift` 里的 `RecordCell`(每条历史记录的卡片)。

- 症状:编辑(铅笔)和播放按钮在不同卡片之间左右位置不一致——按钮跟着每条
  文字的末尾走,而不是钉在卡片右边缘。文字长的卡片按钮偏右,文字短的偏左。
- 真正的根因:**Auto Layout 约束冲突**。原来同时有两条 required 约束:
  1. `textStack.trailing == buttonStack.leading - 10`(文字紧贴按钮)
  2. `buttonStack.trailing == card.trailing - 12`(按钮钉右边)
  当文字宽度把 textStack 往外顶时,这两条会打架,Auto Layout 只能丢掉其中一条
  (丢掉了第 2 条),于是按钮改由文字宽度决定位置,各行就错位了。
- 修法:把第 1 条从等式 `==` 改成不等式 `<=`
  (`textStack.trailing <= buttonStack.leading - 10`)。这样它只保证「文字不越到
  按钮上」,不再强制文字宽度,永远不会和「按钮钉右边」冲突。按钮就稳稳固定在
  每张卡片的右边缘了。
- 教训:**Auto Layout 里,一个方向上不要用两条 required 等式互相定位**。想固定
  某个元素的位置,就让它单独 pin 到容器;相邻元素用 `<=`/`>=` 做避让,而不是用
  `==` 去连锁定位,否则内容一变宽就会打架、丢约束。
- 顺带:按钮栈从竖排(`.vertical` + `centerX`)改成横排一排(`.horizontal`
  + `centerY`);原文那行也从换行 label 改成截断 label(`labelWithString` +
  `maximumNumberOfLines = 1` + `.byTruncatingTail`),更干净。
