# v1.0-win-20261003 — 首次完整通关（uid 0 + kernel SID + KernelSU late-load）

## 里程碑
- **机型**：Redmi K50 Pro（matisse / MT6983）· HyperOS 2.0.6.0 · 内核 **5.10.209** · **BL 未解锁**
- **结果**：`uid=0(root) context=u:r:ksu:s0`，`/proc/modules` → `kernelsu … - Live`
- **过程**：全程同一 `boot_id`，无 panic；`ksu_go.log` 里 `load_policy rc=0` / `late-load rc=0`

## 这一版包含什么
| 内容 | 位置 |
|---|---|
| exploit 源码（含 gate/HOLD 补丁） | `payload_src/mt87_build/` |
| 构建配方 + 期望 sha256 + 自检命令 | `payload_src/mt87_build/BUILD_INFO.txt` |
| 主驱动（部署/体检/R/E5/C/ksud/取证） | `ksu_persist.sh` |
| 编排与取证工具（连抽、尸检、pstore 抢占、Termux 入口） | `tools/` |
| 真实内核 panic 摘录（脱敏） | `evidence/` |
| KernelSU LKM 对照变体（GPL-3.0 衍生） | `ko_patched/` + `ko_patched/README.md` |
| 产物哈希 | `SHA256SUMS` |
| 归属与许可 | `NOTICE.md` / `payload_src/PROVENANCE.md` |
| 安全、副作用与披露 | `SECURITY.md` |

## 关键技术点（本仓库原创或重点整理）
1. **R → E5 → C 三步的真实时序与判据**：C 阶段窗口从 20s 放宽到 **45s** 后，风暴才装得进窗口。
2. **gate 补丁**：在**真正拿到 uid=0** 的那一刻（`mt47` gate），以 root 启动官方 userspace 装载器
   `ksud late-load` —— 绕开 `finit_module` 的 fd churn（`EBADF`）与 SELinux 拒绝。
3. **HOLD（`PSELECT_HOLD=1`）**：持毒进程**永不退出**，消除 `_exit → mm teardown → page_remove_rmap/`
   `lock_page_memcg` 这一整类 panic（`evidence/` 里有对应现场）。

## 已知限制（务必阅读 `SECURITY.md`）
- **每 boot 一次**：LKM late-load 非持久，重启后需重跑；真正开机持久化需要解锁 BL，本仓库不提供。
- **结构性概率崩机**：R/C 两步可能 panic（自动重启，一般不损坏数据，但会留下坏 inode 等痕迹）。
- **副作用**：安装 su 守护进程到 `/apex/com.android.virt/bin/su`、替换壁纸、SELinux 置 Permissive、
  主机名改 `glroot`。
- **适用面极窄**：仅 5.10.209 本机型；其它内核版本几乎必然失败甚至变砖。

## 许可
本仓库以 **GPL-3.0** 发布；KernelSU 及其衍生二进制（`ko_patched/`）遵循 KernelSU 的 GPL-3.0。
第三方与派生代码的归属见 `NOTICE.md` 与 `payload_src/PROVENANCE.md`。
