# ko_patched/ — KernelSU LKM 变体说明

> 这些 `.ko` 是 **KernelSU 的 LKM 构建的衍生物**（GPL-3.0，见 `../NOTICE.md`），
> 用于**直连 `finit_module` 路线的实验与对照**。
>
> ⚠️ **本仓库实测通关的路线不是 finit**，而是 `ksud late-load`
> （`ksud` 自带内嵌模块，**未随本仓库分发**）。在本机型上，finit 路线实测会失败
> （`EBADF`：预开 fd 被自身进程克隆 churn；或 `EACCES/ENOENT`）。这里的变体仅供研究对照。

| 文件 | 大小 | 是什么 | 何时用 |
|---|---|---|---|
| `v330_emptyver.ko` | 349,936 B | **KernelSU 3.3.0 官方 LKM**，`__versions` 段计数清零（跳 CRC 校验） | 想用 finit 直连官方模块时（首选对照）|
| `v330_patched.ko` | 349,936 B | 同上 + **vermagic 修补**为本机（`5.10.209-android12-9-…`）| 内核 `check_modinfo` 卡 vermagic 时对照 |
| `ksu_v2_emptyver.ko` | 152,712 B | 早期自建 GKI209 v2 模块（源 `kernelsu_gki209_v2.ko` sha `386a0842`），`__versions` 4096 → 0 | 小体积对照；历史记录里曾用它验证「空 CRC 段」 |
| `ksu_gki209_v2_patched.ko` | 152,712 B | 同上 + vermagic 修补 | 同上，卡 vermagic 时 |
| `preflight_emptyver.ko` | 8,896 B | **诊断探针**（`__versions` 128 → 0）：只做最小 init 并打印，用来判断「finit 这条路到底通不通」 | 排查 finit 失败原因时，先加载它 |
| `preflight_patched.ko` | 8,896 B | 探针 + vermagic 修补 | 同上 |

## 两个修补手段（本仓库如何做的）
1. **空 `__versions`**：保留 section header，把 `sh_size` 置 0 ⇒ 内核做 CRC 索引时为空，
   跳过 `CONFIG_MODVERSIONS` 的符号校验（只会 warn-once / `TAINT_FORCED_MODULE`）。
2. **vermagic 同长度字符串替换**：把模块里的 vermagic 改成目标内核字符串（本例 `5.10.209`），
   使 `check_modinfo` 的严格比较通过（或配合 `finit_module(...,3)` 的 IGNORE_VERMAGIC/IGNORE_MODVERSIONS 位）。

## 实测结论（避免重复踩坑）
- `finit_module(fd,"",0)` 在本机型 → `EBADF(9)`（fd 被 exploit 自身的 prep clone 冲掉）或 `EACCES/ENOENT`；
  换成 v3.3.0 空 `__versions` 版仍为 `errno=2`。
- 走通的路线是：**在 gate 处以真 uid=0 执行 `ksud late-load --kmi android12-5.10`**（见 `../README.md`）。
