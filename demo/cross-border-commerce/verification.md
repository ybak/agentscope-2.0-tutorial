# 续接实测记录 · 2026-10-13

本记录区分脚本交付、真实运行结果与未完成验收。**本轮没有完成全量两遍通过**：Workflow 的真实模型调用遭遇免费额度耗尽，用户选择“先完成可验证部分，保留额度阻塞”。未切换模型、未开通付费，也未改服务端代码。

## 环境与检查结果

- Gateway：本地 `http://localhost:28080`。
- `/api/v1/version` 实测：`{"apiVersion":"v1alpha1","component":"aistio","experimental":false,"version":"0.2.0"}`。
- 相邻 `agentscope-java` 源码工作区 HEAD：`3c1c29c0`（仅供定位，不声称运行进程与该提交无差异）。
- 已回读 `seashore-main`：owner alice，members 同时包含 admin/alice；`aurora-main` 包含 admin/bob。接手时权限已恢复，本轮未覆写 namespace 成员。

| 检查项 | 本轮结果 | 证据与限制 |
| --- | --- | --- |
| 01 身份 | 通过 | 三账号可用 |
| 02 入驻 | 通过 | 商家互不可见对方 namespace |
| 03 Agent 矩阵 | 通过 | 复用 4 个 Agent，验证各自归属 |
| 04 会话 | 通过 | 本轮新增回复及 idle；日志回复截断为“好…”；这只证明调用完成，不代表业务答案质量合格 |
| 05 隔离 | 通过 | 9 项断言，包括跨商家访问 404 与正向对照 |
| 06 Team | 部分通过 | attempt 已产生；Task 最终 failed，不能视作业务闭环完成 |
| 07 Workflow | 阻塞 | research attempt 返回 403 `AllocationQuota.FreeTierOnly`，Run failed |
| 08 Endpoint | 通过重发与回读 | 停用后重新 publish；固定幂等键回读此前 completed conversation，未生成新的模型回复 |
| 09 人工审批 | 多次通过 | 共享指定工单 → approved → 旧版本重复决批 409 → 评论成功 |
| 10 Automation | 多次通过 | 5 次排程预览；queued → completed；固定键复用同一运行/工单 |
| 可逆清理 | 通过 | Endpoint disabled、Automation enabled=false，均回读确认；之后已恢复 Endpoint published |
| 离线入口 | 通过 | 主线/全部列表、dry-run、单步选择与 5 种错误参数处理 |
| 静态检查 | 通过 | 所有 Bash 脚本 `bash -n`、`git diff --check`、10 篇教程 frontmatter 与本地链接检查 |

## 可追踪资源

| 对象 | ID |
| --- | --- |
| Team Task | `aa358f0b-5d7a-466d-af7c-130f74b75dc0` |
| Team attempt | `49dc120f-d6b3-4e15-bdec-ad9a05de8ac8` |
| Workflow Run（失败） | `107ca176-295b-4e68-964a-640a202ecca5` |
| Workflow attempt（额度错误） | `8f3b2e55-2379-4cf0-a171-7fc4dfd0bb6a` |
| Endpoint | `7d6efb5a-2dff-4433-9c65-73d83594c547` |
| Endpoint conversation（历史完成结果） | `d09c37ad-a698-4cae-8d96-70041bc9b2fd` |
| 审批（最终补测） | `783c46ef-03f0-41aa-b692-6589d302fc3b` |
| Automation | `ed463cd1-25d2-4135-b2ef-f16283fcec4a` |
| Automation Run | `fe7ba72c-5f72-4c69-86ab-e15b764110da` |
| Automation 生成的工单 | `7b60500f-ea2e-5a0e-86ed-c8744f47830a` |

Workflow 的错误摘要来自 `/api/v1/orchestration-runs/{id}/events` 中 `attempt.failed` 与 `run.failed` 的 payload：

```text
HTTP 403
code: AllocationQuota.FreeTierOnly
message: Free quota exhausted.
failureCode: turn_failed
```

本机原始执行日志在 `/tmp/xbd-regression-1.log` 与 `/tmp/xbd-remaining.log`，不入库；临时目录可能被清理。本记录保留关键 ID、状态与错误，不保存 JWT、API Key 或完整 `.env`。

## 相对原实施计划的调整

