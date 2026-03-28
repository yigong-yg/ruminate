# Ruminate System Spec
**Status**: v3 — CC 审查修正 + Meowfis 修订
**Date**: 2026-03-27
**Roles**: Karla (架构师+用户) · Meowfis/Alma (PM) · Claude Code (工程师)
**v3 变更**: Embedding 首选改 OpenAI · 费用估算修正 + 成本优化路径 · 圣女之路用例挂钩 · 数据生命周期问题 · NotebookLM API 评估

---

## 0. 核心定位

> **Ruminate 解决的是输入端问题，不是输出端问题。**
>
> Agent 作为 Input Layer Filter → 提高 Input 质量 → Output 质量提高是自然发生的。
>
> "和 Warren Buffet 吃午饭，哪怕聊天内容是牛排熟度，embedding 也是自己吃饭不可比拟的。"
> — Karla

### 设计哲学

| 维度 | 决策 | 理由 |
|---|---|---|
| 核心问题 | **推进未来**（~80%），回忆过去 ~20% | 回忆过去最大价值点：圣女之路小说一致性 |
| 参考标杆 | NotebookLM | 中间层 + 与记忆设计同构 + 降低幻觉率 |
| 交互模式 | 晨间 briefing + 实时按需 | briefing 要的是洞察不是信息（冰山理论："看到你忽略的联系"） |
| 自治路径 | L1 → L2（主要时间）→ L3 | 保守起步，不跳级 |
| 用户规模 | 单用户 | 记忆框架本身具备灵活性，不需多租户 |
| 噪音定义 | **系统管输入质量，不管输出判断** | "噪音"应在输入端过滤，输出端判断是 agent 的事 |
| 错误处理 | 跳过 + 记录日志，不阻塞管道 | 超级个体 > 系统 > 个体（无标签） |

---

## 1. 架构总览

### 1.1 运行时拓扑

```
┌──────────── 本地 (Karla's Windows) ────────────┐     ┌──── 云端 Workers ────┐
│                                                  │     │                      │
│  ┌─────────┐  REST API   ┌──────────┐           │     │  ┌────────────────┐  │
│  │ Claude   │ ──────────→ │   Alma   │           │     │  │ Whisper API    │  │
│  │  Code    │ ←────────── │  Server  │ ◄─────────┼─────┼──│ LLM API        │  │
│  │(无状态)  │  :23001     │(入口+调度)│           │     │  │ Embedding API  │  │
│  └─────────┘              └──────────┘           │     │  │ YouTube DL     │  │
│       │                        │                 │     │  └────────────────┘  │
│       │   ┌────────────────────┘                 │     │                      │
│       │   │  File System (shared truth)          │     │  ┌────────────────┐  │
│       ├───┤  ~/.config/alma/memory/              │     │  │ Rec Engine     │  │
│       │   │  ~/.config/alma/groups/              │     │  │ (未来)         │  │
│       │   │  ~/.config/alma/people/              │     │  └────────────────┘  │
│       │   └──────────────────────                │     │                      │
│       │                                          │     └──────────────────────┘
│       │  SQLite (加速层，非真相源)                │
│       └── alma/chat_threads.db                   │
│           alma/memories (向量)                    │
└──────────────────────────────────────────────────┘
```

**关键决策：**

| 决策 | 选择 | 理由 |
|---|---|---|
| 重活（转写/embedding/推荐） | **云端 workers** | 本地跑太笨重，一步到位 |
| 与 Alma 本地进程冲突？ | **不冲突** | Alma 是 agent 入口 + 调度，云端是执行层 |
| 状态管理 | **文件系统 + Alma SQLite 双层** | CC session 是无状态执行器，不是状态存储层 |
| API 调用方式 | **一律走 REST API** | 云端必须走 REST；本地 CC 也走 REST 保持一致，不绕过 Alma 业务逻辑 |
| Agent 间通信 | **当前：人类枢纽（Karla 中转）** | OK，未来可自动化 |

