# 110：城市守夜人（CITY WATCH）

一款以中国公安体系为背景的城市警力调度模拟游戏原型，气质参考 Steam 上的《112 Operator》。
你是江城市公安局滨江分局的指挥长：在预算和编制之内部署一套能自己运转的警务体系，亲自研判重大警情，维护城市治安。

- 设计文档：[`docs/GDD.md`](docs/GDD.md)
- 引擎：Godot 4.4（Forward+）
- 全部场景、城市与美术为程序化生成，无外部美术资源（字体除外，见 `assets/fonts/LICENSE.md`）

## 在线试玩

网页版位于 `docs/` 目录，通过 GitHub Pages 发布：**https://mud4u404.github.io/game002/**
（需在仓库 Settings → Pages 中选择本分支的 `/docs` 目录作为来源。首次加载约 45MB。）

网页版使用 Compatibility 渲染器，部分后处理效果比桌面版简化。重新导出网页版：

```bash
GODOT=/path/to/godot tools/export_web.sh
```

## 本地运行

1. 安装 [Godot 4.4](https://godotengine.org/download)（标准版，非 .NET）。
2. 用 Godot 打开本目录的 `project.godot`，按 F5 运行；或者命令行运行：

```bash
godot --path .
```

## 操作

| 操作 | 说明 |
|---|---|
| 滚轮 / 左键拖拽 / WASD | 缩放 / 平移地图 |
| Q / E、中键拖拽 | 旋转地图（可选） |
| 左键 | 选中警情、单位、设施 |
| 右键（已选中单位） | 点警情：手动派警；点嫌疑人：追缉；点路面：巡逻单位划定巡区，其他单位机动布控 |
| 空格 | 接听接警台来电 |
| R | 招募编组 |
| C | 设卡（再点道路放置，右键取消） |
| H | 治安热力图层 |
| L | 电台记录 |
| F | 定位到选中对象 |
| P / 1 / 2 / 3 | 暂停 / 1× / 2× / 4× |
| Esc | 关闭面板 / 取消选择 |

## 原型包含的内容

- 班前部署：研判今晚警情、组建警力、划定巡区后再开始值班
- 警种硬分工：调解 / 处突 / 交管 / 突击，缺专长的警情无法处置；点警情即出派警名单

- 中国警务创新玩法：治安热力与见警率（以巡压案）、巡区部署、1-3-5 分钟快反圈、天网追逃与设卡拦截

- 俯瞰视角的程序化虚构城市：变间距路网、江与桥、CBD / 住宅 / 老城 / 工业 / 公园街区、社会车流、昼夜循环与夜间路灯光带
- 4 类警力单位（社区警务车、巡逻警车、交警铁骑、特警突击车），自动巡逻、自动派警、疲劳与成长
- 14 类警情，按时段加权生成，超时升级（如打架斗殴 → 持械伤人 → 劫持人质）
- 110 接警台：通话问询、警情定性。报警人的描述不一定是真相，定性错误会导致警力不足或漏警
- 武力等级门槛：现场武力不足时处置停滞并请求增援
- 经费、群众安全感、舆情、编制；每日按安全感拨付经费
- 值班长"老周"的对讲式引导（没有独立的说明页）

## 目录结构

```
scenes/            主菜单、游戏场景、城市预览（开发用）
scripts/core/      GameState（时间 / 资源 / 电台总线）、Data（数值表与接警剧本）
scripts/city/      城市生成、路网寻路、社会车流、昼夜环境
scripts/units/     警务单位、车辆几何
scripts/game/      游戏主控（生成、派警、处置结算）、警情
scripts/ui/        指挥大屏 HUD 组件
scripts/menu/      主菜单
scripts/dev/       开发工具（命令行截图、无头模拟）
shaders/           建筑屋顶、路面、江面、标记、HUD 暗角等着色器
```

## 开发工具

```bash
# 截图（需要显示环境；无显卡时可用 xvfb-run + lavapipe）
godot --path . res://scenes/game.tscn -- --shot=/tmp/shot.png --shot-frames=60 [--test-call|--test-recruit|--test-busy --test-select]

# 无头长时间模拟，定期打印指标
godot --path . --headless --fixed-fps 30 res://scenes/game.tscn -- --speed=4 --quit-frames=12000
```
