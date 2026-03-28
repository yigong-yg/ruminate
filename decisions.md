# Feature 1 & 2 执行计划

> **作者**: Claude Code (审阅研究报告后)
> **日期**: 2026-03-27
> **范围**: Feature 1 (Discord 历史记忆索引) + Feature 2 (主动感知)
> **约束**: agent-integrations 仓库不做改动；所有变更在 `~/.config/alma/` 内

---

## 架构总览

### 系统现状确认（与报告校验后的修正）

| 项 | 报告声称 | 实际确认 |
|----|---------|---------|
| 日志路径 | `~/.config/alma/groups/*.log` | ✅ 确认，9个文件 ~112KB |
| memory/ 目录 | 存在但空 | ❌ **目录不存在**，需要创建 |
| cron/jobs.json | 空数组 | ✅ 确认 `[]` |
| HEARTBEAT.md | 不存在 | ✅ 确认不存在 |
| discord-state.json | 有 groupHistory | ✅ 确认，保留最近 ~18 条消息 |
| 向量记忆 | 可用但空 | ✅ sqlite-vec 数据库存在但无自定义记忆 |
| self-reflection skill | 已有 | 是 bundled skill，无法直接读取源码 |
| 自定义 skills | 2 个 | ✅ voice-relay + job-apply |

### 关键架构约束

1. **Alma 是闭源 Electron 应用** (v0.0.727) — 我们无法修改核心代码
2. **扩展方式只有两种**：
   - **Custom Skills** (`~/.config/alma/skills/{name}/SKILL.md`) — 给 LLM 提供执行指令
   - **Alma REST API** (`localhost:23001`) — 读写配置
3. **Cron/Heartbeat 是内置功能** — 通过 Alma 自己的 agent 上下文执行，不是系统 crontab
4. **"alma" 命令是 Alma 内部 skill 命令** — 在 Alma 的 chat context 中执行，不是 bash CLI

### 目标架构

```
~/.config/alma/
├── HEARTBEAT.md                    ← [新建] 心跳检查清单
├── MEMORY.md                       ← [不动] 角色设定
├── SOUL.md                         ← [不动] 系统 prompt
├── memory/
│   └── digest/
│       ├── .watermark              ← [新建] 增量处理水位标记
│       ├── 2026-03-23.md           ← [由 cron 生成] 每日摘要
│       ├── 2026-03-24.md
│       └── ...
├── cron/
│   └── jobs.json                   ← [修改] 添加定时任务
├── skills/
│   └── digest/
│       └── SKILL.md                ← [新建] 每日摘要生成技能
├── groups/
│   └── *.log                       ← [不动] 原始日志（只读）
└── people/
    └── karla.md                    ← [不动] 人物档案
```

---

## Phase 0: 基础设施准备

### Step 0.1: 创建目录结构

```bash
mkdir -p ~/.config/alma/memory/digest
mkdir -p ~/.config/alma/skills/digest
```

### Step 0.2: 确认 Alma API 可达

```bash
curl -s http://localhost:23001/api/health | jq
```

如果 Alma 未运行，需要先启动 Alma 桌面应用。

### Step 0.3: 获取并记录当前 memory 设置

```bash
curl -s http://localhost:23001/api/settings | jq '.memory'
```

记录当前值，后面需要调优。

---

## Phase 1: Feature 1 — Discord 历史记忆索引

### 核心设计

Feature 1 的实现分为两部分：
- **A. Digest Skill** — 一个 custom skill，教 Alma 如何读取日志并生成摘要
- **B. Cron Job** — 定时触发 digest skill

为什么是 Skill 而不是外部脚本？因为：
1. 摘要生成需要 LLM 推理（Alma 自己就是 LLM）
2. `alma memory add` 只在 Alma agent context 内可用
3. 保持所有逻辑在 Alma 生态内，不引入外部依赖

### Step 1.1: 创建 Digest Skill

**文件**: `~/.config/alma/skills/digest/SKILL.md`

```markdown
# 群聊日志摘要生成器

## 概述
读取 Discord 群聊日志，生成结构化的每日摘要，并存入向量记忆系统。

## 使用场景
- 被 cron job 定时调用（每日 UTC 06:00 / MDT 午夜）
- 手动触发：用户要求"消化/digest今天的群聊"

## 执行步骤

### 1. 确定处理范围

读取水位标记文件：
```bash
cat ~/.config/alma/memory/digest/.watermark
```

如果文件不存在，处理所有历史日志。
如果存在，只处理 `lastProcessed` 之后的日期。

### 2. 读取日志文件

读取 `~/.config/alma/groups/` 下所有匹配日期的 `.log` 文件。

日志格式：
```
[HH:MM:SS] [msg:messageId] [username]: 消息内容
[HH:MM:SS] [Alma (BOT)]: 回复内容
```

### 3. 生成结构化摘要

对每天的日志，生成以下格式的摘要：

```markdown
# {日期} 群聊摘要

