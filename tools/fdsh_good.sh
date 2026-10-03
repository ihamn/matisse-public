#!/system/bin/sh
# fdsh_good.sh — 占位 fd 3..9 (LF), 让 exploit 的 KO 预开落到 fd 10 而非常被 churn 的 3
KO=${KO_PATH:-/data/local/tmp/ko_v330.ko}
exec 3<$KO
exec 4<$KO
exec 5<$KO
exec 6<$KO
exec 7<$KO
exec 8<$KO
exec 9<$KO
exec "$@"
