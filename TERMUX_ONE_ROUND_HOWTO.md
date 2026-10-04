# 手机侧「打一轮」使用说明（Termux + Shizuku）

> 2026-10-03 起：**手机上不做跨 boot 状态机**。脚本只在**当前 boot 内跑一轮**就结束，
> **绝不自己重启**；重启由你自己决定，重启后再跑一次脚本即可。✓

## 一、一次性准备（每台手机只做一次）
1. 装好 **Shizuku**（你已装 ✓）与 **Termux** + Termux:Boot（可选）
2. 打开 Shizuku → **启动服务**（方式二选一）
   - 用**无线调试**启动（Android 11+，免 root）：`设置 → 开发者选项 → 无线调试` 打开 → Shizuku 里按提示配对
   - 或在你**当前已有 root 的情况下**用 root 启动（注意：重启后 root 没了，就回到无线调试方式）
3. Shizuku 里点「**使用此应用**」→ 把 **`rish`** 复制到 Termux 的 `~/`
   （脚本会自动在 `~/`、`~/rish/`、`/sdcard/Download/` 找它 ✓）

4. **构建 payload**：本仓库只发布**源码**，不含 `bin/mt87/preload.so`。
   按 [`payload_src/mt87_build/BUILD_INFO.txt`](payload_src/mt87_build/BUILD_INFO.txt) 的配方自行编译（Termux clang 即可），
   把产物放到 `bin/mt87/preload.so`（脚本第 0 步会提示路径）。SHA256 见 [`SHA256SUMS`](SHA256SUMS)。

## 二、每次要提权时（重启后）
在 Termux 里：
```bash
cd ~/matisse-public 2>/dev/null || git clone https://github.com/ihamn/matisse-public.git ~/matisse-public
cd ~/matisse-public  # 公开版: 不访问任何远端仓库, 无需 git pull; 证据只写本地 logs_raw/ (已被 .gitignore 忽略)
bash tools/termux_one_round.sh
```
- 脚本会自己检查：**本 boot 已经是 root ⇒ 直接退出**（不白打）✓
- 否则跑一轮：**R → 退场 285s → E5 → C（45s 窗口，单发）**，约 8-12 分钟 ✓
- 期间**手机有概率崩机重启**（已知的结构性风险 ✓）⇒ 崩机后重跑一次即可 ✓
- 结束时会给结论：
  - `★★★★★★★★ 成功` ⇒ 打开 **KSU 管理器**应显示**越狱模式** ✓
  - `本轮未成功` ⇒ **手动重启手机**，再跑一次 ✓

## 三、成功判据（只看实测）
| 判据 | 怎么看 |
|---|---|
| **kernelsu 在内核** | `grep -E '^(ksu|kernelsu)' /proc/modules` 或脚本自己报 ✓ |
| **装载器日志** | `cat /data/local/tmp/ksu_go.log` ⇒ 应有 `uid=0`、`load_policy rc=0`、`late-load rc=0`、`modules: 1` ✓ |
| **可用 root** | Termux 里 `rish -c 'su -c id'`（或任意 root App）⇒ 期望 `uid=0(root) ... u:r:ksu:s0` ✓ |
| **管理器** | KSU 管理器显示**越狱模式** ✓ |

## 四、注意事项（血的教训）
1. **成功后别急着重启**：LKM late-load 是**每 boot 一次**，重启即丢，需重跑 ✓
2. **绝不 `pkill` / `kill -9` 这些进程**：HOLD 期持毒进程的 cred 就是 `init_cred`，
   杀它会触发 `Kernel panic - Attempted to kill init!` ✓（脚本已把所有 kill 路径拔掉 ✓）
3. **`rish` 必须活着**：Shizuku 被冻结/未启动 ⇒ 脚本会明确报错并退出 ✓
4. **崩机后 30-60 秒**等它自己起来再重跑（脚本启动时也会读 boot_id ✓）

## 五、为什么手机上必须用 Shizuku
Termux 自己是**普通 App 身份**（uid 10xxx），而 exploit 必须跑在 **shell 域**（uid 2000、无 seccomp）✗
⇒ 这正是 `rish`（Shizuku）提供的身份 ✓ —— 和电脑上 `adb shell` 是同一回事 ✓