# Alma Memory System — 逆向工程内部文档

**来源**: asar extract + SQLite 直接读取  
**Alma版本**: v0.0.727  
**日期**: 2026-03-27  
**用途**: 供 Claude Code 测试和集成开发使用  

---

## 1. 架构总览

Alma 的记忆系统分两层：

| 层 | 存储 | 需要 embedding? | 状态 |
|---|---|---|---|
| 文件层 | `~/.config/alma/memory/digest/{date}.md` | ❌ | ✅ 已运行 |
| 向量层 | SQLite `memories` + `memory_embeddings` (vec0) | ✅ | ⏳ 需要 embedding provider |

两层是**平行**的。文件层由 Heartbeat + Digest Skill 写入，Alma 直接读 markdown。向量层由 `POST /api/memories` 写入，支持语义搜索。

**关键约束**: 创建 memory 时 content 和 embedding 是**强耦合**的——无法只写 content 不生成 embedding。没有 embedding provider 时 `POST /api/memories` 直接返回 400。

---

## 2. SQLite 数据库

**路径**: `C:\Users\gongy\AppData\Roaming\alma\chat_threads.db`  
**注意**: Alma 运行时会锁定数据库，测试时建议先 `cp` 一份副本操作。

### 2.1 `memories` 表

```sql
CREATE TABLE memories (
  id TEXT PRIMARY KEY,
  content TEXT,
  metadata TEXT,        -- JSON string
  thread_id TEXT,
  message_id TEXT,
  created_at TEXT,      -- ISO timestamp
  updated_at TEXT,      -- ISO timestamp
  user_id TEXT
);

CREATE INDEX idx_memories_thread_id ON memories(thread_id);
CREATE INDEX idx_memories_created_at ON memories(created_at);
CREATE INDEX idx_memories_updated_at ON memories(updated_at);
CREATE INDEX idx_memories_user_id ON memories(user_id);
```

当前状态: **0 rows** (从未写入过)

### 2.2 `memory_embeddings` 虚拟表

```sql
CREATE VIRTUAL TABLE memory_embeddings USING vec0(
  memory_id TEXT PRIMARY KEY,
  embedding FLOAT[1536]
);
```

