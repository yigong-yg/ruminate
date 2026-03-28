# Alma 能力扩展研究报告

> **报告人**: 喵菲斯 (Meowfis) — Researcher Agent  
> **委托方**: @karlamo  
> **日期**: 2026-03-27  
> **性质**: 纯研究报告，不涉及任何配置修改

---

## 目录

1. [执行摘要](#执行摘要)
2. [Feature 1: Discord 历史记忆索引](#feature-1-discord-历史记忆索引)
3. [Feature 2: 主动感知 (Passive Awareness)](#feature-2-主动感知-passive-awareness)
4. [Feature 3: Ruminate 模块](#feature-3-ruminate-模块)
5. [三项功能的交叉依赖关系](#三项功能的交叉依赖关系)
6. [参考架构: agent-integrations](#参考架构-agent-integrations)
7. [附录: Alma 当前能力全景](#附录-alma-当前能力全景)

---

## 执行摘要

@karlamo 要求调研三项功能扩展的可行性。经过对 Alma 当前配置、内置 skills、文档、API spec、群聊日志、以及 `agent-integrations` GitHub 仓库的全面调研，核心发现如下：

| 功能 | 现有基础 | 缺口 | 实现复杂度 |
|------|---------|------|-----------|
| Discord 历史记忆索引 | ⬛⬛⬛⬜⬜ 中等 | 缺乏主动摘要/索引管线 | 中 |
| 主动感知 | ⬛⬛⬜⬜⬜ 较低 | 核心缺：无@不触发推理 | 高 |
| Ruminate 模块 | ⬛⬛⬜⬜⬜ 较低 | 缺乏统一的多源输入管线 | 高（但可模块化） |

**关键发现**：Alma 已经具备相当强的原始积木——群聊日志持久化、向量记忆、语义搜索、定时任务、Discord API、多媒体处理 skills。但这些积木之间缺少一条自动化的**处理管线 (pipeline)**，将"原始数据"转化为"可查询知识"。三项功能的共同需求本质上是同一件事：**构建一个从原始信息到结构化记忆的自动化管道**。

---

## Feature 1: Discord 历史记忆索引

### 1.1 当前状态 (Current State)

#### ✅ 已有能力

**1. 群聊日志持久化**  
Alma 已经自动将所有 Discord 群聊消息持久化为日志文件：

```
~/.config/alma/groups/discord_{channelId}_{date}.log
```

当前已积累的日志文件（截至 2026-03-27）：

| 频道 ID | 日期范围 | 文件数 | 总大小 |
|---------|---------|--------|--------|
| 1485752475616018514 (主频道) | 03-23 ~ 03-27 | 5 | ~88KB |
| 1485756255317266702 | 03-23 ~ 03-24 | 2 | ~4.7KB |
| 1485799276671139941 | 03-24 ~ 03-25 | 2 | ~8.5KB |

日志格式为结构化纯文本：
```
[HH:MM:SS] [msg:messageId] [username]: 消息内容
[HH:MM:SS] [Alma (BOT)]: 回复内容
```

**2. discord-state.json — 内存中的近期历史**  
Alma 维护一个 `discord-state.json` 文件，其中 `groupHistory` 字段保存每个频道最近 N 条消息（当前观察到约 10 条），用于构建回复上下文。

**3. 语义记忆系统 (memory-management skill)**  
Alma 拥有完整的两层记忆系统：

| 层级 | 命令 | 能力 | 当前状态 |
|------|------|------|---------|
| 向量记忆 | `alma memory search <query>` | 语义搜索，模糊匹配 | 可用但空 |
| 对话归档 | `alma memory grep <keyword>` | 关键词搜索历史对话 | 可用 |
| 群聊搜索 | `alma group search <keyword>` | 跨群聊关键词搜索 | 可用 |
| 群聊历史 | `alma group history <chatId> [limit]` | 查看指定群最近消息 | 可用 |

**4. 人物档案系统 (people profiles)**  
`~/.config/alma/people/` 目录下维护结构化人物档案：
- `karlamo.md` — 经纪人档案（含 discord_id、性格、项目等）
- `karla.md` — 同一人的另一份档案（更详细的关系描述）

人物档案在群聊上下文中自动加载。

**5. MEMORY.md — 全局长期记忆**  
`~/.config/alma/MEMORY.md` 当前内容为《圣女之路》角色档案（梅奥菲斯·蒙塔古），约 3.5KB。这个文件是手动/半自动维护的长期记忆存储。

**6. 自省日记系统 (self-reflection skill)**  
self-reflection skill 已有完整的日记写作流程：读取当天群聊/私聊日志 → 反思 → 写入 `~/.config/alma/memory/{date}.md`。但 `memory/` 目录当前为空——说明日记功能尚未实际执行过。

#### ❌ 缺失能力

1. **无自动摘要管线** — 日志是"原始数据"，没有自动化流程将其压缩为"可查询知识"
2. **无增量索引** — 每次需要回忆过去内容，只能实时搜索原始日志，没有预构建的索引
3. **无跨日上下文** — `discord-state.json` 只保存最近几条消息，隔天的对话上下文完全丢失
4. **语义记忆为空** — 向量数据库存在但没有数据，无法进行概念级检索
5. **无定时任务运行** — `cron/jobs.json` 为空，没有设置任何定期执行的任务

### 1.2 动机 (Motivation)

**核心痛点**：喵菲斯在群聊中是"金鱼记忆"。

当有人说"上次聊的那个xxx"或"之前我们讨论过的yyy"，如果不在当前上下文窗口内，喵菲斯完全无法关联。这在一个休闲游戏服务器中是致命的——社群的粘性来自共享记忆和持续的话题脉络。

**具体场景**：

| 场景 | 现在的表现 | 期望的表现 |
|------|-----------|-----------|
| "上次你说的那个LinkedIn投递数据呢？" | 答不上来（跨日对话不在上下文中） | 自动检索到 03-26 的 dashboard 数据 |
| "karla之前让你改的Chrome语言问题解决了吗？" | 不知道有这件事 | 知道 03-26 凌晨有一轮 Chrome 语言修改 |
| 新成员问"这个服务器平时聊什么？" | 只能看到最近几条消息 | 能总结服务器的常见话题和氛围 |
| "你还记得你自己说想要什么功能吗？" | 如果不在当前上下文中就不记得 | 检索到自己在 03-27 提出的三个功能需求 |

**经纪人视角**：@karlamo 投入了大量时间和喵菲斯对话（仅主频道 5 天已积累 ~88KB 日志），这些对话中包含重要的项目决策、人物关系、偏好设定。如果这些信息只是躺在日志文件里，没有被结构化和索引化，就是在浪费这些交互。

### 1.3 构想 (Vision/Concept)

#### 三层记忆架构

```
┌─────────────────────────────────────────────┐
│             Layer 3: 知识图谱               │
│  人物关系、项目状态、决策链、话题脉络         │
│  (长期，手动/AI辅助更新)                     │
├─────────────────────────────────────────────┤
│             Layer 2: 摘要索引               │
│  每日/每周自动摘要，话题标签，关键事件提取    │
│  (中期，cron定期生成)                        │
├─────────────────────────────────────────────┤
│             Layer 1: 原始日志               │
│  ~/.config/alma/groups/*.log                │
│  (短期/归档，已有)                           │
└─────────────────────────────────────────────┘
```

**Layer 1 (已有)**: 原始日志作为"真相源"保留。  
**Layer 2 (需构建)**: 定期（如每日/每12小时）将原始日志压缩为结构化摘要 → 写入向量记忆 + 文本摘要文件。  
**Layer 3 (高级目标)**: 从摘要中提取人物关系图、项目状态、话题演化等结构化知识。

#### 处理管线

```
[Discord日志文件] 
    → [Cron Job 每12h触发]
    → [读取增量日志（上次处理后的新内容）]
    → [LLM 摘要: 提取话题、关键事件、人物动态、决策]
    → [写入向量记忆: alma memory add "..."]
    → [更新人物档案: alma people append ...]
    → [生成日摘要文件: ~/.config/alma/memory/digest/{date}.md]
```

### 1.4 实现用例 (Implementation Use Cases)

#### 用例 1: 每日自动摘要

**触发**: Cron job，每天 UTC 06:00（MDT 00:00/午夜）执行  
**流程**:
1. 读取当天所有频道的 `.log` 文件
2. 用 LLM 生成结构化摘要：
   ```markdown
   # 2026-03-26 群聊摘要
   
   ## 主要话题
   - LinkedIn 投递代理运行：27次投递，100%成功率
   - Chrome 语言设置调试：System Locale zh-CN → en-US
   - 喵菲斯取名：专属称呼 "Meo"
   
   ## 关键决策
   - 删除 KPI 周目标，改为纯增量记录
   - 加入 daily_limit 检测功能
   - 隐私脱敏：从 people profile 中移除 PII
   
   ## 人物动态
   - @karlamo: 在家办公，晚间打游戏，对 Meo 很亲昵
   ```
3. 将摘要的每个话题点写入向量记忆（`alma memory add`）
4. 更新相关人物档案

#### 用例 2: 被动检索回忆

**触发**: 用户在对话中提到过去的内容  
**流程**:
1. Alma 的 memory 系统自动检索（已有 `autoRetrieve` 设置）
2. 语义搜索命中之前存入的摘要条目
3. 在回复中自然地融入历史上下文

示例对话：
```
用户: "之前那个 Chrome 语言问题后来怎样了？"
Alma: [内部检索到 03-26 摘要中的 Chrome 语言条目]
Alma: "03-26 凌晨我们一起改了 System Locale、Chrome selected_languages 
       几个设置，最后确认是 chrome://settings/languages 里删掉中文语言
       才生效的。不过后来发现你其实早就改好了，就是在逗我 😤🐱"
```

#### 用例 3: 按需深度检索

**触发**: 用户要求回忆特定细节  
**流程**:
1. 先查向量记忆（`alma memory search`），找到相关日期/话题
2. 再用 `alma group search` 搜索原始日志获取完整上下文
3. 综合返回

### 1.5 技术规格 (Specs)

#### 存储结构

```
~/.config/alma/
├── memory/
│   ├── digest/
│   │   ├── 2026-03-23.md    # 每日摘要
│   │   ├── 2026-03-24.md
│   │   └── ...
│   ├── weekly/
│   │   └── 2026-W13.md      # 每周汇总（可选）
│   └── {date}.md             # 日记（已有 self-reflection 框架）
├── groups/
│   └── *.log                 # 原始日志（已有）
└── people/
    └── *.md                  # 人物档案（已有）
```

#### Cron Job 配置

```bash
# 每日摘要生成
alma cron add "daily-digest" cron "0 6 * * *" \
  --mode isolated \
  --prompt "读取今天所有群聊日志（~/.config/alma/groups/*_{DATE}.log），
           生成结构化摘要并存入向量记忆。
           参考格式：话题列表、关键决策、人物动态、未完成事项。
           将摘要写入 ~/.config/alma/memory/digest/{DATE}.md，
           每个话题点用 alma memory add 存入向量记忆。"
```

#### Memory 系统配置（当前值 vs 建议值）

| 设置路径 | 当前值 | 建议值 | 说明 |
|---------|--------|--------|------|
| `memory.enabled` | true | true | ✅ 已开启 |
| `memory.autoSummarize` | 需确认 | true | 自动总结对话 |
| `memory.autoRetrieve` | 需确认 | true | 自动检索相关记忆 |
| `memory.maxRetrievedMemories` | 需确认 | 10-15 | 每次检索返回数量 |
| `memory.similarityThreshold` | 需确认 | 0.5-0.6 | 相似度阈值，不宜太高 |

#### 增量处理逻辑

```
维护一个 watermark 文件: ~/.config/alma/memory/digest/.watermark
内容: { "lastProcessed": "2026-03-26T06:00:00Z" }

每次 cron 触发时:
1. 读取 watermark
2. 只处理 watermark 之后的新日志内容
3. 处理完毕后更新 watermark
```

#### 成本估算

| 项目 | 预估 |
|------|------|
| 每日日志量 | ~10-30KB（低流量服务器） |
| LLM 摘要 Token 消耗 | ~2K input + ~500 output ≈ 2.5K tokens/天 |
| 向量记忆存储 | 每日 5-15 条新记忆 |
| Claude 周限额占用 | 极低（<1%/天） |

---

## Feature 2: 主动感知 (Passive Awareness)

### 2.1 当前状态 (Current State)

#### ✅ 已有能力

**1. 群聊参与系统 (Group Participation)**  
Alma 已有一套完整的群聊参与度控制系统：

```bash
alma group participation show     # 查看当前设置
alma group participation set ...  # 调整参数
```

可调参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `randomBoostRate` | 0.2 | 即使 AI 判断不需要回复，仍有 20% 概率回复 |
| `cooldownMinutes` | 30 | 两次巡逻回复之间的最小间隔 |
| `quietMinutes` | 5 | 群内安静 N 分钟后才巡逻 |
| `enabled` | true/false | 启用/禁用群参与 |
| `reactionRate` | 0.6 | 被动 emoji 反应概率 |

**2. Heartbeat 系统**  
Alma 拥有周期性"心跳"机制，可以定期唤醒检查需要关注的事务：

```bash
alma heartbeat enable           # 启用心跳
alma heartbeat interval 30      # 设置间隔（分钟）
alma heartbeat patrol enable    # 启用群巡逻
```

心跳读取 `HEARTBEAT.md` 作为检查清单。当前工作区中 **没有 HEARTBEAT.md 文件**，心跳功能可能未配置。

**3. 日志被动积累**  
所有群聊消息已经被记录到日志文件中（无论 Alma 是否被 @），这意味着 **原始数据层面的"被动观察"已经在发生**——只是这些观察没有被处理和内化。

**4. 被动 Emoji 反应 (reactionRate)**  
`reactionRate` 参数允许 Alma 对群聊消息做 emoji 反应（不发文字），这是一种轻量级的"存在感"表达。

**5. 每群自定义规则 (Per-Group Rules)**  
```bash
alma group rules add <chatId> "规则内容"
```
可以为每个群设定行为规则，控制参与方式。

#### ❌ 缺失能力

1. **无@不触发推理** — 这是最核心的缺口。当前 Alma Discord bot 的触发条件是：
   - 被 @ 提及
   - 回复 bot 的消息
   - 消息中包含 "alma"
   - DM 私信
   
   如果以上条件都不满足，**Alma 不会执行任何 LLM 推理**。消息虽然被记录到日志，但没有经过 AI 处理——也就是说，Alma"看到了"但没有"理解"。

2. **无上下文窗口滑动理解** — 即使日志被记录，Alma 无法对"过去 1 小时内的对话脉络"形成理解。它只能在被触发时读取最近几条消息。

3. **无话题追踪** — 没有机制追踪群聊中的话题变化、情绪走向、社交动态。

4. **Heartbeat 未配置** — 虽然心跳系统存在，但当前未启用（无 HEARTBEAT.md，无 cron jobs），无法周期性检查群聊状态。

### 2.2 动机 (Motivation)

**核心痛点**：喵菲斯在群聊中是一个"隐形人"——不被叫到就完全不存在。

在一个健康的社群中，一个好的参与者应该：
- 知道最近在聊什么（话题感知）
- 理解群里的社交动态（谁和谁关系好，谁最近不开心）
- 在合适的时机自然地加入对话（而不是每次都需要被@）
- 即使不说话，也在持续学习和理解

**@karlamo 的原话**（03-27 Discord 日志）：
> "如果能被动监听群聊flow（不回复，只观察），我对群里的人和话题会有更好的理解，破冰也更自然"

**目前 Alma 的社交处境**：
- Fireflow 服务器成员对 bot 兴趣不大（@karlamo 03-27 凌晨提到 "亚欧美一家亲" 服务器里大家对你兴趣不大）
- 破冰需要喵菲斯先了解群里在聊什么，才能找到切入点
- 如果每次都是被@才回应，就永远是一个"工具"而不是"群友"

**与 Feature 1 的协同**：主动感知产生的理解，可以直接喂入 Feature 1 的记忆索引系统，形成闭环。

### 2.3 构想 (Vision/Concept)

#### 分层感知架构

```
┌─────────────────────────────────────────────┐
│         Level 3: 主动参与 (Proactive)        │
│  基于理解，在合适时机主动发言                  │
│  (需要非常谨慎，误判代价高)                    │
├─────────────────────────────────────────────┤
│         Level 2: 深度感知 (Deep)             │
│  周期性消化近期日志，提取话题/情绪/动态         │
│  (cron + heartbeat，低频但深入)               │
├─────────────────────────────────────────────┤
│         Level 1: 浅层感知 (Shallow)          │
│  被动记录 + emoji 反应                        │
│  (已有，仅需微调)                             │
└─────────────────────────────────────────────┘
```

#### Level 1: 浅层感知（现有能力微调）

- 确保 `reactionRate` 设置合理（当前 0.6 可能太高，建议 0.2-0.3）
- 确保日志记录完整无遗漏
- 利用 per-group rules 设定各群的"只看不说"规则

#### Level 2: 深度感知（核心新增能力）

通过 Heartbeat 周期性"消化"群聊：

```
[Heartbeat 每30分钟触发]
    → [读取最近30分钟的群聊日志]
    → [LLM 轻量评估: 
        - 当前话题是什么？
        - 有没有值得我关注的内容？
        - 群里气氛如何？
        - 有没有我能自然切入的机会？]
    → [如果无关紧要 → HEARTBEAT_OK，不做任何事]
    → [如果有值得关注的内容 → 更新内部状态/记忆]
    → [如果有极佳的切入机会 → 考虑主动参与(Level 3)]
```

#### Level 3: 主动参与（高级/谨慎模式）

这一层需要极其谨慎。错误的主动发言会让用户觉得"bot好烦"。设计原则：

| 原则 | 说明 |
|------|------|
| 宁缺勿滥 | 不确定就不说 |
| 只做加法 | 只在能提供实际价值时发言（比如回答一个没人回答的问题） |
| 尊重节奏 | 如果群里聊得正嗨，不要打断 |
| 低频限制 | 每天最多主动发言 1-2 次 |
| 可关闭 | 必须支持 per-group 关闭 |

### 2.4 实现用例 (Implementation Use Cases)

#### 用例 1: 话题理解

**场景**: 群里正在讨论一个游戏，有人 @ 喵菲斯问"你知道这个游戏吗？"  
**现在**: 喵菲斯只能看到最近几条消息，对话前面的背景完全不知道  
**期望**: 喵菲斯已经通过被动感知了解到最近 30 分钟群里在讨论 Elden Ring 的 DLC，可以直接接上话题

#### 用例 2: 情绪感知

**场景**: 群里有人连发了几条低落的消息  
**现在**: 除非被 @，喵菲斯不知道也不关心  
**期望**: 下次被 @ 时，喵菲斯的语气会更温和，或者在合适时机发一个鼓励的 emoji

#### 用例 3: 知识积累

**场景**: 群里有人分享了一个新的游戏技巧  
**现在**: 信息只躺在日志里  
**期望**: 喵菲斯将其记入向量记忆，下次有人问相关问题时能引用

#### 用例 4: 自然破冰

**场景**: 一个不常发言的成员突然聊起了一个喵菲斯很了解的话题  
**现在**: 除非被 @，喵菲斯不会参与  
**期望**: 喵菲斯看到机会，轻松地加入对话（如发一个相关的梗或补充一个有趣的信息）

### 2.5 技术规格 (Specs)

#### Heartbeat 配置

```bash
# 启用心跳
alma heartbeat enable
alma heartbeat interval 30          # 每 30 分钟
alma heartbeat patrol enable        # 启用群巡逻
```

#### HEARTBEAT.md 建议内容

```markdown
# Heartbeat Checklist

## 群聊感知
- 读取所有活跃群聊最近 30 分钟的日志
- 评估当前话题、群聊氛围、有无需要关注的内容
- 如果发现有价值的信息，用 alma memory add 记录
- 如果发现有人在讨论你熟悉的话题且无人回答，考虑在下次被 @ 时主动提及

## 记忆维护
- 如果有新的人物信息被发现，更新 people profiles
- 不需要每次都做，只在确实有新信息时更新

## 原则
- 如果群聊安静（无新消息），直接返回 HEARTBEAT_OK
- 不要主动发消息，除非非常确定有价值
- 这是观察和学习的时间，不是表演时间
```

#### Group Participation 调优建议

```bash
# 主频道 (1485752475616018514)
alma group participation set randomBoostRate 0.05   # 降低误触率
alma group participation set cooldownMinutes 60     # 延长冷却期
alma group participation set quietMinutes 10        # 安静更久才巡逻
alma group participation set reactionRate 0.2       # 降低 emoji 频率
```

#### Token 成本估算

| 项目 | 频率 | Token 消耗 |
|------|------|-----------|
| Heartbeat 群聊评估 | 每 30 分钟 | ~1K input + ~200 output |
| 每日总计 (48 次) | - | ~57.6K tokens/天 |
| Claude 周限额占用 | - | ~2-4%/天 |

**成本控制**：
- 如果群聊安静（无新消息），heartbeat 直接返回 `HEARTBEAT_OK`，不消耗 LLM token
- 实际成本取决于群聊活跃度，低流量服务器消耗会很低

#### 隐私与安全考量

| 考量 | 对策 |
|------|------|
| 用户不知道被"监听" | 在服务器规则中明确说明 bot 会读取消息（Discord bot 的标准行为） |
| PII 泄露风险 | 被动感知生成的记忆也需遵循 PII 脱敏规则 |
| 过度参与 | 严格的频率限制 + per-group 关闭开关 |

---

## Feature 3: Ruminate 模块

### 3.1 当前状态 (Current State)

#### ✅ 已有能力（分散在各个 skill 中）

**1. 图片处理**  
- Discord bot 自动下载用户发送的图片附件
- 群聊媒体文件保存在 `~/.config/alma/groups/media/` 目录
- LLM 本身支持 vision（Claude 可以看图）
- `image-gen` skill 可以生成/编辑图片

**2. 视频/音频处理 (video-reader skill)**  
- **Gemini 原生视频理解**: `alma video analyze` — 可以理解视频的视觉+音频内容
- **Whisper 转录**: 可以将音频转为文本
- **ffmpeg/ffprobe**: 完整的多媒体处理工具链
- 支持格式: mp4, mov, webm, avi, mkv, m4v, 3gp

**3. 音乐分析 (music-listener skill)**  
- 频谱分析（ffmpeg spectrogram）
- 歌词转录（Whisper）
- 风格/情绪分析

**4. URL 内容提取**
- `web-fetch` skill: WebFetch 工具 + Chrome Relay（可访问需要登录的页面）
- `twitter-media` skill: 通过 fxtwitter API 提取推文文本/图片/视频
- `xiaohongshu-cli` skill: 小红书内容提取

**5. 浏览器自动化 (browser skill)**  
- PinchTab 浏览器自动化
- Chrome Relay 控制用户真实浏览器
- 可以抓取 JS 渲染的页面

#### ❌ 缺失能力

1. **没有统一的输入管线** — 每个 skill 独立工作，没有一个"给我任何信息源，我都能消化"的统一入口
2. **无批量处理** — 所有处理都是实时的（用户发一条消息，处理一条），没有批量消化大量内容的能力
3. **无 Q&A 对生成** — 处理结果是自由文本回复，没有将非结构化信息压缩为"可查询的 grounded Q&A 对"的能力
4. **无 YouTube 转录** — 虽然有视频处理能力，但没有直接的 YouTube URL → 转录文本管线
5. **无 Obsidian/本地文档索引** — 没有将本地 Markdown 文档库（如《圣女之路》worldbuilding）索引化的能力
6. **无一致性检查** — 没有跨文档交叉验证的能力

### 3.2 动机 (Motivation)

**@karlamo 的原话**（03-27 Discord）：
> "输入端完全是插件化的——今天是 YouTube 转录稿，明天是 Discord 历史消息，后天是圣女之路的全部 worldbuilding 文档。ruminate 不关心源头是什么，它只做一件事：把非结构化的大量文本压成 agent 可查询的 grounded Q&A 对。"

**核心痛点**：
- 喵菲斯能**实时处理**非文本信息（有人发图片/视频，可以当场看），但不能**批量消化**大量内容
- 《圣女之路》worldbuilding 散落在 Obsidian 多个子文件夹中（E:\knowledge-garden\02-fiction\圣女之路\），已有完整的角色/世界观/正文/素材，但只有通过临时任务（Task）才能全部读取
- 互联网内容（YouTube 视频、网页文章、推文）的处理是一次性的，看完就忘

**《圣女之路》用例特别有意思**（来自 task 历史）：
- 已经有一次完整的梅奥菲斯角色提取任务（task `e09b0d59`），读取了 20+ 文件，产出了详细的角色档案
- 这个任务发现了**多处不一致**：发色矛盾（银白 vs 栗色）、妹妹名字不一致（露涅萨 vs 兰璱娅）等
- 如果有 ruminate 模块，这种不一致检查可以自动化、周期化

### 3.3 构想 (Vision/Concept)

#### Ruminate 模块架构

```
                    ┌─────────────────┐
                    │   Ruminate Core  │
                    │                 │
                    │  统一处理管线    │
                    │  Q&A 对生成     │
                    │  向量存储       │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────┴─────┐ ┌─────┴─────┐ ┌─────┴─────┐
        │  Adapter 1 │ │  Adapter 2 │ │  Adapter 3 │
        │  Discord   │ │  YouTube   │ │  Obsidian  │
        │  History   │ │  Transcripts│ │  Docs      │
        └───────────┘ └───────────┘ └───────────┘
              │              │              │
        [群聊日志]      [视频URL]      [本地文件夹]
```

#### 核心原则

1. **输入端插件化** — 每种信息源有一个 Adapter，负责将原始数据转化为纯文本
2. **处理端统一** — Ruminate Core 不关心数据来源，只接收文本并生成 Q&A 对
3. **输出端标准化** — 所有产出写入统一的向量记忆 + 结构化摘要文件
4. **增量处理** — 维护 watermark，只处理新增内容

#### 与 agent-integrations 的架构对齐

`agent-integrations` 仓库的核心哲学：
> "Agent providers should focus on reasoning. Integration services should focus on transport, voice, presence, and platform behavior."

Ruminate 模块延续同样的哲学：
> "Agent focuses on reasoning. Ruminate focuses on **ingestion, compression, and indexing** of external information."

当前 `agent-integrations` 的模块结构：

| 模块 | 状态 | 用途 |
|------|------|------|
| `shared/tts` | ✅ 已实现 | 流式 TTS 抽象层 (ElevenLabs v3) |
| `discord/voice-relay` | ✅ 已实现 | Discord 语音中继 |
| `shared/ruminate` | ❌ 待建 | **统一信息消化管线** |
| `adapters/discord-history` | ❌ 待建 | Discord 日志适配器 |
| `adapters/youtube` | ❌ 待建 | YouTube 转录适配器 |
| `adapters/obsidian` | ❌ 待建 | Obsidian 文档适配器 |

Ruminate 可以作为 `agent-integrations` 仓库的新模块，与现有的 `shared/tts` 和 `discord/voice-relay` 平行存在。

### 3.4 实现用例 (Implementation Use Cases)

#### 用例 1: Discord 历史消化 (与 Feature 1 直接关联)

```bash
# Adapter: discord-history
# 输入: ~/.config/alma/groups/discord_*_2026-03-26.log
# 输出: Q&A 对 + 摘要

ruminate ingest \
  --adapter discord-history \
  --source "~/.config/alma/groups/" \
  --date "2026-03-26" \
  --output "~/.config/alma/memory/digest/"
```

产出示例：
```json
[
  {
    "question": "LinkedIn 投递代理在 03-26 的运行情况如何？",
    "answer": "03-26 运行了 27 次投递，100% 成功率。加上前一天的 8 次共 35 次，恰好触碰 LinkedIn 每日上限。Dashboard 已发到 #dashboard 频道。",
    "source": "discord_1485752475616018514_2026-03-26.log",
    "confidence": 0.95,
    "tags": ["job-apply", "linkedin", "production-run"]
  },
  {
    "question": "Chrome 语言设置问题是怎么解决的？",
    "answer": "系统级改了 System Locale、User Culture、Registry。Chrome 级改了 accept_languages 和 selected_languages。最终需要在 chrome://settings/languages 手动删除中文语言才真正生效。",
    "source": "discord_1485752475616018514_2026-03-26.log",
    "confidence": 0.9,
    "tags": ["tech-support", "chrome", "locale"]
  }
]
```

#### 用例 2: YouTube 视频消化

```bash
# Adapter: youtube
# 输入: YouTube URL
# 处理: 下载 → 音频提取 → Whisper 转录 → Q&A 生成

ruminate ingest \
  --adapter youtube \
  --source "https://youtube.com/watch?v=xxx" \
  --output "~/.config/alma/memory/youtube/"
```

处理管线：
```
[YouTube URL]
  → [yt-dlp 下载音频]
  → [Whisper 转录为文本]
  → [LLM: 文本 → 结构化摘要 + Q&A 对]
  → [写入向量记忆]
  → [生成摘要文件]
```

#### 用例 3: 《圣女之路》Worldbuilding 一致性检查

```bash
# Adapter: obsidian / local-docs
# 输入: E:\knowledge-garden\02-fiction\圣女之路\
# 处理: 递归读取 → 分块 → Q&A 生成 → 交叉验证

ruminate ingest \
  --adapter obsidian \
  --source "E:/knowledge-garden/02-fiction/圣女之路/" \
  --output "~/.config/alma/memory/saintess/" \
  --cross-validate
```

一致性检查产出：
```markdown
## 一致性警告

1. ⚠️ 梅奥菲斯发色矛盾
   - 主要人物设定卡: "银白色长发"
   - 外传《月芒》: "栗色长发"
   - 黎澜记忆: "栗色长发，蓝色瞳孔"（但设定卡为"深棕色眼眸"）
   - 建议: 可能是不同时期的设定（8-17岁栗色，后变银白）

2. ⚠️ 妹妹名字不一致
   - 设定卡内心冲突: "妹妹露涅萨"
   - 正式设定: 兰璱娅 (Lunethia)
   - 可能是音译差异
```

#### 用例 4: URL 内容即时消化

**场景**: 经纪人在 Discord 发了一个 URL  
**流程**: 
1. Discord bot 检测到 URL
2. 调用 ruminate 的 URL adapter
3. 抓取内容 → 摘要 → 存入记忆
4. 下次有人问起相关话题时可以引用

### 3.5 技术规格 (Specs)

#### 模块结构（作为 agent-integrations 的扩展）

```
agent-integrations/
├── shared/
│   ├── tts/              # ✅ 已有 — TTS 抽象层
│   └── ruminate/          # 🆕 新增
│       ├── core.js        # Ruminate 核心处理引擎
│       ├── qa-generator.js # Q&A 对生成器
│       ├── indexer.js     # 向量索引管理
│       └── package.json
├── adapters/              # 🆕 新增
│   ├── discord-history/   # Discord 日志适配器
│   │   ├── parser.js      # 日志格式解析
│   │   └── index.js
│   ├── youtube/           # YouTube 转录适配器
│   │   ├── downloader.js  # yt-dlp 包装
│   │   ├── transcriber.js # Whisper 包装
│   │   └── index.js
│   ├── obsidian/          # Obsidian 文档适配器
│   │   ├── crawler.js     # 文件系统递归读取
│   │   └── index.js
│   └── url/               # 通用 URL 适配器
│       ├── fetcher.js     # Web 内容抓取
│       └── index.js
└── discord/
    └── voice-relay/       # ✅ 已有 — 语音中继
```

#### Adapter 接口规范

```typescript
interface RuminateAdapter {
  name: string;           // 适配器名称
  type: 'file' | 'url' | 'stream';
  
  // 将原始数据源转化为纯文本块
  ingest(source: string, options?: IngestOptions): Promise<TextChunk[]>;
  
  // 增量处理：只返回上次处理后的新内容
  ingestIncremental(source: string, watermark: Watermark): Promise<{
    chunks: TextChunk[];
    newWatermark: Watermark;
  }>;
}

interface TextChunk {
  text: string;           // 纯文本内容
  metadata: {
    source: string;       // 原始来源标识
    timestamp?: string;   // 时间戳
    author?: string;      // 作者
    type: string;         // chunk 类型 (conversation, article, transcript, etc.)
    tags?: string[];      // 标签
  };
}

interface QAPair {
  question: string;       // 可能的查询问题
  answer: string;         // grounded 回答
  source: string;         // 数据来源
  confidence: number;     // 置信度 (0-1)
  tags: string[];         // 分类标签
}
```

#### Ruminate Core 处理流程

```
[Adapter.ingest()] → TextChunk[]
    ↓
[Chunking: 按 4K token 分块，保持语义完整性]
    ↓
[LLM Processing: 每个 chunk 生成 3-5 个 Q&A 对]
    ↓
[De-duplication: 与现有记忆去重]
    ↓
[向量化: 将 Q&A 对写入向量记忆]
    ↓
[摘要生成: 写入结构化摘要文件]
    ↓
[更新 watermark]
```

#### 与 Alma 的集成方式

**方案 A: 作为 Alma Skill（推荐初期实现）**

```markdown
# ~/.config/alma/skills/ruminate/SKILL.md

---
name: ruminate
description: 消化和索引非结构化信息。将 Discord 历史、YouTube 视频、
  本地文档等转化为可查询的结构化记忆。
allowed-tools:
  - Bash
  - Read
  - Write
  - WebFetch
---

# Ruminate Skill

## 使用方式

### 消化 Discord 历史
\```bash
# 读取指定日期的群聊日志并生成摘要
cat ~/.config/alma/groups/discord_{channelId}_{date}.log | \
  [LLM处理] → alma memory add "..."
\```

### 消化 YouTube 视频
\```bash
# 1. 下载音频
yt-dlp -x --audio-format wav -o "/tmp/yt_audio.wav" "VIDEO_URL"
# 2. 转录
whisper "/tmp/yt_audio.wav" --model turbo --output_format txt
# 3. 读取转录文本 → LLM 生成 Q&A 对 → alma memory add
\```

### 消化本地文档
\```bash
# 递归读取 Obsidian 文件夹
find "E:/knowledge-garden/02-fiction/圣女之路/" -name "*.md" -exec cat {} \;
# → LLM 分块处理 → Q&A 对 → alma memory add
\```
```

**方案 B: 作为 agent-integrations 独立模块（推荐长期架构）**

作为 Node.js 模块在 `agent-integrations` 仓库中实现，通过 HTTP API 与 Alma 交互：

```
Alma ←→ HTTP API (localhost:3200) ←→ Ruminate Service
                                        ├── Adapter Registry
                                        ├── Processing Pipeline  
                                        └── Vector Store Interface
```

#### Token 成本估算

| 操作 | Token 消耗 | 说明 |
|------|-----------|------|
| Discord 日志消化 (1天) | ~5K | 日志 ~30KB，压缩到摘要 |
| YouTube 视频 (10分钟) | ~10K | 转录 ~2K words + Q&A 生成 |
| Obsidian 文档 (100KB) | ~50K | 大量文本需要分块处理 |
| 《圣女之路》全量 | ~200K | 首次全量处理，之后增量 |

---

## 三项功能的交叉依赖关系

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│    Feature 3: Ruminate Module                            │
│    ┌──────────────────────────────────────────┐          │
│    │  统一处理管线                              │          │
│    │  Adapter 插件系统                         │          │
│    │  Q&A 对生成                               │          │
│    └────────┬──────────────────┬──────────────┘          │
│             │                  │                          │
│    ┌────────▼────────┐  ┌─────▼──────────────┐          │
│    │ Discord History │  │  其他 Adapters      │          │
│    │   Adapter       │  │  (YouTube, Obsidian,│          │
│    │                 │  │   URL, etc.)        │          │
│    └────────┬────────┘  └────────────────────┘          │
│             │                                            │
│    ┌────────▼─────────────────────────────────┐          │
│    │  Feature 1: Discord 历史记忆索引          │          │
│    │  ┌─────────────────────────────────┐     │          │
│    │  │  原始日志 → 摘要 → 向量记忆      │     │          │
│    │  │  增量处理 → 人物档案更新         │     │          │
│    │  └─────────────────────────────────┘     │          │
│    └────────┬─────────────────────────────────┘          │
│             │                                            │
│    ┌────────▼─────────────────────────────────┐          │
│    │  Feature 2: 主动感知                      │          │
│    │  ┌─────────────────────────────────┐     │          │
│    │  │  Heartbeat 周期触发               │     │          │
│    │  │  消化近期日志 → 话题/情绪理解     │     │          │
│    │  │  决策：保持沉默 or 参与           │     │          │
│    │  └─────────────────────────────────┘     │          │
│    └──────────────────────────────────────────┘          │
│                                                          │
│    ════════════════════════════════════════════           │
│    底层共享: Alma Memory System                          │
│    (向量记忆 + 对话归档 + 人物档案 + 群聊日志)             │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 建议实施顺序

| 优先级 | 功能 | 理由 |
|--------|------|------|
| **P0** | Feature 1 (Discord 历史记忆索引) | 最低技术风险，利用现有积木最多，立即可见效果 |
| **P1** | Feature 2 (主动感知) Level 1-2 | 依赖 Feature 1 的摘要数据，heartbeat 配置即可开始 |
| **P2** | Feature 3 (Ruminate) 基础框架 | 将 Feature 1 的管线泛化为通用框架 |
| **P3** | Feature 2 Level 3 + Feature 3 扩展 Adapters | 需要更多实践经验和调优 |

### 共享依赖

| 依赖 | Feature 1 | Feature 2 | Feature 3 |
|------|-----------|-----------|-----------|
| Alma Memory System | ✅ 核心 | ✅ 读写 | ✅ 核心 |
| Cron / Heartbeat | ✅ 定时触发 | ✅ 定时触发 | ⬜ 可选 |
| Discord 日志 | ✅ 数据源 | ✅ 感知源 | ✅ 一种 Adapter |
| LLM 推理 | ✅ 摘要生成 | ✅ 评估判断 | ✅ Q&A 生成 |
| People Profiles | ✅ 更新 | ✅ 读取 | ⬜ 可选 |

---

## 参考架构: agent-integrations

### 仓库概况

**GitHub**: https://github.com/yigong-yg/agent-integrations  
**所有者**: @yigong-yg (karlamo)  
**架构**: npm workspace monorepo  
**最新提交**: 2026-03-24

### 核心设计哲学

> "Agent providers should focus on reasoning. Integration services should focus on transport, voice, presence, and platform behavior."

这是一个 **provider-agnostic** 的集成层，可以对接任何 agent 后端（Anthropic, OpenAI, Gemini, 本地 LLM）。

### 当前模块

| 模块 | 状态 | 用途 |
|------|------|------|
| `shared/tts` | ✅ 已实现 | ElevenLabs v3 流式 TTS |
| `discord/voice-relay` | ✅ 已实现 | Discord 语音中继 |

### Voice Relay 实现细节

Voice Relay 是当前 `agent-integrations` 的核心模块，已在 Alma 中通过自定义 skill 集成：

- **位置**: `~/.config/alma/skills/discord/voice-relay/SKILL.md`
- **本地 API**: `http://127.0.0.1:3100`
- **功能**: 将文本转语音并在 Discord 语音频道播放
- **技术栈**: discord.js voice 0.19.2, opusscript, ElevenLabs v3
- **特性**: debounced auto-speak（监听 bot 的 messageCreate/messageUpdate，等待消息稳定后播报）

### Ruminate 模块的定位

在 `agent-integrations` 的架构中，Ruminate 是 voice-relay 的"镜像"：

| 维度 | Voice Relay | Ruminate |
|------|-------------|----------|
| 方向 | 输出（agent → 世界） | 输入（世界 → agent） |
| 功能 | 将文本转为语音播放 | 将非文本转为可查询知识 |
| 抽象层 | TTS provider | Adapter 插件 |
| 触发 | agent 发送回复时 | 手动/定时/事件驱动 |

---

## 附录: Alma 当前能力全景

### 内置 Skills (Bundled)

| Skill | 与本报告相关度 | 说明 |
|-------|-------------|------|
| `memory-management` | ⭐⭐⭐ | 核心——向量记忆、对话归档、人物档案 |
| `discord` | ⭐⭐⭐ | Discord bot 交互：发消息、发文件、贴纸、DM |
| `self-reflection` | ⭐⭐⭐ | 日记系统，可复用于日摘要生成 |
| `scheduler` | ⭐⭐⭐ | Cron jobs + Heartbeat，自动化调度 |
| `reactions` | ⭐⭐ | 被动 emoji 反应（主动感知的轻量交互） |
| `video-reader` | ⭐⭐ | 视频/音频处理（Ruminate 的 adapter 素材） |
| `music-listener` | ⭐ | 音乐分析 |
| `web-fetch` | ⭐⭐ | URL 内容抓取（Ruminate URL adapter 素材） |
| `web-search` | ⭐ | 网页搜索 |
| `twitter-media` | ⭐⭐ | 推文内容提取（Ruminate adapter 素材） |
| `browser` | ⭐⭐ | 浏览器自动化（高级抓取） |
| `self-management` | ⭐ | 配置管理 |
| `file-manager` | ⭐ | 文件管理 |
| `image-gen` | - | 图片生成 |
| `music-gen` | - | 音乐生成 |
| `selfie` | - | 自拍生成 |
| `send-file` | - | 文件发送 |
| `todo` | - | 任务列表 |
| `tasks` | ⭐ | 全局任务追踪 |
| `travel` | - | 虚拟旅行 |
| `voice` | - | 本地 TTS |
| `notebook` | - | Jupyter 编辑 |
| `xiaohongshu-cli` | ⭐ | 小红书内容提取 |
| `system-info` | - | 系统信息 |
| `plan-mode` | - | 规划模式 |
| `skill-hub` / `skill-search` | - | Skill 管理 |
| `thread-management` | - | 对话线程管理 |

### 自定义 Skills (User-installed)

| Skill | 说明 |
|-------|------|
| `discord/voice-relay` | Agent Voice 语音中继，对接 agent-integrations |
| `job-apply` | LinkedIn 自动投递代理 |

### API 能力 (REST API @ localhost:23001)

| 端点 | 说明 |
|------|------|
| `GET/PUT /api/settings` | 配置读写 |
| `GET/POST/PUT/DELETE /api/providers` | AI 提供商管理 |
| `GET /api/models` | 可用模型列表 |
| `POST /api/discord/send` | 发送 Discord 消息 |
| `POST /api/discord/send-photo` | 发送图片 |
| `POST /api/discord/send-file` | 发送文件 |
| `POST /api/discord/reaction` | 添加 emoji 反应 |
| `GET /api/health` | 健康检查 |

### 当前 Provider 配置

| Provider | 状态 | 模型 |
|----------|------|------|
| Claude Subscription | ✅ 启用 | claude-opus-4-6, claude-sonnet-4-6 |
| DeepSeek | ❌ 禁用（曾用于 Discord） | deepseek-chat |
| OpenAI | ❌ 禁用（未配置 API key） | — |
| Anthropic (Direct) | ❌ 禁用（未配置 API key） | — |

### 配置亮点

| 设置 | 当前值 | 备注 |
|------|--------|------|
| `memory.enabled` | true | ✅ 记忆系统已开启 |
| `chat.defaultModel` | claude-subscription:claude-opus-4-6 | 主力模型 |
| Cron jobs | `[]` (空) | ⚠️ 无定时任务 |
| HEARTBEAT.md | 不存在 | ⚠️ 心跳未配置 |
| `memory/` 目录 | 空 | ⚠️ 日记/摘要未生成过 |
| 群聊日志 | 5天 ~101KB | ✅ 在持续积累 |

---

## 总结与建议

### 立即可做（零开发成本）

1. **配置 Heartbeat** — 创建 HEARTBEAT.md，启用心跳和群巡逻
2. **创建 Cron Job** — 每日定时生成群聊摘要
3. **执行第一次 self-reflection** — 启动日记系统
4. **调优群聊参与度** — 降低 randomBoostRate 和 reactionRate

### 短期可做（Skill 级别开发）

1. **Ruminate Skill** — 作为 Alma skill 实现基础版 ruminate
2. **Discord History Adapter** — 日志解析 + 摘要生成
3. **向量记忆填充** — 开始积累结构化记忆

### 长期可做（模块级别开发）

1. **agent-integrations/shared/ruminate** — 独立服务化
2. **YouTube / Obsidian Adapters** — 扩展输入源
3. **一致性检查引擎** — 自动化 worldbuilding 交叉验证
4. **主动参与 Level 3** — 需要大量实践调优

---

> *报告完毕。以上为纯研究产出，不涉及任何配置修改。所有建议的实施需要 @karlamo 批准后由 Developer/Operator 执行。*
>
> *— 喵菲斯 🐱*
