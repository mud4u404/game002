# AGENTS.md —— 协作手册（给参与本仓库编码的 AI 与开发者）

《110：城市守夜人》是一款 Godot 4.4.1（GDScript）俯瞰视角的中国城市警务调度游戏，参考 Steam《112 Operator》的气质，玩法以中国警务为核心。
**动手前先读完本文件**，再读 `docs/GDD.md` 里与任务相关的章节。

---

## 1. 协作流程

本仓库可能有**多个 AI 同时编码**。每个 AI 有自己的名字（下文用 `<名字>` 表示，如 `mavis`），由仓库主人告知。

| 步骤 | 做法 |
|---|---|
| 领任务 | **只做带 `for-<名字>` 标签的 Issue**（例如 `for-mavis`）。别人的标签一律不碰。开工时在 Issue 下留言"<名字> 认领"。 |
| 建分支 | 从最新 `main` 切出 `<名字>/<issue号>-<短名>`，例如 `mavis/1-day-report`。**只推送自己前缀的分支**。 |
| 改文件 | Issue 里写了"允许修改的文件"时，**只能改这些文件**。确实需要改别的文件，先在 Issue 下说明原因，等回复再动手。 |
| 提交 | 小步提交，提交说明用中文或英文均可，写清"做了什么、为什么"。 |
| 提 PR 前 | 先 `git fetch origin && git merge origin/main`，把最新 `main` 合进自己的分支。有冲突时**保留双方的改动**；看不懂别人的代码时，停下来在 PR 里说明，不要删。 |
| 提 PR | 目标分支 `main`。标题以 `[<名字>]` 开头并引用 Issue（`[mavis] #1 值班日报`）。正文按第 6 节模板填写。**每个 AI 同时只能有一个未合并的 PR。** |
| 审查 | 由 Claude 审查。收到 review 后逐条修改或回复理由，改完 push 到同一分支，并在 PR 下留言"已按审查修改"。 |
| 合并 | 审查通过后由仓库主人合并。**不要自己合并，不要强推（`--force`）任何分支。** |

**实时通知（必须做）**：每完成一件事——提交新 PR、按审查改完、对 Issue 有疑问——都要到**调度频道 PR #6** 下留一行评论，例如 `PR #7 已提交，请审查`。这会立即唤醒审查者，不留言就要等最长 1 小时的巡检。

**边界纪律**
- 不修改、不评论、不审查、不合并其他 AI 的分支和 PR。发现别人的问题，告诉仓库主人。
- 只改 Issue 要求的内容。发现别的问题，写在 PR 正文"顺带发现"里，不要顺手改。
- 推送被拒绝时，先 `git fetch` 再合并，**绝不强推**。

## 2. 环境与自检命令（提 PR 前必须全部通过）

需要 Godot 4.4.1 标准版（非 .NET）。以下命令都读取环境变量 `GODOT`（Godot 可执行文件路径）。

```bash
GODOT=/path/to/godot tools/check.sh          # 语法检查，必须输出 check: OK
GODOT=/path/to/godot tools/sim.sh            # 无界面模拟一个游戏日，不得出现 SCRIPT ERROR
GODOT=/path/to/godot tools/shot.sh out.png --skip-setup --shot-hour=21   # 截图（需要 xvfb）
```

- 改了界面：PR 里**必须附截图**（`tools/shot.sh`，可配合 `--test-busy`、`--test-call`、`--test-suspect`、`--layers=heat,reach` 等参数，见 `scripts/game/game.gd` 的 `_dev_hooks`）。
- 改了数值或玩法：PR 里贴 `tools/sim.sh` 修改前后的输出对比。
- 在编辑器里运行：打开 `project.godot`，F5。

---

## 3. 代码结构