## 主要话题
- [话题1]: 一句话描述
- [话题2]: 一句话描述

## 关键事件/决策
- 具体事件或决定

## 人物动态
- @用户名: 当天的关键行为/状态

## 未完成事项
- 如果有讨论到但未解决的问题

## 情绪/氛围
- 群聊整体氛围的一句话描述
```

### 4. 写入摘要文件

```bash
# 将摘要写入文件
# 路径: ~/.config/alma/memory/digest/{YYYY-MM-DD}.md
```

### 5. 存入向量记忆

将摘要中的每个主要话题点作为单独的记忆条目存入向量记忆：
```
alma memory add "2026-03-26: LinkedIn投递代理运行27次，100%成功率"
alma memory add "2026-03-26: Chrome语言设置调试，最终在chrome://settings/languages删除中文才生效"
```

每个记忆条目以日期为前缀，保持可追溯性。

### 6. 更新人物档案（如有新信息）

如果日志中发现了关于用户的新信息（新爱好、新项目、状态变化），用 `alma people append` 更新档案。

### 7. 更新水位标记

```json
{"lastProcessed": "2026-03-27T06:00:00Z", "lastDate": "2026-03-27"}
```

写入 `~/.config/alma/memory/digest/.watermark`

## 注意事项
- 不要在摘要中包含 PII（遵循 SOUL.md 规则）
- 每个向量记忆条目控制在 200 字以内
- 每天生成 5-15 个记忆条目，不要过多
- 如果某天日志为空或极少（<5条消息），跳过该天
```

### Step 1.2: Cron Job → 合并到 Heartbeat

~~原计划用 cron job 每日触发 digest，但有三个问题：~~
1. ~~Windows 无 crontab~~
2. ~~Alma 不是 24 小时在线，cron 可能错过触发窗口~~
3. ~~Heartbeat 已经是周期性执行，没必要再加一层~~

**最终方案**: Digest 检查已合并到 HEARTBEAT.md 的第 1 步。每次心跳都会检查水位标记，发现有未消化的历史日期就自动补齐。无论 Alma 离线多久，重新上线后第一次心跳就会把缺失的天数全部补上。

不需要单独配置 cron job。

### Step 1.3: 首次全量回填

启用 heartbeat 后，第一次心跳会发现 watermark 的 `lastDate` 为 null，自动触发全量回填（03-23 到昨天）。

如果想手动触发，也可以在 Alma Discord 中：
```
@Alma 执行 digest skill，处理所有历史日志（03-23 到昨天），每天生成一份摘要。
```

### Step 1.4: 调优 Memory 设置

通过 API 调整记忆系统参数：

```bash
# 1. 获取当前设置
current=$(curl -s http://localhost:23001/api/settings)

# 2. 修改 memory 相关设置
updated=$(echo "$current" | jq '
  .memory.enabled = true |
  .memory.autoSummarize = true |
  .memory.autoRetrieve = true |
  .memory.maxRetrievedMemories = 10 |
  .memory.similarityThreshold = 0.5
')

# 3. 写回
curl -s -X PUT http://localhost:23001/api/settings \
  -H "Content-Type: application/json" \
  -d "$updated" | jq '.memory'
```

关键参数说明：

| 参数 | 推荐值 | 理由 |
|------|--------|------|
| `autoRetrieve` | `true` | 用户对话时自动从向量记忆检索相关内容 |
| `maxRetrievedMemories` | `10` | 每次检索返回 10 条，平衡上下文占用和覆盖度 |
| `similarityThreshold` | `0.5` | 阈值不要太高，群聊话题跨度大，需要宽松匹配 |
| `autoSummarize` | `true` | 长对话自动摘要 |

### Step 1.5: 验证

1. 检查 `~/.config/alma/memory/digest/` 下是否生成了 `.md` 文件
2. 用 `alma memory search "LinkedIn投递"` 验证向量记忆是否可检索
3. 在 Discord 中测试："之前那个Chrome语言问题怎么解决的？" — 看 Alma 能否利用记忆回答

---

## Phase 2: Feature 2 — 主动感知

### 核心设计

主动感知分 3 层实施，按风险递增：

| 层 | 名称 | 实施难度 | 误判风险 |
|----|------|---------|---------|
| L1 | 参数调优 | 低 | 无 |
| L2 | Heartbeat 感知 | 中 | 低 |
| L3 | 主动参与 | 高 | 高 |