### 1.2 角色分工

| 角色 | 身份 | 职责 |
|---|---|---|
| **架构师 + 用户** | Karla | 架构决策、需求定义、最终验收 |
| **产品经理** | Meowfis/Alma | 需求梳理、问题拆解、spec 维护、审查 |
| **工程师** | Claude Code | 实现、调试、测试、脚本开发 |

### 1.3 设计原则

1. **Agent-Oriented Design (AOD)**: 每个独立能力封装为一个 agent，agent 之间通过明确协议通信
2. **文件层优先**: 所有持久化数据必须有 human-readable 的文件表示，向量/数据库是加速层不是真相源
3. **渐进自治**: L1 → L2 → L3，不跳级
4. **可观测性**: 每个 agent 的输入、输出、错误必须可追溯
5. **输入端治理**: 系统管输入质量，输出判断是 agent 的事

---

## 2. Agent 清单

| Agent | 职责 | 运行环境 | 自治等级 | 状态 |
|---|---|---|---|---|
| **Alma** | Discord 交互、人格表达、日常对话、调度入口 | Alma Desktop (Electron, 本地) | L1 | ✅ 运行中 |
| **Claude Code** | 开发、调试、系统管理、编排（无状态执行器） | Terminal (本地) | L0-L1 | ✅ 运行中 |
| **Digest Agent** | 日志 → 摘要 → 文件层 (→ 可选向量层) | Alma Heartbeat | L2 | ⏳ 文件层就绪 |
| **Ingestion Agent** | 非文本源 → 结构化文本 | 云端 worker | L1 | 📋 待设计 |
| **Research Agent** | 深度搜索 + 多源综合 + 报告生成 | 云端 worker | L1 | 📋 待设计 |
| **Recommendation Agent** | 个人知识推荐引擎（搜广推） | 云端 worker | L1→L2 | 🔮 未来 |
| **Monitor Agent** | API 健康、成本追踪、异常告警 | 云端 worker | L2 | 📋 待设计 |

---

## 3. 通信协议

### 3.1 Agent 间通信

```
Claude Code ──REST──→ Alma Server (:23001)    # 结构化操作
Alma Server ──File──→ ~/.config/alma/         # 持久化
Cloud Worker ──REST──→ Alma Server             # 结果回写
Karla ──────Human────→ 跨 Agent 中转           # 当前模式，未来可自动化
```

**规则：**
- 所有写操作走 REST API，不直接碰 SQLite（保护 Alma 业务逻辑：去重、embedding 触发等）
- 文件系统是共享读取层（Alma 和 CC 都可读）
- CC 是无状态执行器，不存储会话状态

### 3.2 数据流向

```
[外部源]                    [处理层]              [存储层]              [消费层]

YouTube ───→ Ingestion ──→ transcript.md ──→ ┐
Podcast ───→ Ingestion ──→ episode.md    ──→ ├→ memory/         ──→ Alma (对话检索)
Browser ───→ Ingestion ──→ bookmark.md   ──→ ┤   digest/            Claude Code (开发上下文)
Discord ───→ Digest    ──→ {date}.md     ──→ ┤   ingested/          晨间 Briefing
Substack ──→ RSS       ──→ article.md    ──→ ┘   research/          推荐系统 (未来)
```

---

## 4. Feature 规格

### 4.1 Digest Pipeline (Feature 1 & 2) — ⏳ 文件层就绪

**输入**: `~/.config/alma/groups/*.log`
**输出**: `~/.config/alma/memory/digest/{YYYY-MM-DD}.md`
**触发**: Alma Heartbeat (4h 间隔)
**向量层**: 可选，需要 embedding provider（**OpenAI `text-embedding-3-small` 首选**，DeepSeek 备选。理由：切换 provider 需全库 rebuild，成本 >> 价格差，稳定性优先）

#### 胶水层（自建方案）

