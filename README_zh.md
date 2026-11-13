# postgres

> 本说明也有 [English 版本](./README.md)。

基于 **PostgreSQL 18** 的 Docker 镜像，可选集成**中文全文检索**（[`zhparser`](https://github.com/amutu/zhparser)）与
**地理空间**（[PostGIS](https://postgis.net)）扩展。所有镜像均将系统 locale 设为 `zh_CN.UTF-8`、时区设为 `Asia/Shanghai`。

镜像发布到 GitHub Container Registry；当配置了仓库 Secrets `DOCKER_USERNAME` / `DOCKER_PASSWORD` 时，也可发布到 Docker
Hub：

| 标签                                    | 基础镜像                 | 扩展                      | 说明                                                                                                             |
|-----------------------------------------|--------------------------|---------------------------|------------------------------------------------------------------------------------------------------------------|
| `ghcr.io/vnobo/postgres:18`             | `postgres:18`            | —                         | PostgreSQL 18，带 `zh_CN.UTF-8` locale 与 `Asia/Shanghai` 时区。                                                 |
| `ghcr.io/vnobo/postgres:18-zhparser`    | `postgres:18`            | zhparser + scws           | 增加中文全文检索。                                                                                               |
| `ghcr.io/vnobo/postgres:18-postgis`     | `postgis/postgis:18-3.6` | PostGIS + zhparser + scws | 地理空间 + 中文全文检索。                                                                                        |
| `ghcr.io/vnobo/postgres:latest-postgis` | `postgis/postgis:18-3.6` | PostGIS + zhparser + scws | 最近一次 `18-postgis` 构建的滚动 `latest` 别名（每次 `main`/tag 构建时推送）。**不建议用于固定版本的生产环境。** |

## 目标读者与使用场景

- **运维 / 决策者**：只想用现成 PostgreSQL 18 中文环境，或评估本仓库是否适用 —— 读镜像表与选型。
- **应用开发者**：需要中文全文检索（车牌、地址、商品名等）—— 使用 `18-zhparser` 或 `18-postgis`。
- **构建 / 维护者**：要改镜像、升级依赖或理解 CI 发布 —— 读“从源码构建 / CI/CD”。

## 镜像选型

| 你的需求                              | 推荐标签                                |
|---------------------------------------|-----------------------------------------|
| 仅 PostgreSQL 18 + 中文 locale / 时区 | `:18`                                   |
| 中文全文检索（无地理需求）            | `:18-zhparser`                          |
| 中文检索 + 地理空间查询               | `:18-postgis`                           |
| 始终用最新 postgis 构建（滚动）       | `:latest-postgis`（不建议生产固定依赖） |

## 前置要求

- 已安装 Docker（建议 24+，支持多阶段构建与从 `ghcr.io` 拉取）。
- 能访问 `ghcr.io`（拉取预构建镜像）或具备构建环境（从源码构建时）。
- 连接客户端：`psql`（PostgreSQL 客户端），或用容器内的 `docker exec`。

## 技术栈与钉死版本

| 组件        | 版本              | 来源                                                | 说明                                                                                       |
|-------------|-------------------|-----------------------------------------------------|--------------------------------------------------------------------------------------------|
| PostgreSQL  | 18                | `postgres:18`                                       | 跟随最新 18.x 补丁（安全）。                                                               |
| PostGIS     | 3.6 (3.6.0)       | `postgis/postgis:18-3.6`                            | 要求 PostgreSQL 12–18。                                                                    |
| scws (SCWS) | 1.2.3 (`a04ef5e`) | [hightman/scws](https://github.com/hightman/scws)   | 中文分词 C 库；钉死到 1.2.3 release commit，因为上游 `master` 在当前 automake 下构建失败。 |
| zhparser    | master (latest)   | [amutu/zhparser](https://github.com/amutu/zhparser) | 构建自最新 `master`；未钉死，因此构建不可复现、供应链不安全。                              |

> **升级：** scws 钉死到 1.2.3 release commit（其 `master` 在当前 automake 下损坏）；zhparser 跟随上游 `master`
> HEAD。要改任一版本，编辑 [`zhparser/Dockerfile`](./zhparser/Dockerfile) 与 [`postgis/Dockerfile`](./postgis/Dockerfile)
> 中对应的 `ARG`/fetch。

## 快速开始

### 拉取预构建镜像

```bash
docker pull ghcr.io/vnobo/postgres:18
docker pull ghcr.io/vnobo/postgres:18-zhparser
docker pull ghcr.io/vnobo/postgres:18-postgis
```

### 运行并启用中文检索

使用命名卷持久化数据，避免容器删除后数据丢失：

```bash
docker run --name pg \
  -e POSTGRES_PASSWORD=secret \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  -d ghcr.io/vnobo/postgres:18-zhparser
```

启用扩展，然后在[中文分词实战](#中文分词实战)中创建 `chinese` 文本搜索配置并尝试分词示例：

```sql
create extension if not exists zhparser;
```

## 中文分词实战

`zhparser` 基于 [scws](https://github.com/hightman/scws) 分词器：它将中文切分为**词元（lexemes）**，PostgreSQL 再将其索引为
`tsvector` 并用 `tsquery` 匹配。与英文不同，中文没有空格作为词边界，因此分词器需要判断词从哪里开始、在哪里结束 ——
而混合内容（中文 + 字母 + 数字，例如车牌号）正是难点所在。

> **注意：** 以下 `to_tsvector` / `ts_debug` 的词元与 `ST_DistanceSphere` 距离为**示意输出，未经实跑验证** ——
> 请以你实际环境中的结果为准（可用 [`zhparser/zhparser.sql`](./zhparser/zhparser.sql) 验证）。

### 案例 1 — 纯车牌号

像 `京A12345` 这样的车牌混合了汉字、拉丁字母与数字。zhparser 将其作为整体切分：

```sql
select to_tsvector('chinese', '京A12345');
-- '京a12345':1
```

### 案例 2 — 车牌嵌入中文地址

当车牌是更长字符串的一部分时，周围的中文会被独立切分：

```sql
select to_tsvector('chinese', '北京市海淀区京A12345违法记录');
-- '北京':1 '北京市':2 '海淀区':3 '京a12345':4 '违法':5 '记录':6
```

### 案例 3 — 注册自定义词，使车牌前缀保持完整

默认情况下省份字母（`京A`、`沪B` …）可能被拆开。将其注册为自定义词并重新同步，使其始终作为一个词元：

```sql
insert into zhparser.zhprs_custom_word
values ('京A'),
       ('沪B');
select sync_zhprs_custom_word();
alter extension zhparser update;
```

同步后，重新运行案例 2 会保持 `京A` 完整，并使按车牌前缀搜索更可靠。可用 `ts_debug` 观察同步前后的切分差异：

```sql
-- 注册自定义词前：省份前缀可能被拆开
select ts_debug('chinese', '京A12345违法记录');
-- 注册 '京A' 并执行 sync_zhprs_custom_word() 后：'京A' 是一个词元
```

### 组合：中文分词 + PostGIS（地理搜索）

在 `18-postgis` 镜像上，你可以同时索引中文文本**和**几何，并一次性联合查询 —— 例如“找出车牌/地址匹配关键词、且距某点 50 km
内的车辆”：

```sql
-- 在 ghcr.io/vnobo/postgres:18-postgis 上执行
create extension if not exists postgis;
create extension if not exists zhparser;

drop text search configuration if exists chinese;
create text search configuration chinese (parser = zhparser);
alter text search configuration chinese add mapping for n,v,a,i,e,l,x with simple;

create table vehicles
(
    id       serial primary key,
    plate    text,                 -- 车牌号，例如 '京A12345'
    address  text,                 -- 中文地址
    location geometry(Point, 4326) -- 经度/纬度
);

-- 自动维护的中文搜索向量（PostgreSQL 12+ 生成列）
alter table vehicles
    add column search tsvector
        generated always as (
            to_tsvector('chinese', coalesce(plate, '') || ' ' || coalesce(address, ''))
            ) stored;

create index vehicles_search_gin on vehicles using gin (search);
create index vehicles_loc_gist on vehicles using gist (location);

insert into vehicles (plate, address, location)
values ('京A12345', '北京市海淀区中关村南大街', ST_SetSRID(ST_MakePoint(116.316, 39.983), 4326)),
       ('沪B67890', '上海市浦东新区世纪大道', ST_SetSRID(ST_MakePoint(121.505, 31.239), 4326));

-- 关键词匹配 + 空间过滤（北京中心 50 km 内）
select plate,
       address,
       ST_DistanceSphere(
               location,
               ST_SetSRID(ST_MakePoint(116.40, 39.90), 4326)
       ) as dist_m
from vehicles
where search @@ to_tsquery('chinese', '北京')
  and ST_DWithin(
        location::geography,
        ST_SetSRID(ST_MakePoint(116.40, 39.90), 4326)::geography,
        50000
      );
--  plate   | address                  | dist_m
-- ---------+--------------------------+---------
--  京A12345 | 北京市海淀区中关村南大街 | ~7800
```

`GIN` 索引加速 `@@` 全文匹配；`GiST` 索引加速 `ST_DWithin` 空间过滤。使用 `::geography` 可获得以米为单位的精确距离。

## 从源码构建

每个镜像是一个独立的 Docker 构建上下文。

```bash
# 基础 locale 镜像
docker build -t postgres:18 .

# zhparser 镜像
docker build -t postgres:18-zhparser ./zhparser

# postgis 镜像
docker build -t postgres:18-postgis ./postgis
```

重新指定 PostgreSQL 主版本：

```bash
docker build --build-arg PG_CONTAINER_VERSION=18 -t postgres:18 ./zhparser
```

## 验证 zhparser 扩展

[`zhparser/zhparser.sql`](./zhparser/zhparser.sql) 是一个幂等的验证脚本。在运行的 `18-zhparser` 或 `18-postgis` 容器上执行：

```bash
docker run --rm -e POSTGRES_PASSWORD=test -p 5432:5432 postgres:18-zhparser &
psql -h localhost -U postgres -f zhparser/zhparser.sql
```

它会断言扩展安装成功、自定义词同步正常，以及中文全文检索（`ts_debug`/`to_tsvector`/`to_tsquery`）行为正确。

## 目录结构

```
.
├── Dockerfile              # 基础镜像：postgres:18 + zh_CN.UTF-8 locale + Asia/Shanghai 时区
├── zhparser/
│   ├── Dockerfile          # scws + zhparser 多阶段构建，叠加在 postgres:18 上
│   └── zhparser.sql        # 幂等的扩展验证 / 冒烟测试脚本
├── postgis/
│   └── Dockerfile          # scws + zhparser 叠加在 postgis/postgis:18-3.6 上
├── .github/workflows/
│   ├── postgres-build.yml      # 构建并发布基础镜像
│   ├── postgres-zhparser.yml   # 构建并发布 zhparser 镜像（含冒烟测试）
│   └── postgres-postgis.yml    # 构建并发布 postgis 镜像（含冒烟测试）
├── README.md               # 英文版说明
├── README_zh.md            # 本文件（中文版）
└── AGENTS.md
```

## CI/CD

GitHub Actions 在 push 到 `main`、打 `v*` 标签、以及月度定时任务时，构建、冒烟测试并发布镜像到 `ghcr.io/vnobo/postgres`。Pull
request 会构建并运行冒烟测试（执行 `zhparser.sql`）但不发布。三个 workflow 也都支持通过 `workflow_dispatch` **手动触发**
（Actions → *Run workflow*）。Docker Hub 发布是可选的，需要 `DOCKER_USERNAME` / `DOCKER_PASSWORD` Secrets。

## 常见问题（FAQ）

- **认证失败 / `role "postgres" does not exist`**：用 `-e POSTGRES_PASSWORD=...` 启动，并以
  `psql -U postgres -h localhost` 加该密码连接。
- **`CREATE EXTENSION zhparser` 报找不到**：请使用 `18-zhparser` 或 `18-postgis` 镜像（基础 `:18` 不含该扩展）。
- **中文检索无结果**：确认已创建 `chinese` 配置并做 `ADD MAPPING`（见实战章节），且查询用 `to_tsquery('chinese', ...)`
  而非普通字符串。
- **数据随容器丢失**：运行时加 `-v <卷>:/var/lib/postgresql/data`（见快速开始）。

## 致谢

本项目镜像构建于多个开源项目之上：

- [PostgreSQL](https://www.postgresql.org) —— 数据库引擎与官方 `postgres` 基础镜像。
- [PostGIS](https://postgis.net) —— 地理空间扩展与 `postgis/postgis` 基础镜像。
- [scws (SCWS)](https://github.com/hightman/scws) —— zhparser 依赖的中文分词 C 库。
- [zhparser](https://github.com/amutu/zhparser) —— PostgreSQL 中文全文解析器。

感谢它们的维护者与贡献者。

## 许可证

MIT
