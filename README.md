# Nacos Setup

一个强大的 Nacos 安装和管理工具，支持单机模式和集群模式的快速部署。

## ✨ 特性

- 🚀 **一键安装**：通过简单的命令即可完成 Nacos 的安装和配置
- 🔄 **双模式支持**：支持单机模式和集群模式
- 🎯 **智能端口管理**：自动检测端口冲突并分配可用端口
- 🔐 **自动安全配置**：自动生成 JWT Token、Identity Key 和管理员密码
- ☕ **Java 版本检测**：自动检测 Java 环境并验证版本兼容性
- 💾 **数据源配置**：支持外部数据库（MySQL/PostgreSQL）或内置 Derby
- 📦 **缓存下载**：下载的 Nacos 包会被缓存，避免重复下载
- 🌐 **全局可用**：安装后可在任何目录下使用 `nacos-setup` 命令

## 📦 安装

### 方式 1：从源码安装（推荐）

```bash
# 克隆仓库
git clone https://github.com/your-repo/nacos-setup.git
cd nacos-setup

# 安装到系统（需要 sudo 权限）
sudo bash install.sh
```

### 方式 2：一键在线安装

```bash
curl -fsSL https://your-domain.com/install.sh | sudo bash
```

### 验证安装

```bash
nacos-setup --help
```

## 🚀 快速开始

### 单机模式

```bash
# 安装默认版本（3.1.1）
nacos-setup

# 指定版本
nacos-setup -v 2.5.2

# 自定义端口和目录
nacos-setup -p 18848 -d /opt/nacos

# 后台运行
nacos-setup --detach
```

### 集群模式

```bash
# 创建 3 节点集群
nacos-setup -c prod

# 创建 5 节点集群
nacos-setup -c prod -n 5

# 加入现有集群
nacos-setup -c prod --join

# 移除节点
nacos-setup -c prod --leave 2

# 清理并重建集群
nacos-setup -c prod --clean
```

### 数据源配置

```bash
# 配置全局数据源（MySQL/PostgreSQL）
nacos-setup --datasource-conf
```

## 📖 使用说明

### 命令选项

#### 通用选项

- `-v, --version VERSION` - Nacos 版本（默认：3.1.1，最低：2.4.0）
- `-p, --port PORT` - 服务端口（默认：8848）
- `--no-start` - 安装后不自动启动
- `--adv` - 高级模式（交互式配置）
- `--detach` - 后台模式（启动后退出）
- `--datasource-conf` - 配置全局数据源
- `-h, --help` - 显示帮助信息

#### 单机模式选项

- `-d, --dir DIRECTORY` - 安装目录（默认：~/ai-infra/nacos/standalone/nacos-VERSION）
- `--kill` - 允许停止占用端口的 Nacos 进程

#### 集群模式选项

- `-c, --cluster CLUSTER_ID` - 集群标识符（启用集群模式）
- `-n, --nodes COUNT` - 集群节点数量（默认：3）
- `--clean` - 清理现有集群
- `--join` - 加入现有集群
- `--leave INDEX` - 从集群中移除指定节点

### 版本要求

- **最低版本**：Nacos 2.4.0
- **Nacos 3.x**：需要 Java 17+
- **Nacos 2.4.x - 2.5.x**：需要 Java 8+

### 安装目录结构

```
系统安装位置：
/usr/local/nacos-setup/
├── bin/
│   └── nacos-setup          # 主命令
└── lib/
    ├── cluster.sh           # 集群模式实现
    ├── standalone.sh        # 单机模式实现
    ├── common.sh            # 通用工具
    ├── port_manager.sh      # 端口管理
    ├── download.sh          # 下载管理
    ├── config_manager.sh    # 配置管理
    ├── java_manager.sh      # Java 环境管理
    └── process_manager.sh   # 进程管理

用户数据目录：
~/ai-infra/nacos/
├── standalone/              # 单机模式安装目录
│   └── nacos-VERSION/
└── cluster/                 # 集群模式安装目录
    └── CLUSTER_ID/
        ├── 0-vVERSION/     # 节点 0
        ├── 1-vVERSION/     # 节点 1
        └── cluster.conf     # 集群配置
```

## 🔧 高级功能

### 外部数据库配置

1. 配置全局数据源：

```bash
nacos-setup --datasource-conf
```

2. 按照提示输入数据库信息：
   - 数据库类型（MySQL/PostgreSQL）
   - 主机地址
   - 端口
   - 数据库名
   - 用户名和密码