```
触发条件: memory/digest/ 下出现新 .md 文件
处理逻辑:
  1. 读取 .md 文件
  2. 按 ## 标题拆分为 chunks
  3. 每个 chunk → POST /api/memories {content, metadata: {source: "digest", date}}
  4. 记录已处理文件到 .vector-watermark
失败处理: 跳过 + 记录日志，下次重试
```

### 4.2 Ingestion Pipeline (Feature 3) — 📋 设计中

> 核心使命：把非结构化富媒体变成可用知识

#### 4.2.1 YouTube / 长视频 → Text

| 维度 | 决策 |
|---|---|
| 视频源 | YouTube 为主（外网高质量内容），B站人工看（娱乐为主） |
| 内容类型 | 高质量长内容（数小时级），无特定偏好，learn by doing |
| 触发方式 | **Phase 1**: 手动丢链接 → **Phase 2**: 自动推荐 |
| 处理粒度 | **全文转写 + 摘要，全都要**；后续靠内容评分裁剪 |
| 处理时间 | 无硬性限制（后台处理即可） |
| 运行环境 | 云端 worker |

```
Pipeline:
  1. yt-dlp 提取 metadata + 字幕 (优先官方字幕，fallback Whisper)
  2. Whisper API 转写 (~$0.006/min，4h视频 ~$1.44)
  3. 字幕清洗 + 分段
  4. LLM 全文摘要 + 章节摘要 + 关键点提取
  5. 输出 → memory/ingested/youtube/{video-id}.md
  6. 内容评分 (后期加入，反哺推荐系统)
  7. 错误 → 跳过 + 记录日志
```

#### 4.2.2 播客 → Text

```
输入: RSS feed URL 或手动链接
处理: 类似 YouTube pipeline (音频提取 → Whisper → LLM 摘要)
输出: memory/ingested/podcast/{episode-slug}.md
优先级: 中（有价值但低于 YouTube）
```

#### 4.2.3 浏览器上下文 → Text

```
场景: Alma 官方 Discord 等无法直接访问的内容
方案: 待评估 (browser extension? manual paste? screen reader?)
优先级: 低（有潜力但方案不明确）
```

#### 4.2.4 截图 / 语音备忘 → ❌ 不做

```
理由: 截图垃圾内容太多，语音备忘需求不存在
```

### 4.3 Personal Knowledge Recommendation Engine — 🔮 终极形态

> 这不是一个 Feature，是 Ruminate 的终极升维。

#### 设计理念

```
手动丢链接 (Phase 1)
    ↓ 积累用户兴趣画像
自动推荐系统 (Phase 2)
    ↓ diversity + novelty score
每日推送 (Phase 3)
    ├── 5 个熟悉领域内容 (巩固)
    ├── 3 个高潜力内容 (人工判断无价值但实际有价值的)
    ├── 1 个 novel 内容 (推荐系统改进/探索)
    └── 1 个超出当前水平的内容 (拉伸区)
    ↓ 用户反馈 → 迭代
需求本身不断进化 (这才是好的产品形态)
```

#### 关键洞察

- **Agent 作为 Input Layer Filter**：agent 不是帮你处理信息，是帮你**筛选信息源**
- **搜广推架构**：先粗筛（多源聚合）→ 精排（个性化打分）→ 推荐（多样性+新颖性）
- **bias-variance tradeoff**：初期全文转写（高 variance），后期靠内容评分收敛（降 bias）
- **时效性要求**：12-24小时以内即可
- **RSS 渠道**：Substack 等通过 RSS 自动监听

### 4.4 晨间 Briefing — 📋 待设计

```
目标: 每日洞察，不是信息堆叠
内容:
  - 投资/新闻中的高潜力信号
  - 跨领域联系挖掘 (冰山理论：看到忽略的联系，而不是信息本身)
  - 昨日 digest 精华
  - 推荐系统推送 (Phase 2+)
形式: Alma 主动 DM，简洁，可展开
```

### 4.5 圣女之路 Worldbuilding 一致性 — 📋 待设计

