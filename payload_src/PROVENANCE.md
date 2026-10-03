# PROVENANCE — payload_src/ 逐文件来源

> 这份文件是为了说清一件事：**`payload_src/` 不是全部原创**。
> 它是在若干公开的 CVE 研究 / PoC 之上做的**机型移植 + 补丁 + 插桩**。
> 版权归各文件原始作者所有；若上游未显式声明许可，请以其原始仓库条款为准。

| 文件 / 目录 | 来源 | 本仓库做了什么 | 许可 |
|---|---|---|---|
| `src/kernelsnitch/*.h` | **KernelSnitch**（KASLR 侧信道研究） | 基本原样使用，作为 futex 侧信道工具 | 上游未标注 → 以上游仓库为准 |
| `src/preload.c` | 公开的 GhostLock / CVE-2026-43499 系 PoC 思路 | 机型适配、gate/HOLD 相关改动 | 上游未标注 → 以上游仓库为准 |
| `src/su_daemon.c`、`src/su_blob.S` | 同上（嵌入式 su 守护进程） | 保留并随载荷编译 | 上游未标注 → 以上游仓库为准 |
| `src/wallpaper_blob.S`、`assets/wallpaper.webp` | 本仓库作者 | 演示用壁纸 | 随仓库（GPL-3.0）|
| `src/main.c` | 上游骨架 + 本仓库作者 | R/E5/C 编排、`mt47` gate 启动 `ksud`、`PSELECT_HOLD`、KO fd 修复、环境旋钮 | GPL-3.0（原创部分）|
| `src/slide.c`、`src/fops.c`、`src/pipe.c`、`src/root.c`、`src/util.c`、`src/target.h`、`src/targets/*` | 上游骨架 + 本仓库作者 | 机型偏移、几何、毒链生命周期补丁 | GPL-3.0（原创部分）|
| `Makefile` | 本仓库作者 | 可复现构建（Termux clang / NDK 均可） | GPL-3.0 |

## 处理原则
- 我们**不主张**对上游代码的版权；本仓库只主张自己新增的修改与编排部分。
- 若你是上游作者且不同意上述转载/修改方式：**开 issue，我们立即更正或移除相应文件**（见 `SECURITY.md` §4）。
- 想要商用/再分发的第三方：请回到**上游**确认许可，本仓库的 GPL-3.0 不能覆盖上游的原始条款。