3. 配置将保存在 `~/ai-infra/nacos/default.properties`

4. 后续安装会自动使用该配置

### 集群管理

#### 增量启动（Derby 模式）

集群模式使用增量式配置启动，确保 Derby 数据库的正确初始化：

```
Node 0: cluster.conf 只包含自己
Node 1: cluster.conf 包含 node0 + 自己
Node N: cluster.conf 包含 node0...node(N-1) + 自己
```

启动后自动更新所有节点的 cluster.conf 包含全部成员。

#### 节点管理

```bash
# 查看集群状态
ls -la ~/ai-infra/nacos/cluster/CLUSTER_ID/

# 手动启动节点
cd ~/ai-infra/nacos/cluster/CLUSTER_ID/0-v3.1.1
bash bin/startup.sh

# 停止节点
bash bin/shutdown.sh
```

### 端口冲突处理

脚本会自动检测端口冲突：

1. **检测到 Nacos 进程**：
   - 使用 `--kill` 参数：停止现有进程
   - 不使用 `--kill`：自动分配新端口

2. **检测到非 Nacos 进程**：
   - 自动分配可用端口

## 🗑️ 卸载

```bash
# 卸载 nacos-setup
sudo bash install.sh uninstall

# 或
sudo bash install.sh -u
```

卸载后：
- 系统命令 `/usr/local/bin/nacos-setup` 将被删除
- 安装目录 `/usr/local/nacos-setup/` 将被删除
- 用户数据 `~/ai-infra/nacos/` 不会被删除

## 📝 示例

### 示例 1：开发环境快速安装

```bash
# 安装单机 Nacos
nacos-setup

# 访问控制台
# Nacos 3.x: http://localhost:8080/index.html
# Nacos 2.x: http://localhost:8848/nacos/index.html
# 默认用户名：nacos
# 密码会在安装时显示
```

### 示例 2：生产环境集群部署

```bash
# 1. 配置外部 MySQL 数据库
nacos-setup --datasource-conf

# 2. 创建 3 节点集群
nacos-setup -c production -n 3 -v 3.1.1

# 3. 后续扩容：添加新节点
nacos-setup -c production --join

# 4. 节点下线
nacos-setup -c production --leave 3
```

### 示例 3：多环境部署

```bash
# 开发环境
nacos-setup -c dev -n 1 -p 8848

# 测试环境
nacos-setup -c test -n 2 -p 9848

# 生产环境
nacos-setup -c prod -n 3 -p 10848
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

Apache License 2.0

## 🔗 相关链接

- [Nacos 官网](https://nacos.io)
- [Nacos GitHub](https://github.com/alibaba/nacos)
- [Nacos 文档](https://nacos.io/zh-cn/docs/quick-start.html)

## 📞 支持

如有问题，请：

1. 查看 [常见问题](#常见问题)
2. 提交 [Issue](https://github.com/your-repo/nacos-setup/issues)
3. 查看 Nacos 日志：`~/ai-infra/nacos/*/logs/`

## 常见问题

### Q: 安装后找不到 nacos-setup 命令？

A: 确保 `/usr/local/bin` 在您的 PATH 中：

```bash
echo $PATH | grep /usr/local/bin
```

如果没有，添加到 `~/.bashrc` 或 `~/.zshrc`：

```bash
export PATH="/usr/local/bin:$PATH"
```

### Q: Java 版本不兼容怎么办？

A: 
- Nacos 3.x 需要 Java 17+
- Nacos 2.x 需要 Java 8+

安装正确的 Java 版本并设置 JAVA_HOME：

```bash
export JAVA_HOME=/path/to/java
export PATH=$JAVA_HOME/bin:$PATH
```

### Q: 集群模式启动失败？

A:
1. 检查 Derby 模式是否正确配置（增量启动）
2. 检查端口是否冲突
3. 查看日志：`~/ai-infra/nacos/cluster/CLUSTER_ID/*/logs/startup.log`

### Q: 如何切换到外部数据库？

A:

```bash
# 1. 配置数据源
nacos-setup --datasource-conf

# 2. 重新安装（会自动使用外部数据库）
nacos-setup -c prod --clean
```

### Q: 如何更新 Nacos 版本？

A:

```bash
# 单机模式：直接安装新版本
nacos-setup -v 3.2.0 -d /new/directory

# 集群模式：清理并重建
nacos-setup -c prod -v 3.2.0 --clean
```