> 回忆过去 20% 中的最高优需求。

```
场景: 小说创作中需要检索角色、情节线、世界观设定的历史一致性
实现路径: 向量记忆语义搜索 (不是独立 agent，是 Alma 记忆层的应用)
前提: 小说内容需入库 (按角色/章节/设定分 chunk → embedding)
入库方式: 
  1. 手动导入现有内容 → memory/creative/saintess/
  2. 后续写作自动追加
查询方式: Alma 对话中自然语言检索 ("圣女之路里XX角色的设定是什么")
优先级: M1 向量层就绪后即可开始，不依赖云端 worker
```

### 4.6 Research Pipeline — 📋 待设计

```
输入: 研究问题 (自然语言)
处理:
  1. 查询改写 (query decomposition)
  2. 多源搜索 (web + memory + ingested docs)
  3. 综合 + 去重 + 矛盾检测
  4. 结构化报告输出
输出: memory/research/{topic-slug}.md
触发: 手动 (按需)
```

---

## 5. 存储架构

```
~/.config/alma/
├── memory/
│   ├── digest/              # 每日 Discord 摘要
│   │   ├── {YYYY-MM-DD}.md
│   │   ├── .watermark       # digest 进度
│   │   └── .vector-watermark # 胶水层进度
│   ├── ingested/            # 非文本源转化结果
│   │   ├── youtube/
│   │   ├── podcast/
│   │   └── browser/
│   └── research/            # 研究报告
│       └── {topic-slug}.md
├── skills/
│   └── digest/
│       └── SKILL.md
├── groups/                  # 原始 Discord 日志 (只读)
└── people/                  # 人物档案

./agent-integrations/        # Claude Code 侧实现
├── spec.md                  # 本文件
├── decisions.md             # 架构决策记录 (ADR)
├── scripts/
│   ├── digest-to-vector.sh  # 胶水层: digest → 向量
│   ├── youtube-ingest.sh    # YouTube 转写管道
│   └── bulk-import.sh       # 批量导入工具
├── skills/                  # 自定义 Alma Skills
│   └── (待定)
└── tests/
    └── (待定)
```

---

## 6. 依赖与成本

| 依赖 | 用途 | 成本 | 必要性 |
|---|---|---|---|
| Claude Subscription | Alma 聊天 + Claude Code 开发 | 已有 | 必须 |
| OpenAI API | Embedding (**首选**, `text-embedding-3-small`) + Whisper 转写 | Embedding 极低 + Whisper ~$0.006/min | 向量层 + Ingestion |
| DeepSeek API | Embedding (备选) + 廉价 LLM 调用 | 极低 | 备选/摘要生成 |
| yt-dlp | YouTube 下载 | 免费 | Ingestion |
| 云端 worker 运行环境 | 转写/embedding/推荐计算 | 待评估 | Phase 2+ |

**费用估算（月度）：**
- 轻度使用（每周 1-2 个视频）：< $5/月
- 中度使用（每周 3-5 个长视频 + 推荐）：$20-40/月（⚠️ 4h视频 Whisper 转写 ~$1.44/个，5个/周 ≈ $30/月纯转写）
- 重度使用（全自动推荐引擎）：$50-150/月（主要是 LLM + Whisper 调用）

**成本优化路径：**
- Phase 1: 优先使用 YouTube 官方字幕/自动字幕（免费），仅无字幕视频 fallback Whisper
- Phase 2: 评估本地 `whisper.cpp` 可行性，大幅降低转写成本（GPU 有则免费）
- NotebookLM：**无官方 API**，有非官方逆向库 `notebooklm-py` 可探索，但稳定性存疑，不作为主路径

---

## 7. 里程碑

