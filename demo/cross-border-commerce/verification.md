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
| A 人工审批 | 多次通过 | 共享指定工单 → approved → 旧版本重复决批 409 → 评论成功 |
| B Automation | 多次通过 | 5 次排程预览；queued → completed；固定键复用同一运行/工单 |
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
./run-all.sh --from 7 --with-ext
# 验证原计划的两遍全量：
./run-all.sh --with-ext
./run-all.sh --with-ext
```

若改用其他模型，还需更新已有 Agent 的模型定义；只设置 `XBD_MODEL` 不会覆写已创建的 Agent。对外调用的固定幂等键会复用历史结果，如需验证新回复，应显式使用新的业务幂等键。
