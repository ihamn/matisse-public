# NOTICE — 第三方组件与归属

本仓库包含或引用了以下第三方工作。**版权归各自作者所有**，本仓库仅按各自许可使用。

## 1. KernelSU（GPL-3.0）

- 项目：KernelSU — https://github.com/tiann/KernelSU
- 许可：**GNU GPL-3.0**
- 本仓库中的相关部分：
  - `ko_patched/*.ko` —— 基于 KernelSU 的 LKM 构建并按本机型内核（5.10.209 / KMI android12-5.10）
    做过 §vermagic/`__versions` 处理的**衍生二进制**
  - 脚本中调用的 `ksud late-load`（`ksud` 二进制**未随本仓库分发**，请从 KernelSU 官方发行版获取）
- 因此：**本仓库整体以 GPL-3.0 发布**（见 `LICENSE`）。若你分发本仓库或其衍生作品，须遵守 GPL-3.0。

## 2. 未包含的第三方内容（仅致谢/参考链接）

以下项目在开发过程中被参考或用于对照实验，**未包含在本仓库内**，请自行获取并遵守其许可：

- **GhostLock**（Android 提权研究）—— 仅在早期评估中被对照使用
- **CyberMeowfia / security-research**、**CVE 参考实现**等 —— 仅作 CVE 机制对照
- **Google platform-tools (adb)** —— 不在本仓库内；请从 Google 官方获取
- 设备内核符号（`kallsyms`）、厂商内核镜像（`*.elf`/`*.img`）—— **属于厂商 IP，本仓库不包含**

## 3. 本仓库原创部分

除上述之外，`ksu_persist.sh`、`tools/`、`payload_src/`、文档与证据整理，
版权归本仓库作者所有，同样以 **GPL-3.0** 授权。

## 4. 免责

见 `README.md` 末尾的免责声明与 `SECURITY.md`。本研究仅面向**自有设备**的安全分析与学习。