**建议**: 先实施 L1 + L2，观察一周效果后再考虑 L3。

### Step 2.1: (L1) 群聊参与度调优

当前 Alma 已有 `randomBoostRate`、`reactionRate` 等参数。需要确认当前值并调整。

在 Alma Discord 中执行：
```
@Alma 查看当前所有群的 participation 设置
alma group participation show
```

**建议调整值**：

| 参数 | 当前(推测) | 建议值 | 理由 |
|------|-----------|--------|------|
| `randomBoostRate` | 0.2 | 0.05 | 降低无@时的随机回复概率，避免打扰 |
| `cooldownMinutes` | 30 | 60 | 延长冷却期，降低频率 |
| `quietMinutes` | 5 | 10 | 群更安静后才巡逻 |
| `reactionRate` | 0.6 | 0.15 | 大幅降低 emoji 反应频率，减少"bot 感" |

执行命令（在 Alma Discord 中）：
```
@Alma 调整主频道参与度：
alma group participation set randomBoostRate 0.05
alma group participation set cooldownMinutes 60
alma group participation set quietMinutes 10
alma group participation set reactionRate 0.15
```

### Step 2.2: (L2) 创建 HEARTBEAT.md

**文件**: `~/.config/alma/HEARTBEAT.md`

```markdown
# Heartbeat 检查清单

## 群聊感知（每次心跳执行）

1. 读取所有活跃群聊最近一个心跳周期内的日志
   - 日志路径: ~/.config/alma/groups/discord_*_{今日日期}.log
   - 只读取上次心跳之后的新内容

2. 快速评估（不需要深度分析）：
   - 群里在聊什么话题？
   - 有没有值得记住的新信息？
   - 群里气氛如何？

3. 如果发现有价值的信息：
   - 用 alma memory add 存入向量记忆
   - 如果是关于某个人的新信息，考虑更新 people profile

4. 如果群聊安静（无新消息），直接返回 HEARTBEAT_OK

## 原则
- 这是观察和学习的时间，不是表演时间
- 不要主动发消息到任何群
- 只做信息收集和记忆更新
- 如果没有新内容，直接 HEARTBEAT_OK
- 每次心跳的记忆新增不超过 3 条
```

### Step 2.3: (L2) 启用 Heartbeat

在 Alma Discord 中执行：
```
@Alma 启用心跳系统：
alma heartbeat enable
alma heartbeat interval 30
alma heartbeat patrol enable
```

参数说明：
- `interval 30` — 每 30 分钟检查一次
- `patrol enable` — 启用群巡逻（读取群聊更新）

### Step 2.4: (L2) 为每个群设置感知规则

```
@Alma 为主频道添加规则：
alma group rules add 1485752475616018514 "心跳巡逻时只观察、不发言。将有价值的信息存入记忆，但不要回复。"
alma group rules add 1485756255317266702 "心跳巡逻时只观察、不发言。"
alma group rules add 1485799276671139941 "心跳巡逻时只观察、不发言。"
```

### Step 2.5: (L2) 验证 Heartbeat 运行

等待 30 分钟后检查：
1. Alma 是否有执行心跳（查看日志或 cron/runs.json）
2. 向量记忆中是否有新增条目（`alma memory search` 测试）
3. Alma 在被 @ 时是否展现出对近期话题的了解

### Step 2.6: (L3, 延期) 主动参与设计

> **注意**: 此步骤建议在 L1+L2 运行稳定一周后再实施。

L3 的核心是让 Heartbeat 不仅观察，还能在极高置信度时主动参与。需要在 HEARTBEAT.md 中添加判断逻辑，但当前阶段风险太高（服务器流量低，误判很明显），建议观望。

如果未来要实施，需要添加的判断条件：
- 群里有人问了一个问题，5分钟无人回答，且 Alma 知道答案
- 话题与 Alma 的核心能力强相关（技术/游戏/Alma 自身功能）
- 该群当天 Alma 主动发言次数 < 1
- 距离上次被 @ 回复已过 2 小时

---

## Phase 3: Feature 1 + 2 联动

### Step 3.1: Heartbeat 中调用 Digest 逻辑

一旦 Feature 1 的 digest skill 和 Feature 2 的 heartbeat 都运行稳定，可以在 HEARTBEAT.md 中添加：

```markdown
## 记忆维护（每日一次，配合 digest cron job）
- 检查今天的 digest 是否已生成
- 如果 cron job 失败或遗漏，手动触发 digest skill
```

### Step 3.2: 记忆检索增强