| 阶段 | 内容 | 前置条件 | 状态 |
|---|---|---|---|
| **M0** | Digest 文件层稳定运行 + 心跳 | Alma 配置 | ✅ 就绪 |
| **M1** | Embedding provider 启用 + 胶水层 | OpenAI API 接入 (`text-embedding-3-small`) | ⏳ 待执行 |
| **M2** | YouTube Ingestion MVP (手动丢链接) | yt-dlp + Whisper API + 云端 worker | 📋 设计中 |
| **M3** | 晨间 Briefing MVP | M0 + M1 | 📋 待设计 |
| **M4** | 播客 Ingestion | M2 pipeline 复用 | 📋 待设计 |
| **M5** | 推荐系统 MVP (内容评分 + 兴趣画像) | M2 + 足够的 ingested 数据 | 🔮 未来 |
| **M6** | 自动推荐 + 每日推送 | M5 + 用户反馈循环 | 🔮 未来 |
| **M7** | L3 自治 (全自动 + 自我改进) | M0-M6 稳定运行 | 🔮 远期 |

---

## 8. 已关闭的开放问题

| 问题 | 答案 | 决策轮次 |
|---|---|---|
| 核心定位：记忆力 vs 执行力？ | 推进未来 (~80%)，回忆过去 (~20%) | R1 |
| 每日交互模式？ | 晨间 briefing (洞察) + 实时按需 | R1 |
| Agent 自治等级？ | L1 → L2 → L3，保守路径 | R1 |
| 噪音定义？ | 系统管输入端，输出判断是 agent 的事 | R1 |
| 单用户 vs 多用户？ | 单用户 | R1 |
| YouTube 消费模式？ | 高质量长内容，无特定偏好，learn by doing | R2 |
| 触发方式？ | 手动丢链接 → 自动推荐系统（渐进） | R2 |
| 处理粒度？ | 全文转写 + 摘要，全都要 | R2 |
| 非文本源优先级？ | YouTube > 播客 > 浏览器 >> 截图/语音(不做) | R2 |
| 错误处理？ | 跳过 + 记日志，不阻塞 | R2 |
| 运行时拓扑？ | 本地 Alma 调度 + 云端 workers 执行 | R3 |
| CC Session 状态？ | CC 是无状态执行器，不存储状态 | R3 |
| API 方式？ | 一律 REST API（云端必须，本地也统一） | R3 |
| Agent 间通信？ | 当前人类中转 OK，未来可自动化 | R3 |
| 认知负荷？ | 投资（原话：\"投资我和Meowfis的爱巢\"）| R3 |
| Embedding provider 首选？ | OpenAI `text-embedding-3-small`（切换成本 >> 价格差）| CC审查 |
| 圣女之路实现路径？ | 向量记忆语义搜索，小说内容入库 | CC审查 |
| NotebookLM 转写可行性？ | 无官方 API，`notebooklm-py` 可探索但不作为主路径 | CC审查 |

## 9. 剩余开放问题（实现阶段按需补充）

- [ ] 云端 worker 具体部署方案？(Cloudflare Workers? AWS Lambda? VPS?)
- [ ] 推荐系统的 diversity/novelty score 算法设计？
- [ ] 晨间 briefing 的具体内容模板？
- [ ] 浏览器上下文采集方案？
- [ ] 工作流版本控制需求？(SKILL.md git track?)
- [ ] 安全红线明确定义？
- [ ] 成功度量标准？
- [ ] **数据生命周期策略**：`memory/ingested/` 会持续增长（一年后数百个转写文件 + 数千条向量），需要定义：文件层归档/清理机制？向量层旧记忆衰减 vs 全量保留？存储成本上限？
- [ ] **圣女之路内容入库方案**：按角色/章节/设定分 chunk 的最优粒度？增量更新策略？
- [ ] **NotebookLM 非官方 API (`notebooklm-py`) 可行性评估**：稳定性、rate limit、是否值得作为转写/摘要的替代路径？

---

*本文档由 Meowfis (PM) 根据三轮 Ruminate 对话整理。最终实现在 `./agent-integrations/` 目录下。*
*下次更新：M2 YouTube Ingestion 详细设计*