1. 人工审批采用同 namespace 的工单显式共享，不使用搬到 default namespace 的绕行方案；未实现真实退款或 runtime tool 暂停恢复。
2. Automation 默认 `enabled=false`，用 `test=true` 实际生成测试工单。未验证次日定时触发或抓取真实价格。
3. 清理改为可逆停用 Endpoint/Automation，保留所有配置与历史；不执行归档全库后重建。
4. 修正主线 GET 身份参数位置；Step 04 增加本轮事件计数验收；Team 输出当前状态，不预判错误原因。
5. 额度阻塞后停止新的模型回归。全量第二遍、Workflow 成功终态与新 Endpoint 调用仍待额度恢复后验证。

## 恢复后的操作

先确认服务端已有可用模型额度。如果仅增加现有模型额度，可继续：

```bash
cd demo/cross-border-commerce
./run-all.sh --from 7
# 验证原计划的两遍全量：
./run-all.sh
./run-all.sh
```

若改用其他模型，还需更新已有 Agent 的模型定义；只设置 `XBD_MODEL` 不会覆写已创建的 Agent。对外调用的固定幂等键会复用历史结果，如需验证新回复，应显式使用新的业务幂等键。

## 课程补充：Workspace、沙箱与自有模型通道

同日新增Step 11 / 12 / 13。以下是这三节的独立验收，不改变上面的主线额度阻塞结论。

| 检查项 | 结果 | 边界 |
| --- | --- | --- |
| 11 Workspace | 多次通过 | 两份文件写入并回读；重复发布复用 revision 1；实验 Agent 的绑定版本与 digest 一致 |
| 12 Environment | 真实执行通过 | 回读默认 local；控制面把 sandbox 环境直配为阿里云沙箱（E2B 兼容端点 + `config.apiKey`，Dataplane 零配置）；实验 Agent 绑定后新会话在云沙箱内 write/read 随机标记成功回读；第二个新会话读同路径确认 SESSION 隔离；超时回收与快照恢复留作手动观察 |
| 13 模型定义 | 通过读取与保存 | 用原模型 ID 保存实验 Agent，回读 definition version 2；Workspace、工具与环境字段保持一致；未切换通道 |
| 11–13 执行入口 | 通过 | `./run-all.sh --from 11`；12/13 默认不发模型请求 |
| 原隔离步骤 | 9 项通过 | 增加实验 Agent 后仍验证原业务角色齐全、namespace 归属及跨商家拒绝访问 |
| 静态检查 | 通过 | 全部 Bash 语法、13 篇步骤 frontmatter、本地 Markdown 链接与 `git diff --check` |
| Java 适配示例 | 编译通过 | 使用本地 core/OpenAI 构建产物与 Spring 依赖运行 javac；不等于自定义 Dataplane 已部署 |
| 离线入口与模型探针 | 通过 | `python3 tests/test_entrypoints.py`：全部 13 步单步选择、8 种错误参数及6种本地 HTTP 桩响应；桩测试不代表真实模型网关 |

新增资源：Workspace `ws_1f00115de267`，实验 Agent `64582f1d-6afc-4dcc-a670-c0b5eb326835`，沙箱环境登记 `env_9eabd64e9e27`（后经控制面 PATCH 为阿里云沙箱配置并真实执行）。Workspace revision 1 的 digest 为 `f91d28ea116cd9f4fc3d3d4a69e7ca6a3d882def54da68e73d6b716bf4aa674f`。

仍待具备凭据和额度后验收：工作区运行期文件投影与工具读取、沙箱超时回收与快照恢复、自有模型通道文本/工具/流式调用、自定义 Dataplane 部署与新 Chat 端到端执行。E2B 实例启动与 SESSION 文件隔离已于 2026-10-14 用阿里云沙箱实测通过（见上表 Step 12）。本轮未修改相邻 Service 源码；沙箱验证期间为绕开免费额度耗尽，将实验 Agent 模型从 `deepseek-v4-flash-0731` 临时切换为 `qwen-flash`。

### 连续编号调整验证

课程与脚本统一为 `step-01` 至 `step-13`，目录、图示、章节链接和执行入口同步。离线检查覆盖全部单步（含 01–09 写法）、默认 13 步、断点续跑、列表及错误参数；模型探针继续用本地桩验证。本次编号调整未触发新的模型、审批或自动化运行。Automation 保留历史幂等键，避免改名导致重复工单。