在 SOUL.md 中**不需要改动**——Alma 的 `autoRetrieve` 设置开启后，会自动在回复用户时检索向量记忆。关键是向量记忆中要有内容（由 Feature 1 的 digest 填充）。

---

## 执行顺序总结

| 序号 | 操作 | 类型 | 前置依赖 |
|------|------|------|---------|
| 0.1 | 创建 memory/digest 目录 | bash | 无 |
| 0.2 | 确认 Alma API 可达 | bash | Alma 运行中 |
| 0.3 | 获取当前 memory 设置 | API | 0.2 |
| 1.1 | 创建 digest skill | 写文件 | 0.1 |
| 1.2 | 配置 cron job | Alma 命令 | 1.1, Alma 运行中 |
| 1.3 | 首次全量回填 | Alma 命令 | 1.1, 1.2 |
| 1.4 | 调优 memory 设置 | API | 0.3 |
| 1.5 | 验证 F1 | 手动测试 | 1.3, 1.4 |
| 2.1 | 调优参与度参数 | Alma 命令 | Alma 运行中 |
| 2.2 | 创建 HEARTBEAT.md | 写文件 | 无 |
| 2.3 | 启用 heartbeat | Alma 命令 | 2.2, Alma 运行中 |
| 2.4 | 设置群规则 | Alma 命令 | 2.3 |
| 2.5 | 验证 F2 | 观察 | 2.3, 2.4 |
| 3.1 | F1+F2 联动 | 更新 HEARTBEAT.md | 1.5, 2.5 |

---

## 可以在此 Claude Code session 中直接执行的操作

以下操作不需要 Alma 运行，可以立即执行：

1. ✅ `mkdir -p ~/.config/alma/memory/digest` — 创建目录
2. ✅ 写入 `~/.config/alma/skills/digest/SKILL.md` — Digest 技能文件
3. ✅ 写入 `~/.config/alma/HEARTBEAT.md` — 心跳检查清单
4. ✅ 写入 `~/.config/alma/memory/digest/.watermark` — 初始水位标记

以下操作**需要 Alma 运行中**（通过 API 或 Discord 对话）：

5. ⏳ API: 调优 memory 设置
6. ⏳ Alma Discord: 创建 cron job
7. ⏳ Alma Discord: 首次全量 digest
8. ⏳ Alma Discord: 调优 participation 参数
9. ⏳ Alma Discord: 启用 heartbeat
10. ⏳ Alma Discord: 设置群规则

---

## 给 agent-integrations 的未来 Prompt

当需要在 agent-integrations 中实现 Ruminate 模块时，可以用以下 prompt：

```
在 agent-integrations 仓库中创建 shared/ruminate 模块。

设计要求：
1. 遵循现有 monorepo 结构（ESM, "type": "module", @agent-integrations/ scope）
2. 参考 shared/tts 的导出模式
3. 核心接口：
   - RuminateAdapter: { ingest(source) → TextChunk[] }
   - RuminateCore: { process(chunks) → QAPair[] }
4. 第一个 Adapter: discord-history
   - 解析 Alma 的日志格式: [HH:MM:SS] [msg:id] [user]: text
   - 输出 TextChunk[]
5. 不需要 HTTP API（先作为纯库使用）
6. 零外部依赖（与 shared/tts 一致）

日志格式示例：
[23:47:30] [msg:1485787112962789419] [karlamo]: 欢迎来到你的专属频道
[23:47:33] [Alma (BOT)]: 欢迎！我是喵菲斯，你的专属AI助手。
```

---

## 风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Cron job 格式不对导致不执行 | 中 | 高 | 通过 Alma 内部命令创建而非手写 JSON |
| Heartbeat 消耗过多 token | 低 | 中 | HEARTBEAT.md 中强调"无新消息直接 OK" |
| 向量记忆质量差导致检索无效 | 中 | 中 | 每个记忆条目加日期前缀，控制粒度 |
| Alma 更新后破坏 skill 格式 | 低 | 高 | 保持 SKILL.md 简洁，减少对内部 API 的假设 |
| Memory 设置 PUT 需要完整对象 | 确定 | 中 | 先 GET 再修改再 PUT |

---

## Token 成本预估

| 操作 | 频率 | 日均 Token |
|------|------|-----------|
| Digest cron (每日) | 1次/天 | ~3K |
| Heartbeat (每30min) | 最多48次/天 | ~10K (大部分直接 OK) |
| 自动记忆检索 | 每次对话 | ~500/次 |
| **日总计** | | **~15-20K** |
| **周限额占用** | | **<3%** |

当前周限额使用 22%（来自 discord-state.json），完全在预算内。
