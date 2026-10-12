---
chapter: 27
title: Skill 仓库
source: integration/skill/index.md, integration/skill/overview.md, integration/skill/git-repository.md
---

# 第 27 章 Skill 仓库

> 本章导读：讲解 `AgentSkillRepository` 接口的三种开箱即用实现——Git 技能仓库（远程仓库 + 轻量 remote ref 检查，按需 pull）、MySQL 与 PostgreSQL 技能仓库（数据库 CRUD，在线编辑即时生效；两者均已标记废弃，建议迁移到第 24 章的统一 JDBC 模块）。章首还给出两条使用契约：作用域隔离（每个仓储实例只服务一个作用域）与实例复用（同来源共享实例、不为每个 Agent 重建）。读完本章，你可以为技能选择合适的存储来源，并在多团队、多作用域场景下正确组合多个仓储。

`AgentSkill` 是 AgentScope 用 Markdown + 资源文件来描述一个可复用"技能"的格式（参考第 15 章）。`AgentSkillRepository` 接口负责把这些技能从外部存储里加载进来，再交给 `Toolkit` / `ReActAgent` 使用。

`agentscope-extensions-*` 仓库提供了以下开箱即用的实现：

| 扩展 | 后端 | 适合场景 |
| --- | --- | --- |
| Git Repository | 远程 Git 仓库 | 用 Git 流程管控技能版本，跨团队共享 |
| MySQL Repository | MySQL 数据库 | 通过控制台 / 业务系统在线编辑、动态发布 |
| PostgreSQL Repository | PostgreSQL 数据库 | 已有 PostgreSQL 基础设施，在线编辑、动态发布 |

> Nacos 也提供了一个 `AgentSkillRepository` 实现：见第 28 章。

表中各实现的接入细节见本章后续各节。

## 接入方式

```java
AgentSkillRepository repo = ...;        // 任选一种实现
List<AgentSkill> skills = repo.getAllSkills();

Toolkit toolkit = new Toolkit();
skills.forEach(toolkit::registerSkill);

ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .toolkit(toolkit)
    .build();
```

## 选型建议

- **想用 Git PR 流程管控、可读可 review** → Git
- **要在管理后台 / 配置中心动态修改、立即生效** → MySQL、PostgreSQL 或 Nacos
- **多种来源混用** → 实现 `AgentSkillRepository` 自己组合，或多个 repo 都注册到 toolkit

## 作用域隔离

技能名是人起的（`code-review`、`git-helper`），不同团队、不同作用域重名是常态。`AgentSkillRepository` 契约要求**每个仓储实例只服务一个作用域**：同名技能跨作用域共存，读写、覆盖（含 `force`）、删除都只发生在实例绑定的作用域内；实例够不着的作用域显式拒绝，而不是静默落到别处。

各来源用后端原生的维度表达作用域，构造时传入即可：

| 来源 | 隔离维度 | 用法 |
| --- | --- | --- |
| FileSystem | `baseDir` 目录 | 每个作用域一个目录、一个仓储实例 |
| Classpath | `resourcePath` 前缀 | 同上 |
| Workspace（Harness） | `RuntimeContext` 用户 | `workspace/<userId>/skills/` 按用户隔离 |
| Git | 仓库 / 分支 / `skillsRoot` | 不同作用域用不同仓库、分支或仓库内子目录 |
| Nacos | 原生 `namespaceId` | 构造时绑定一个命名空间 |
| JDBC | `namespace` 列 | 构造时绑定，见第 24 章（"作用域隔离（namespace）"一节） |

一个应用需要多个作用域时，为每个作用域注册一个仓储再组合——`HarnessAgent.builder().skillRepository(a).skillRepository(b)`，后注册的优先级更高——而不是让一个仓储跨作用域查询。

自定义实现遵循同一要求：选你后端原生的维度、构造时绑定、所有操作限定在绑定作用域内、够不着的作用域显式报错。

## 实例复用

多个 Agent 指向同一个技能来源（相同的 baseDir、Nacos namespaceId、Git 仓库等）时，构造一个仓储实例共享给它们，不要为每个 Agent 各建一个。仓储实例按构造参数寻址、可安全共享；重复构造的代价因来源而异——Nacos 仓储每个实例都会建立一条到服务端的客户端连接，Git 仓储在未指定本地路径时各自 clone 一份仓库。Spring 场景下把仓储声明为单例 Bean 注入即可。对应地，不同作用域各建各的实例（见上节）。

