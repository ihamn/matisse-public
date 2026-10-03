# matisse-public — Redmi K50 Pro (MT6983) / kernel 5.10.209 提权与 KernelSU 装载记录

> **English TL;DR** — A fully documented, from-scratch writeup + toolkit for obtaining `uid=0` with a
> kernel SID on a **Redmi K50 Pro (matisse, MediaTek MT6983, kernel 5.10.209)** and loading **KernelSU via
> LKM late-load**, without unlocking the bootloader. Full source is published on purpose: a root tool you
> cannot audit is a root tool you should not trust.

---

## 为什么把源码全部公开

这个仓库做的事是 **提权**。任何"能给你 root"的闭源工具，都应当被怀疑：
它同样能悄悄做别的事，而你无法验证。所以我们**主动公开全部源码、日志格式、失败过程与复现步骤**，
包括：

- 完整的 exploit 源码（`payload_src/`）—— 你可以逐行读、自己编译、比对哈希
- 全部脚本与判据（`tools/`、`ksu_persist.sh`）—— 包括**失败的那些尝试**
- 真实的内核 panic 摘录（`evidence/`）—— 证明我们遇到的崩机与其根因
- 明确的**适用边界与免责声明**（见下）

**不包含**：任何设备标识（序列号 / MAC）、个人数据、第三方未授权代码。

---

## 成果（可复核）

| 项 | 实测证据 |
|---|---|
| `uid=0` | `su -c id` → `uid=0(root) gid=0(root) groups=0(root)` |
| **kernel SID** | 同一行的 `context=u:r:ksu:s0` |
| **KernelSU 已加载** | `/proc/modules` → `kernelsu … - Live` |
| 装载器日志 | `/data/local/tmp/ksu_go.log` → `uid=0` / `load_policy rc=0` / `late-load rc=0` / `modules: 1` |
| 设备未崩机 | 全程同一 `boot_id`，`uptime` 连续增长 |

完整战报：[WIN_20261003_1620_uid0_kernelsu.md](WIN_20261003_1620_uid0_kernelsu.md)

---

## 它做了什么（高层）

1. **R 轮**：在 `pselect` 的 `fd_set` 上做堆布局，配合 `rt_waiter` 释放后的悬垂 `pi_blocked_on`
   触发 `rt_mutex_adjust_prio_chain` 走链，落到一个受控写入（写 `task->real_cred`）。
2. **E5 轮**：把 SELinux 的 enforcing 清零（Per-Android 的 `enforcing-8` 写），进入 Permissive。
3. **C 轮**：写 `task->cred`（真正的 uid=0 + kernel SID）。
4. **gate 分支**（本仓库的关键补丁）：在**真正拿到 uid=0** 的那一刻，
   `system("sh /data/local/tmp/ksu_go.sh &")` —— 用官方 userspace 装载器 `ksud late-load`
   把 KernelSU 装进内核（绕开 `finit_module` 的 fd 被 churn / SELinux 拒绝问题）。
5. **HOLD**（`PSELECT_HOLD=1`）：持毒进程**永不退出**（否则 `_exit → mm teardown → lock_page_memcg`
   必崩；而它此时 `cred == init_cred`，被 SIGKILL 还会引发 `Attempted to kill init` panic）。

---

## 快速开始

### 在电脑上（USB adb 驱动，最完整）

```bash
git clone https://github.com/ihamn/matisse-public.git && cd matisse-public
# 依赖：adb（自备 platform-tools）、bash、一部已开启 USB 调试的 matisse
bash tools/win_loop.sh 12     # 连抽最多 12 轮，命中判据即停手
# 注意: 电脑侧需要自备 adb (Google platform-tools), 本仓库不分发
# 判据：/proc/modules 出现 kernelsu  或  /data/local/tmp/ksu_go.log 里 late-load rc=0
```

### 在手机上（Termux + Shizuku，无需电脑）

见 [TERMUX_ONE_ROUND_HOWTO.md](TERMUX_ONE_ROUND_HOWTO.md)：

```bash
bash tools/termux_one_round.sh     # 只在当前 boot 内跑一轮; 绝不自己重启
```

> 注意：Termux 是普通 App 身份，**必须**通过 Shizuku 的 `rish` 拿到 shell 身份才能开火 ✓

---

## 目录结构

```
ksu_persist.sh              主驱动：部署/体检/R/E5/C/ksud/取证（含全部判据与安全阀）
tools/                      编排与取证工具（连抽、尸检、pstore 抢占、Termux 入口等）
payload_src/mt87_build/     exploit 源码（C）与构建信息（含 kernel target 偏移）
ko_patched/                 KernelSU LKM 变体（GPL-3.0 衍生，见 NOTICE）
evidence/                   脱敏后的真实内核 panic 摘录（pc / Call trace / Kernel Offset）
docs/                       过程文档与复盘
```

---

## 适用边界（重要）

- **机型/内核**：Redmi K50 Pro（matisse / MT6983）+ **5.10.209**（`5.10.209-android12-9-…`）。
  **其它内核版本几乎必然失败甚至变砖**。
- **前提**：设备是你自己的、已开启 USB 调试 / Shizuku；**无需解锁 bootloader**。
- **稳定性**：R/C 两步存在**结构性概率崩机**（伪页在 rmap/memcg 回收路径被解引用等，见 `evidence/`）。
  崩机会自动重启，**一般不损坏数据**，但请自行评估风险。
- **持久化**：LKM late-load 是**每 boot 一次**；重启后需重跑。真正的开机持久化需要刷入修补过的
  boot 镜像（即需要解锁 bootloader），本仓库不提供、也不建议。

## 免责声明 / 许可

- 仅供**自有设备的安全研究与学习**。请勿用于未授权设备；由此产生的任何后果由使用者自负。
- 本仓库以 **GPL-3.0** 发布；其中 KernelSU 及其衍生二进制（`ko_patched/`）遵循 KernelSU 的
  **GPL-3.0** 许可，版权归 KernelSU 项目所有（见 `NOTICE`）。
- 第三方项目（如 GhostLock、CyberMeowfia 的研究仓库）**未包含**在本仓库中；如需请自行获取并遵守其许可。
- 若你是相关厂商的安全团队并希望协调披露，请开 issue。