- 使用 [sqlite-vec](https://github.com/asg017/sqlite-vec) 扩展
- 向量维度固定 **1536** (与 OpenAI text-embedding-3-small / DeepSeek embedding 兼容)
- `memory_id` 外键关联 `memories.id`
- vec0 扩展 DLL 路径: `C:\Users\gongy\AppData\Local\Programs\Alma\resources\app.asar.unpacked\node_modules\sqlite-vec-windows-x64\vec0.dll`

### 2.3 相关辅助表

```
memory_embeddings_chunks      — vec0 内部分块存储
memory_embeddings_info        — vec0 元数据 (版本 v0.1.7-alpha.2)
memory_embeddings_rowids      — vec0 行ID映射
memory_embeddings_vector_chunks00 — vec0 向量数据块
memory_metadata               — 键值对存储 (当前为空)
```

---

## 3. 未文档化的 Memory REST API

**Base URL**: `http://localhost:23001` (端口可能变化，检查 `~/.config/alma/api-spec.md` 中的实际端口)

### 3.1 CRUD 操作

#### GET /api/memories
列出所有记忆。

```bash
curl -s http://localhost:23001/api/memories | jq
```

返回: `Memory[]` 数组

#### GET /api/memories/:id
获取单条记忆。

```bash
curl -s http://localhost:23001/api/memories/MEMORY_ID | jq
```

#### POST /api/memories
创建新记忆。**需要 embedding provider**。

```bash
curl -s -X POST http://localhost:23001/api/memories \
  -H "Content-Type: application/json" \
  -d '{
    "content": "2026-03-23: Fireflow Discord服务器正式创建",
    "threadId": "optional-thread-id",
    "messageId": "optional-message-id",
    "metadata": {"source": "digest", "date": "2026-03-23"}
  }' | jq
```

请求体:
```typescript
{
  content: string;      // 必填，不能为空
  threadId?: string;    // 可选，关联的 thread ID
  messageId?: string;   // 可选，关联的 message ID
  metadata?: object;    // 可选，JSON 元数据
}
```

**错误场景**:
- 无 embedding provider → `400 {"error": "No embedding provider configured..."}`
- content 为空 → `400`
- 服务未就绪 → `503 {"error": "Memory service not available", "serviceStatus": ...}`

#### PUT /api/memories/:id
更新记忆内容。

```bash
curl -s -X PUT http://localhost:23001/api/memories/MEMORY_ID \
  -H "Content-Type: application/json" \
  -d '{"content": "updated content"}' | jq
```

#### DELETE /api/memories/:id
删除单条记忆。

```bash
curl -s -X DELETE http://localhost:23001/api/memories/MEMORY_ID
```

#### DELETE /api/memories
**清空所有记忆**（危险操作）。

```bash
curl -s -X DELETE http://localhost:23001/api/memories
```

### 3.2 搜索

#### POST /api/memories/search
语义搜索。**需要 embedding provider**。

```bash
curl -s -X POST http://localhost:23001/api/memories/search \
  -H "Content-Type: application/json" \
  -d '{"query": "上次讨论求职的是什么时候"}' | jq
```

请求体 (推测，需要测试确认):
```typescript
{
  query: string;        // 搜索查询
  limit?: number;       // 最大返回数
  threshold?: number;   // 相似度阈值
}
```

### 3.3 管理

#### GET /api/memories/status
检查记忆服务状态。

```bash
curl -s http://localhost:23001/api/memories/status | jq
```

返回:
```json
{
  "ready": true,
  "initialized": true,
  "error": null,
  "rebuilding": false
}
```

#### GET /api/memories/stats
获取记忆统计。

```bash
curl -s http://localhost:23001/api/memories/stats | jq
```

返回:
```json
{
  "total": 0,
  "bySource": {},
  "byThread": {}
}
```

#### GET /api/memories/embedding-model
获取当前 embedding 模型配置。

```bash
curl -s http://localhost:23001/api/memories/embedding-model | jq
```

返回:
```json
{"model": null}  // 未配置时
```

### 3.4 重建索引 (关键发现!)

Alma 官方 Discord 回复称没有 rebuild 命令——**但源码中存在**。

#### POST /api/memories/rebuild
重建所有记忆的 embedding 向量。

```bash
curl -s -X POST http://localhost:23001/api/memories/rebuild | jq
```

内部逻辑 (从 minified 源码推断):
1. 检查是否有 embedding provider，无则返回 400
2. 遍历 `memories` 表所有记录
3. 对每条记录的 `content` 调用 embedding API
4. 更新 `memory_embeddings` 虚拟表中的向量
5. 支持进度查询和取消

#### GET /api/memories/rebuild-progress
查询重建进度。

```bash
curl -s http://localhost:23001/api/memories/rebuild-progress | jq
```

#### POST /api/memories/cancel-rebuild
取消正在进行的重建。

```bash
curl -s -X POST http://localhost:23001/api/memories/cancel-rebuild | jq
```

---

## 4. Embedding Provider 配置

### 4.1 当前 Provider 状态

```bash
curl -s http://localhost:23001/api/providers | jq '.[] | {id, name, type, enabled}'
```

| Provider ID | Name | Type | Enabled |
|---|---|---|---|
| openai | OpenAI | openai | ❌ false |
| claude-subscription | Claude Subscription | claude-subscription | ✅ true |
| deepseek | DeepSeek | deepseek | ❌ false |
| anthropic | Anthropic | anthropic | ❌ false |

### 4.2 启用 DeepSeek 作为 Embedding Provider

```bash
# 1. 启用 DeepSeek provider
curl -s -X PUT http://localhost:23001/api/providers/deepseek \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}' | jq

# 2. 配置 memory embedding 模型
# 先 GET settings，修改 memory.embeddingModel，再 PUT 回去
current=$(curl -s http://localhost:23001/api/settings)
updated=$(echo "$current" | jq '.memory.embeddingModel = "deepseek:deepseek-embedding"')
curl -s -X PUT http://localhost:23001/api/settings \
  -H "Content-Type: application/json" \
  -d "$updated" | jq '.memory'
```

### 4.3 启用 OpenAI 作为 Embedding Provider (备选)

```bash
# 1. 启用 OpenAI provider
curl -s -X PUT http://localhost:23001/api/providers/openai \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}' | jq

# 2. 配置
current=$(curl -s http://localhost:23001/api/settings)
updated=$(echo "$current" | jq '.memory.embeddingModel = "openai:text-embedding-3-small"')
curl -s -X PUT http://localhost:23001/api/settings \
  -H "Content-Type: application/json" \
  -d "$updated" | jq '.memory'
```

### 4.4 格式说明

`memory.embeddingModel` 格式为 `"providerId:modelId"`，其中 `providerId` 是 Alma 内部分配的 ID（可以是用户自定义名称如 "openai" 或 UUID 如 "mldj8z8v4idasx5idot"）。通过 `curl -s http://localhost:23001/api/providers | jq '.[].id'` 获取。

---

## 5. Memory 设置

### 5.1 当前配置

```json
{
  "memory": {
    "enabled": true,
    "autoSummarize": true,
    "autoRetrieve": true,
    "maxRetrievedMemories": 10,
    "similarityThreshold": 0.5,
    "embeddingModel": null    // 未配置
  }
}
```

### 5.2 完整 Memory Settings Schema

```typescript
interface MemorySettings {
  enabled: boolean;
  autoSummarize: boolean;     // 聊天中自动提取关键信息存入向量库
  autoRetrieve: boolean;      // 回复时自动从向量库检索相关记忆
  maxRetrievedMemories: number; // 每次检索最多返回几条 (1-20)
  similarityThreshold: number;  // 余弦相似度阈值 (0-1)
  queryRewriting?: boolean;
  summarizationModel?: string;  // "providerId:modelId"
  toolModel?: string;           // "providerId:modelId"
  embeddingModel?: string;      // "providerId:modelId"
}
```

---

## 6. 兼容性注意事项

### 6.1 Chat 和 Embedding 可以用不同 Provider

Alma 的设计允许：
- `chat.defaultModel` → Claude Subscription (Anthropic)
- `memory.embeddingModel` → DeepSeek 或 OpenAI

两者独立运行，不冲突。

### 6.2 切换 Embedding Provider 必须重建

DeepSeek embedding 和 OpenAI embedding 虽然都是 1536 维，但潜空间不同。切换后必须：
1. 清空旧向量: `DELETE /api/memories` 或逐条删除
2. 切换 `memory.embeddingModel`
3. 重新写入所有 memories (重新调用 `POST /api/memories`)
4. 或者使用 `POST /api/memories/rebuild`（如果 memories 表中的 content 还在）

### 6.3 Digest 文件不会自动进入向量层

心跳 / Digest Skill 生成的 `memory/digest/*.md` 文件**不会**自动写入 SQLite `memories` 表。需要在 Digest Skill 的 SKILL.md 中显式调用 `alma memory add` 或通过 API `POST /api/memories`。

---

## 7. 测试清单

以下测试需要先启用一个 embedding provider：

- [ ] `POST /api/memories` — 创建单条记忆，确认写入成功
- [ ] `GET /api/memories` — 确认能列出
- [ ] `POST /api/memories/search` — 语义搜索测试
- [ ] `POST /api/memories/rebuild` — 重建测试
- [ ] `GET /api/memories/rebuild-progress` — 进度查询
- [ ] 批量导入测试 — 循环调用 POST /api/memories 导入 digest 文件内容
- [ ] `DELETE /api/memories/:id` — 删除单条
- [ ] 切换 provider 后 rebuild 测试

### 7.1 建议的批量导入脚本框架

```bash
# 读取每个 digest 文件，按 "## " 段落拆分，逐条写入
for file in ~/.config/alma/memory/digest/*.md; do
  date=$(basename "$file" .md)
  # 用 awk 按 ## 标题拆分段落
  awk '/^## /{if(buf)print buf; buf=$0; next}{buf=buf" "$0}END{if(buf)print buf}' "$file" | while read -r chunk; do
    [ -n "$chunk" ] && curl -s -X POST http://localhost:23001/api/memories \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"$date: $chunk\", \"metadata\": {\"source\": \"digest\", \"date\": \"$date\"}}"
  done
done
```

---

## 8. 源码逆向笔记

- 主入口: `app.asar → out/main/index.js` (minified, ~1.5MB)
- 代码是单文件 bundle，所有模块打包在一起
- 关键函数名 (通过 grep 提取):
  - `addMemory`, `createMemory`, `deleteMemory`, `getMemory`, `getMemoryById`
  - `searchMemory`, `rebuildMemoryEmbeddings`
  - `getMemoryServiceStatus`, `getMemoryStats`, `getMemorySettings`
  - `getMemoryToolModel`, `getMemoryToolModelEndpoint`
  - `rewriteQueryForMemorySearch` (查询改写，用于提高检索质量)
  - `OperateMemory` (可能是工具调用接口)
- sqlite-vec 扩展加载路径: `app.asar.unpacked/node_modules/sqlite-vec-windows-x64/vec0.dll`

---

*本文档基于 Alma v0.0.727 的 asar 解包和 SQLite 直接读取生成。API 行为可能随版本更新变化。*