## Git 技能仓库

`agentscope-extensions-skill-git-repository` 把一个远程 Git 仓库当作技能仓库：每次读取时做轻量的 remote ref 检查，只在远端 HEAD 变化时才真正 pull，平时几乎零开销。

### 何时使用

- 想用 Git 来管控技能内容的版本与审阅。
- 想跨多个项目共享同一份技能集。
- 不希望在生产服务里嵌入数据库或配置中心。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-skill-git-repository</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

底层使用 JGit，HTTPS / SSH 都支持。

### 快速上手

```java
import io.agentscope.core.skill.repository.GitSkillRepository;
import io.agentscope.core.skill.AgentSkill;

// 公开仓库 + 默认分支，使用临时目录
GitSkillRepository repo = new GitSkillRepository(
    "https://github.com/agentscope/skills.git"
);

// 取出全部技能注册到 Toolkit
Toolkit toolkit = new Toolkit();
repo.getAllSkills().forEach(toolkit::registerSkill);

// 应用退出时清理临时目录
Runtime.getRuntime().addShutdownHook(new Thread(repo::close));
```

### 选定分支 / 自定义本地路径

```java
GitSkillRepository repo = new GitSkillRepository(
    "https://github.com/agentscope/skills.git",
    "develop",                   // 分支
    Path.of("/var/skills/repo"), // 本地路径（null = 临时目录）
    "agentscope-public",         // source 标识（在 Toolkit 里能看到）
    true                         // autoSync = true，每次读自动检查并 pull
);
```

### 私有仓库的鉴权

`GitSkillRepository` 复用系统级 Git 配置，不在 Java 侧管理凭证：

- **HTTPS**：使用 `~/.gitconfig` 里的 credential helper（osxkeychain、libsecret 等）。
- **SSH**：使用 `~/.ssh/` 下的密钥与 ssh-agent。

```java
// SSH 私有仓库
GitSkillRepository repo = new GitSkillRepository(
    "git@github.com:my-org/private-skills.git"
);
```

CI 环境下请确保 runner 用户具备相应凭证或挂载好 SSH agent。

### 自动同步与手动同步

- `autoSync=true`（默认）：`getSkill / getAllSkills / skillExists` 等读操作前会先 `ls-remote`，如远端有更新才执行 pull。
- `autoSync=false`：完全不自动 pull，要刷新时调用 `repo.sync()`。

```java
GitSkillRepository repo = new GitSkillRepository(remoteUrl, false);
repo.sync();              // 启动时同步一次
schedule(() -> repo.sync(), 5, TimeUnit.MINUTES);  // 定时同步
```

### 工程实践建议

- 建议在 Spring Bean 上以单例形式持有仓库，重启时统一 `close()`。
- 临时目录会注册 JVM Shutdown Hook 自动删除；如果你强制 kill 进程，可能残留，需要外部清理。
- 多实例部署时各自维护一份本地 clone，没有锁竞争。

## MySQL 技能仓库

> **已废弃**：请迁移到统一 JDBC 模块（见第 24 章）的 `JdbcAgentSkillRepository`——一套实现覆盖 MySQL、PostgreSQL、H2、SQLite 及后续方言。本模块建的表原样可用，早于 metadata_json 的旧表需先补一列；迁移要点见第 24 章（"从历史模块迁移"一节）。

`agentscope-extensions-skill-mysql-repository` 把技能存到 MySQL，提供完整的 CRUD：在控制台/业务系统里编辑保存，Agent 这边立即可读。

### 何时使用

- 通过管理后台在线运营技能，希望"改完即生效"。
- 已经有 MySQL 基础设施，不想再引入 Git 依赖。
- 需要把技能存储和业务数据放在同一事务边界。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-skill-mysql-repository</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import com.zaxxer.hikari.HikariDataSource;
import io.agentscope.core.ReActAgent;
import io.agentscope.core.skill.repository.mysql.MysqlSkillRepository;

HikariDataSource ds = new HikariDataSource();
ds.setJdbcUrl("jdbc:mysql://localhost:3306/agentscope");
ds.setUsername("root");
ds.setPassword("***");

// 第二参数 createIfNotExist=true：自动建库建表
MysqlSkillRepository repo = new MysqlSkillRepository(ds, true);