| 路径 | 职责 |
|---|---|
| `scripts/core/data.gd`（autoload `Data`） | 全部数值表：警种 `UNIT_TYPES`、专长 `SKILLS`、警情 `INCIDENTS`、接警剧本 `CALLS` |
| `scripts/core/game_state.gd`（autoload `GameState`） | 时间、经费、安全感、舆情、统计；电台消息 `post()`、值班长提示 `advisor` 信号 |
| `scripts/game/game.gd` | 主循环：班前部署 → 值班；警情生成与处置、派警、选择与指令、教学 |
| `scripts/game/ops.gd` | 中国警务玩法：治安热力、见警率、1-3-5 快反圈、天网、卡点、嫌疑人追逃 |
| `scripts/game/incident.gd` / `suspect.gd` | 警情、逃逸嫌疑人数据 |
| `scripts/units/police_unit.gd` | 警力单位：状态机、寻路、巡区、疲劳 |
| `scripts/city/*` | 地图数据、路网、地块、地面贴图绘制 |
| `scripts/ui/hud.gd` | 界面总装：顶栏、左侧警情栏、右侧面板、底部按钮、值班长 |
| `scripts/ui/marker_layer.gd` | 地图上的所有标注（单位卡片、警情六边形、图层） |
| `scripts/ui/ui_kit.gd` | 配色、字体、面板与按钮样式、绘图工具——**新界面一律用这里的函数** |
| `scripts/dev/dev_tools.gd`（autoload `DevTools`） | 命令行参数、截图、模拟输出 |
| `docs/` | GitHub Pages 发布目录（网页版）+ `GDD.md` 设计文档 |

---

## 4. 必须遵守的规则（违反会被直接要求返工）

### 4.1 GDScript
- **类型必须明确**：从字典、数组或未声明类型的变量取值时，写 `var x: float = d.value`，不要写 `var x := d.value`（会报 "Cannot infer the type"）。
- 缩进用 **Tab**。命名 snake_case，类名 PascalCase。注释用中文，密度和周围代码一致。
- 不要引入新的 autoload、插件或第三方库。
- 数值写进 `data.gd` 或文件顶部常量，不要把魔法数字散落在逻辑里。

### 4.2 字体与图标（最容易踩的坑）
- 中文字体 `assets/fonts/NotoSansSC-*.ttf` 和图标字体 `MaterialSymbolsRounded-Subset.ttf` 都是**子集**。
- 新增了字库里没有的汉字或符号，网页版会显示方框；新增图标不在子集里会显示空白。
- 需要新字 / 新图标时：**不要自己重新生成字体**，在 PR 正文里列出新增的字符和图标名，由 Claude 统一处理。图标名须来自 Material Symbols，并在 `scripts/ui/icons.gd` 中登记。

### 4.3 不要碰的东西
- `docs/index.*`（网页版构建产物）：只由 Claude 用 `tools/export_web.sh` 更新，PR 里不要包含。
- `assets/fonts/`、`export_presets.cfg`、`project.godot`（除非 Issue 明确要求）。
- `.godot/` 目录与 `*.import` 文件的无关变动：提交前用 `git checkout` 还原。

### 4.4 美术与交互规范
- 风格：参考《112 Operator》——深蓝单色战术地图、发光线条、六边形图标、胶囊按钮、少文字。
- **不要做"网页式"的大段文字说明界面**。能用图标、颜色、进度表达的就不要用文字。
- 颜色只用 `UIKit` 里的常量（`ACCENT`、`CYAN`、`RED`、`GREEN`、`AMBER`、`TEXT*`）和 `Data.SKILLS[*].color`。
- 面板用 `TechPanel`，按钮用 `UIKit.button / accent_button / icon_button`，字用 `UIKit.label`。
- 地图保持干净：不加树木、装饰物。

### 4.5 玩法原则
- 玩家要"尽在掌握"：重要决策由玩家做，自动化只接管一般事务。
- 警种要有区别：靠 `SKILLS` 专长硬分工，不要让某个警种"什么都能干"。
- 贴合中国警务：110 接警、派出所、巡特警、交警、特警的职责分工。

---

## 5. 常见任务的切入点

- 加警情类型：`data.gd` 的 `INCIDENTS`（需要 `req` 专长）+ `hour_weight`；可选加接警剧本到 `CALLS`。
- 加警种：`UNIT_TYPES` + `SKILLS` + `FACILITY_TYPES`；地图卡片颜色在 `marker_layer.gd` 的 `UNIT_FILL`，车辆剪影在 `vehicle_art.gd`。
- 加界面面板：参考 `scripts/ui/setup_panel.gd`（继承 `TechPanel`、在 `_process` 里定位与刷新）。
- 加开发测试参数：`game.gd` 的 `_dev_hooks()`。

---

## 6. PR 正文模板

```markdown
关联 Issue：#
编码者：<名字>

## 做了什么
- 

## 自检
- [ ] tools/check.sh 输出 check: OK
- [ ] tools/sim.sh 无 SCRIPT ERROR（改数值时附前后对比）
- [ ] 界面改动已附截图
- [ ] 没有包含 docs/index.*、字体、无关 .import 变动

## 新增的汉字 / 图标（没有就写"无"）


## 顺带发现（未修改）

```
