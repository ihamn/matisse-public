# SECURITY — 安全、副作用与披露

## 0. 一句话
本仓库是一份**针对自有设备**的内核提权研究记录。它会给你的设备 root —— 请先读完这一页再动手。

## 1. 给使用者的警告（重要）
1. **不要运行来历不明的 root 包**。任何能给你 root 的东西，同样能在你不知情时做别的事。
   本仓库的立场是：源码必须公开可审计（见 README）。若你只想「一键」，请先想清楚你把内核执行权交给了谁。
2. **本仓库的二进制请先自行核验**：`SHA256SUMS` 是本仓库发布产物的哈希；
   exploit 产物（`preload.so`）的构建配方与期望 sha256 见 `payload_src/mt87_build/BUILD_INFO.txt`。
   最保险的做法是**只使用源码自行编译**。
3. **不要在主力机 / 装了银行与支付类 App 的机器上测试**。本链存在结构性概率崩机（见 README 适用边界），并有下述副作用。
4. **仅用于你自己的设备**。未授权设备上的使用可能违法。

## 2. 已知副作用（实测，务必知情）
| # | 副作用 | 落点 / 备注 |
|---|---|---|
| 1 | 安装一个 su 守护进程 | `/apex/com.android.virt/bin/su`（并写 `/data/local/tmp/su`）|
| 2 | **替换当前壁纸** | 原图备份到 `/data/system/users/0/wallpaper_orig` |
| 3 | SELinux 置为 Permissive | 重启恢复 Enforcing |
| 4 | 主机名改为 `glroot` | 作为「C 轮已落地」的外部信标，重启恢复 |
| 5 | 概率性内核 panic（自动重启） | 伪 `struct page` 在 rmap/memcg 回收路径被解引用等；见 `evidence/` |

## 3. 已知风险点（研究者）
- `PSELECT_HOLD=1` 的进程**永不退出**，且此时其 `cred == init_cred`：**不要 SIGKILL 它**
  （会触发 `Attempted to kill init` panic），要清理请重启设备。
- `finit_module` 路线在本机型被自身进程的 fd churn 打坏（`EBADF`）；本仓库改走 `ksud late-load`。
- 崩溃会留下**坏 inode / 设置被重置**等文件系统损伤（不弹窗，只在访问时暴露）。

## 4. 报告问题 / 协调披露
- 一般性问题：直接开 **GitHub Issue**（附 `uname -r`、内核 panic 摘录、复现命令）。
- **上游归属问题**：若你是被引用项目（如 KernelSnitch / GhostLock / CVE-2026-43499 相关）的作者，认为本仓库的归属或再分发有问题，请开 issue 说明，我们会**立即更正或移除相关文件**。
- 厂商安全团队：欢迎通过 issue 联系协调披露。

## 5. 许可
本仓库以 **GPL-3.0** 发布（见 `LICENSE`）；第三方组件与派生代码的许可见 `NOTICE.md`。