ReActAgent agent = ReActAgent.builder()
    .name("assistant")
    .model(model)
    .skillRepository(repo)
    .build();
```

### 表结构

`createIfNotExist=true` 时自动创建以下两张表：

```sql
CREATE TABLE IF NOT EXISTS agentscope_skills (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    skill_content LONGTEXT NOT NULL,
    source VARCHAR(255) NOT NULL,
    metadata_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS agentscope_skill_resources (
    id BIGINT NOT NULL,
    resource_path VARCHAR(500) NOT NULL,
    resource_content LONGTEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id, resource_path),
    FOREIGN KEY (id) REFERENCES agentscope_skills(id) ON DELETE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

- `agentscope_skills`：技能本身，`name` 唯一，`skill_content` 存 `SKILL.md` 全文。
- `agentscope_skill_resources`：技能附带的资源文件（截图、模板等），与 `id` 级联。

### 与已有表兼容

- 旧表如果没有 `metadata_json` 列，仓库会自动降级到"只往返 name + description"的兼容模式，不会主动 `ALTER TABLE`。
- 想升级到完整模式，自行执行 `ALTER TABLE agentscope_skills ADD COLUMN metadata_json LONGTEXT NULL;` 即可。

### 自定义库名 / 表名

```java
MysqlSkillRepository repo = new MysqlSkillRepository(
    ds,
    "skill_center",          // 库名
    "ops_skills",            // 技能表
    "ops_skill_resources",   // 资源表
    true                     // 自动建库建表
);
```

### CRUD 操作

```java
// 写入（save 是 upsert：name 已存在则更新）
AgentSkill skill = ...;
repo.save(List.of(skill), /* overwrite */ true);

// 读取
AgentSkill loaded = repo.getSkill("calculator");
List<String> names = repo.getAllSkillNames();
boolean exists = repo.skillExists("calculator");

// 删除
repo.delete("calculator");
```

写入与删除都在事务里执行，资源表的 `ON DELETE CASCADE` 保证不会出现孤儿资源。

## PostgreSQL 技能仓库

> **已废弃**：请迁移到统一 JDBC 模块（见第 24 章）的 `JdbcAgentSkillRepository`——一套实现覆盖 MySQL、PostgreSQL、H2、SQLite 及后续方言。本模块建的表原样可用，早于 metadata_json 的旧表需先补一列；迁移要点见第 24 章（"从历史模块迁移"一节）。

`agentscope-extensions-skill-postgresql-repository` 把技能存到 PostgreSQL，提供完整的 CRUD：在控制台/业务系统里编辑保存，Agent 这边立即可读。

### 何时使用

- 通过管理后台在线运营技能，希望"改完即生效"。
- 已经有 PostgreSQL 基础设施，不想再引入 Git 依赖。
- 需要把技能存储和业务数据放在同一事务边界。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-skill-postgresql-repository</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import javax.sql.DataSource;
import io.agentscope.core.skill.repository.postgresql.PostgresSkillRepository;

DataSource ds = ...;  // HikariCP、PgBouncer 等连接池

// createIfNotExist=true：自动建 schema 和表；writeable=true：允许写入
PostgresSkillRepository repo = new PostgresSkillRepository(ds, true, true);

Toolkit toolkit = new Toolkit();
repo.getAllSkills().forEach(toolkit::registerSkill);
```

### 使用 Builder

```java
PostgresSkillRepository repo = PostgresSkillRepository.builder(ds)
    .schemaName("my_schema")
    .skillsTableName("my_skills")
    .resourcesTableName("my_resources")
    .createIfNotExist(true)
    .writeable(true)
    .build();
```

### 表结构

`createIfNotExist=true` 时自动创建以下两张表（在指定 schema 下）：

```sql
CREATE TABLE IF NOT EXISTS "agentscope"."agentscope_skills" (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    skill_content TEXT NOT NULL,
    source VARCHAR(255) NOT NULL,
    metadata_json TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "agentscope"."agentscope_skill_resources" (
    id BIGINT NOT NULL,
    resource_path VARCHAR(500) NOT NULL,
    resource_content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, resource_path),
    FOREIGN KEY (id) REFERENCES "agentscope"."agentscope_skills"(id) ON DELETE CASCADE
);
```

- `agentscope_skills`：技能本身，`name` 唯一，`skill_content` 存 `SKILL.md` 全文。
- `agentscope_skill_resources`：技能附带的资源文件（截图、模板等），与 `id` 级联。

与 MySQL 版不同，PostgreSQL 使用 **schema**（而非 database）作为命名空间隔离边界，数据库由 JDBC URL 决定。

### 与已有表兼容

- 旧表如果没有 `metadata_json` 列，仓库会自动降级到"只往返 name + description"的兼容模式，不会主动 `ALTER TABLE`。
- 想升级到完整模式，自行执行 `ALTER TABLE "agentscope"."agentscope_skills" ADD COLUMN metadata_json TEXT NULL;` 即可。

### CRUD 操作

```java
// 写入（save 是 upsert：name 已存在则更新）
AgentSkill skill = ...;
repo.save(List.of(skill), /* overwrite */ true);

// 读取
AgentSkill loaded = repo.getSkill("calculator");
List<String> names = repo.getAllSkillNames();
boolean exists = repo.skillExists("calculator");

// 删除
repo.delete("calculator");
```

写入与删除都在事务里执行，资源表的 `ON DELETE CASCADE` 保证不会出现孤儿资源。

### Builder 配置参数

| 方法 | 说明 |
| --- | --- |
| `schemaName(String)` | 默认 `agentscope` |
| `skillsTableName(String)` | 默认 `agentscope_skills` |
| `resourcesTableName(String)` | 默认 `agentscope_skill_resources` |
| `createIfNotExist(boolean)` | `true` 时自动 `CREATE SCHEMA` + `CREATE TABLE`，默认 `true` |
| `writeable(boolean)` | 是否允许写操作，默认 `true` |

## 本章小结

这一章回答的是技能放在哪、怎么组合的问题。接入动作对三种来源是同一套：`getAllSkills()` 取出、`registerSkill` 注册，或直接 `skillRepository(...)` 挂入 Agent；真正要选的是存储与更新方式：

1. **Git 技能仓库**：远程仓库 + 轻量 remote ref 检查，只在远端 HEAD 变化时才 pull；凭证复用系统级 Git 配置（HTTPS credential helper / SSH），`autoSync` 可关、改用 `repo.sync()` 手动刷新；
2. **MySQL 技能仓库**（**已废弃**）：数据库 CRUD，控制台/业务系统编辑保存、Agent 立即可读，库名表名可自定义；
3. **PostgreSQL 技能仓库**（**已废弃**）：与 MySQL 版同构，以 **schema**（而非 database）为命名空间隔离边界，支持 Builder 配置与 `writeable` 只读模式。

两个数据库仓库都已标记废弃——统一 JDBC 模块（第 24 章）的 `JdbcAgentSkillRepository` 一套实现覆盖 MySQL、PostgreSQL、H2、SQLite 及后续方言，本模块建的表原样可用。

最后回到章首的两条使用契约，它们比选哪个实现更容易被忽略：**作用域隔离**——每个仓储实例只服务一个作用域，多作用域用多个仓储组合（后注册的优先级更高），不让一个仓储跨作用域查询；**实例复用**——同来源共享一个实例（Spring 下声明为单例 Bean），重复构造的代价是 Nacos 多一条客户端连接、Git 各自 clone 一份仓库。

**验收清单**——读到这里，你应该能：

- ☐ 用 `getAllSkills()` 加 `registerSkill` 把任一来源的技能注册进 Toolkit，或用 `skillRepository(...)` 直接挂入 Agent；
- ☐ 按选型建议三条，为自己的场景在 Git 与数据库来源之间做选择并说明理由；
- ☐ 解释每个仓储实例只服务一个作用域的含义，并说出 Git 仓储表达作用域的三个维度；
- ☐ 解释同来源为什么要共享仓储实例，说出 Nacos 与 Git 仓储各自重复构造的代价；
- ☐ 复述 MySQL / PostgreSQL 仓库的废弃状态与迁移目标，说出旧表升级到完整模式要补哪一列。

## 延伸阅读

- 第 15 章（技能）—— `AgentSkill` 格式与 `Toolkit` 的技能注册机制，本章三种仓储加载的就是它
- 第 24 章（会话存储与分布式部署）—— 统一 JDBC 模块 `JdbcAgentSkillRepository`、作用域隔离（namespace）与迁移要点
- 第 28 章（基础设施与生态工具）—— Nacos 技能仓库与集成扩展全览表
