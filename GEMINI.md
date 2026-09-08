# 📜 DJIToDrive 项目宪法与物理边界规约 (Project Constitution & Security Protocol)

> 📌 **项目名称**：`DJIToDrive` (DJI 一键导入 Google Drive)
> 📁 **物理死锁工作区**：`/Users/qianliangjun/Desktop/DJI一键导入google drive`
> 🛡️ **隔离级别**：Worker Project 物理死锁（Strict Working Directory Isolation）

---

## 一、 物理边界与跨界死锁隔离 (Physical Boundary Isolation)

1. **绝对工作区限制**：
   - Agent 的全部活动范围死锁在当前工作区根目录 `/Users/qianliangjun/Desktop/DJI一键导入google drive`。
   - 严禁读取、创建、编辑任何其他项目的代码与文件；
   - 严禁执行指向其他工作区目录的终端命令。
2. **唯一合法授权令牌**：
   - 动工前必须严格呈递「改动五问」；
   - 唯一合法动工授权令牌为 **`0`** 或 **`可以编程`**，其他任何表述一律拒绝执行并提示用户。

---

## 二、 凭据安全与 Keychain 强制令 (Security & Keychain Mandate)

1. **零明文密码/Token 规范**：
   - 严禁将 Google Cloud Client Secret、Access Token、Refresh Token 以明文形式硬编码在代码、测试用例或任何本地 json/plist 配置文件中。
   - 必须通过 macOS 原生 `Security.framework`（Keychain Services API）进行存储与检索，使用 `kSecClassGenericPassword` 服务标识。
2. **防污染与 Git 物理屏蔽**：
   - `.gitignore` 必须永久屏蔽所有证书、钥匙、备份与临时构建目录。

---

## 三、 代码工程质量铁律 (Engineering Standards)

1. **行数上限**：任何 Swift 源码物理行数严禁超过 **800 行**。
2. **AI 注释头**：所有源码文件首行必须包含结构化「文件职责」AI 注释。
3. **官方构建令**：构建与测试必须严格使用官方 `swift build` 与 `swift test` 命令，禁止裸 `swiftc`。
4. **审计追踪**：每次代码变动后，必须强制更新 `DEV_LOG.md`。

---

## 四、 灾备与五星归档机制 (Disaster Recovery & 5-Star Milestone)

1. **高频指令 1**：极速打包项目到 `backups/backup_YYYYMMDD_HHmm.tar.gz`。
2. **高频指令 7**：跨账号一键全景交接，更新 `HANDOFF.md` 与生成 4合1 归档包。
3. **五星里程碑**：重大模块跑通或重构前，生成带 `milestone_5star_` 前缀的永久归档，免于滚动清理。
