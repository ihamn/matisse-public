# NOTICE — 第三方组件与归属

本仓库包含或引用了以下第三方工作。**版权归各自作者所有**，本仓库仅按各自许可使用。

## 1. KernelSU（GPL-3.0）

- 项目：KernelSU — https://github.com/tiann/KernelSU
- 许可：**GNU GPL-3.0**
- 本仓库中的相关部分：
  - `ko_patched/*.ko` —— 基于 KernelSU 的 LKM 构建，并按本机型内核（5.10.209 / KMI android12-5.10）做过 vermagic / `__versions` 处理的**衍生二进制**
  - 脚本中调用的 `ksud late-load`（`ksud` 二进制**未随本仓库分发**，请从 KernelSU 官方发行版获取）
- 因此：**本仓库整体以 GPL-3.0 发布**（见 `LICENSE`）。若你分发本仓库或其衍生作品，须遵守 GPL-3.0。

## 2. payload_src/ 的来源与许可（**不是全部原创，务必阅读**）

`payload_src/mt87_build/` 是在若干**公开的 CVE 研究 / PoC** 之上做的机型移植、补丁与插桩。
**各文件版权归其原始作者所有**；上游未显式声明许可的部分，请以其原始仓库条款为准。

逐文件来源表见 **[`payload_src/PROVENANCE.md`](payload_src/PROVENANCE.md)**。要点：

- `src/kernelsnitch/*` —— 来自 **KernelSnitch**（KASLR 侧信道研究）
- `src/preload.c` / `src/su_daemon.c` / `src/su_blob.S` —— 来自公开的 GhostLock / CVE-2026-43499 系 PoC
- `src/main.c` / `slide.c` / `fops.c` / `pipe.c` / `root.c` / `util.c` / `target*.h` —— 上游骨架 + 本仓库的机型移植与补丁（GPL-3.0 原创部分）

> **如果你是上游作者**，认为上述转载/修改有问题：开 issue，我们**立即更正或移除**（见 `SECURITY.md` §4）。

## 3. 未包含的第三方内容（仅致谢/参考）

- **Google platform-tools (adb)** —— 请从 Google 官方获取，本仓库不分发
- **KernelSU 的 `ksud` 与管理器 APK** —— 请从 KernelSU 官方发行版获取
- 设备内核符号（`kallsyms`）、厂商内核镜像（`*.elf` / `*.img`）—— **属于厂商 IP，本仓库不包含**
- 与本机型无关的其它 GhostLock 资产（`profiles.zip` 等）—— 未包含

## 4. 本仓库原创部分

除上述之外，`ksu_persist.sh`、`tools/`、文档与证据整理，以及 `payload_src/` 中本仓库新增的修改，
版权归本仓库作者所有，同样以 **GPL-3.0** 授权。

## 5. 免责

见 `README.md` 末尾的免责声明与 `SECURITY.md`。本研究仅面向**自有设备**的安全分析与学习。
