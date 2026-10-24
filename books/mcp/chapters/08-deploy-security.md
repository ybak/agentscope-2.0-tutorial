---
chapter: 8
title: 部署与安全
source: https://modelcontextprotocol.io/specification/2026-07-28 (transports / security)
---

# 第 8 章 部署与安全

> 从"能跑"到"敢上生产"。多租户与安全是平台刚需。

## 本章节级大纲

- 传输选型:stdio(本地/单机)vs Streamable HTTP(服务化);2026-07-28 header 路由与无状态部署的配合
- 鉴权与授权:2026-07-28 授权框架(RFC 9207 对齐)逐点讲;内网 token / OAuth 的选型
- **多租户下的工具可见性与权限**:哪些租户/Agent 能看哪些工具(呼应平台最大缺口,与第 6 章目录治理衔接)
- 安全专题:tool poisoning、工具描述注入、Server 供应链可信(来源审核、签名)、最小权限原则、敏感数据经工具外泄的路径与防护
- 生产运维:进程管理、健康检查、容量与限流、监控指标与 trace 埋点(→ langfuse 书交叉引用)
- 部署清单(章节收尾:checklist 形式)

## 写作备注

- 素材:spec transports/security/authorization 页;tool poisoning 公开研究(引用标注);团队安全规范
- 核对清单:2026-07-28 授权框架细节与弃用项以官方 spec 为准;安全研究引用动笔前重查是否有新披露
