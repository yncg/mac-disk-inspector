#!/bin/bash
# ============================================================
#  磁盘空间体检 —— 双击运行
#  自动扫描磁盘占用 → 生成网页报告 → 自动在浏览器打开
#  纯系统命令，无需安装任何依赖
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="$SCRIPT_DIR/磁盘空间报告"
OUT="$REPORT_DIR/index.html"
DATA="$(mktemp -t diskscan)"
BIG="$(mktemp -t diskbig)"
mkdir -p "$REPORT_DIR"

B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'
step() { printf "  ${D}→${R} %s\n" "$1"; }

printf "\n${B}  磁盘空间体检${R}\n${D}  正在扫描，约需 1-3 分钟，请勿关闭窗口…${R}\n\n"

# ---------- 工具函数 ----------
add() { # 类别 标签 路径
  local cat="$1" label="$2" path="$3" kb
  [ -e "$path" ] || return 0
  kb="$(du -sk "$path" 2>/dev/null | awk 'NR==1{print $1+0}')"
  kb="${kb:-0}"; [ "$kb" -gt 0 ] || return 0
  printf '%s\t%s\t%s\t%s\n' "$kb" "$cat" "$label" "$path" >> "$DATA"
}
addkb() { # 大小KB 类别 标签 路径
  local kb="${1:-0}"
  [ "$kb" -gt 0 ] || return 0
  printf '%s\t%s\t%s\t%s\n' "$kb" "$2" "$3" "${4:-}" >> "$DATA"
}
human() {
  # 输入单位为 KB（1024 字节块）。
  # 输出采用 macOS 原生口径 —— 1000 进制（1 GB = 1000 MB = 10^9 字节），
  # 与 Finder 文件夹底部显示的容量、以及"关于本机"完全一致。
  awk -v k="${1:-0}" 'BEGIN{
    b = k * 1024;
    if (b >= 1000000000) printf "%.1f GB", b/1000000000;
    else if (b >= 1000000) printf "%.0f MB", b/1000000;
    else printf "%.0f KB", b/1000 }'
}
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
cat_sum() { sort -rn "$DATA" 2>/dev/null | awk -F'\t' -v c="$1" '$2==c{s+=$1} END{print s+0}'; }

# ---------- 磁盘总览 ----------
TOTAL_KB=$(df -k /System/Volumes/Data | awk 'NR==2{print $2+0}')
USED_KB=$(df -k /System/Volumes/Data  | awk 'NR==2{print $3+0}')
AVAIL_KB=$(df -k /System/Volumes/Data | awk 'NR==2{print $4+0}')

# ---------- 1/3 可直接清理 ----------
echo "${B}[1/3] 可直接清理的项目${R}"
add clean "Camtasia 录屏代理文件" "$HOME/Library/Application Support/TechSmith/Camtasia/MediaProxies"
add clean "系统与应用缓存" "$HOME/Library/Caches"
add clean "命令行缓存" "$HOME/.cache"
add clean "Quark 视频缓存" "$HOME/Library/Application Support/Quark/Cache"
add clean "Quark 更新包" "$HOME/Library/Application Support/Quark/updates"
add clean "Reqable 抓包历史" "$HOME/Library/Application Support/com.reqable.macosx"
add clean "Xcode 衍生数据" "$HOME/Library/Developer/Xcode/DerivedData"
add clean "iOS 设备备份" "$HOME/Library/Application Support/MobileSync/Backup"
add clean "应用日志" "$HOME/Library/Logs"
add clean "废纸篓" "$HOME/.Trash"

INST_KB=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  kb="$(du -sk "$p" 2>/dev/null | awk 'NR==1{print $1+0}')"
  INST_KB=$(( INST_KB + kb ))
  add clean "macOS 系统安装包" "$p"
done < <(find /Applications -maxdepth 1 -iname "Install macOS*.app" 2>/dev/null)

while IFS= read -r p; do
  add clean "MuMu 模拟器实例" "$p"
done < <(find "$HOME/Library/Application Support" -maxdepth 3 -type d -name bundles -path "*mumu*" 2>/dev/null)
step "完成"

# ---------- 2/3 你的数据 ----------
echo "${B}[2/3] 你的实际数据 / 资产${R}"
add asset "图片" "$HOME/Pictures"
add asset "影片" "$HOME/Movies"
add asset "音乐" "$HOME/Music"
add asset "文稿" "$HOME/Documents"
add asset "桌面" "$HOME/Desktop"
add asset "下载" "$HOME/Downloads"
add asset "Windows 虚拟机" "$HOME/Parallels"
add asset "文献库 Zotero" "$HOME/Zotero"
step "完成"

# ---------- 3/3 系统与开发环境 ----------
echo "${B}[3/3] 系统与开发环境${R}"
add system "第三方工具链 /usr/local" "/usr/local"
add system "Homebrew /opt/homebrew" "/opt/homebrew"
add system "开发者组件 /Library/Developer" "/Library/Developer"
add system "系统数据库 /private/var/db" "/private/var/db"
add system "LM Studio 本地模型" "$HOME/.lmstudio"
add system "应用沙盒容器" "$HOME/Library/Containers"
add system "WorkBuddy 数据" "$HOME/.workbuddy"
APPS_KB="$(du -sk /Applications 2>/dev/null | awk 'NR==1{print $1+0}')"
addkb $(( APPS_KB - INST_KB )) system "已安装应用（不含安装包）" "/Applications"
step "完成"

# ---------- 大文件 ----------
echo "${B}扫描全盘大于 1GB 的文件…${R}"
# 注意：用 du 取“实际磁盘占用”，而非 stat 的逻辑大小
# （虚拟机磁盘镜像是稀疏文件，逻辑大小可能虚高上百倍）
find "$HOME" /Applications /Library /opt /usr/local -type f -size +1G -print0 2>/dev/null |
while IFS= read -r -d '' f; do
  kb="$(du -sk "$f" 2>/dev/null | awk 'NR==1{print $1+0}')"
  [ "${kb:-0}" -ge 1048576 ] && printf '%s|%s\n' "$kb" "$f"
done | sort -t'|' -k1,1rn | head -25 > "$BIG"
step "完成"

# ---------- 生成网页 ----------
printf "${B}正在生成报告…${R}\n\n"
CAT_CLEAN=$(cat_sum clean); CAT_ASSET=$(cat_sum asset); CAT_SYSTEM=$(cat_sum system)
MAX_KB="$(sort -rn "$DATA" 2>/dev/null | head -1 | cut -f1)"; MAX_KB="${MAX_KB:-1}"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"
USED_PCT=$(( USED_KB * 100 / TOTAL_KB ))

{
cat <<'H1'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>磁盘空间体检报告</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#F4F4F2;color:#2C2C2A;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",Arial,sans-serif;line-height:1.6;padding:32px 20px 64px}
.wrap{max-width:940px;margin:0 auto}
h1{font-size:22px;font-weight:600;letter-spacing:-.2px}
.sub{color:#888780;font-size:13px;margin-top:4px}
.card{background:#fff;border:1px solid #E6E4DF;border-radius:12px;padding:20px 22px;margin-top:18px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-top:18px}
.metric{background:#fff;border:1px solid #E6E4DF;border-radius:12px;padding:16px 18px}
.metric .k{font-size:12px;color:#888780}
.metric .v{font-size:26px;font-weight:600;margin-top:2px;letter-spacing:-.5px}
.metric.clean .v{color:#C2410C}
.bar-outer{height:10px;background:#EDEBE6;border-radius:6px;overflow:hidden;margin-top:14px;display:flex}
.bar-used{background:#E24B4A;height:100%}
h2{font-size:15px;font-weight:600;margin-bottom:4px}
.note{font-size:12.5px;color:#888780;margin-bottom:14px}
.row{padding:12px 0;border-top:1px solid #F0EEEA}
.row:first-child{border-top:none}
.row-head{display:flex;align-items:baseline;gap:8px}
.dot{width:8px;height:8px;border-radius:50%;flex:0 0 8px;position:relative;top:-1px}
.lbl{font-size:13.5px;font-weight:500;flex:1;min-width:0}
.sz{font-size:13.5px;font-weight:600;font-variant-numeric:tabular-nums}
.track{height:6px;background:#F2F0EC;border-radius:4px;margin-top:7px;overflow:hidden}
.fill{height:100%;border-radius:4px}
.pth{font-size:11.5px;color:#A9A79F;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;margin-top:5px;word-break:break-all}
.c-clean .dot,.c-clean .fill{background:#D85A30}
.c-clean .sz{color:#C2410C}
.c-asset .dot,.c-asset .fill{background:#378ADD}
.c-asset .sz{color:#1D6AC4}
.c-system .dot,.c-system .fill{background:#888780}
.c-system .sz{color:#5F5E5A}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:6px}
.tab{border:1px solid #DEDCD6;background:#fff;color:#2C2C2A;border-radius:999px;padding:6px 14px;font-size:12.5px;cursor:pointer;font-family:inherit}
.tab.on{background:#2C2C2A;color:#fff;border-color:#2C2C2A}
.sum{display:flex;justify-content:space-between;align-items:baseline;padding:10px 0 2px;font-size:13px;color:#5F5E5A}
.sum b{font-size:15px}
.file{display:flex;justify-content:space-between;gap:14px;padding:9px 0;border-top:1px solid #F0EEEA;font-size:12.5px}
.file:first-child{border-top:none}
.file .f{color:#5F5E5A;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;word-break:break-all;min-width:0}
.file .s{font-weight:600;white-space:nowrap;font-variant-numeric:tabular-nums}
.legend{display:flex;gap:18px;flex-wrap:wrap;font-size:12px;color:#888780;margin-top:14px}
.legend span{display:flex;align-items:center;gap:6px}
.legend i{width:9px;height:9px;border-radius:2px;display:inline-block}
footer{margin-top:26px;font-size:12px;color:#A9A79F;text-align:center}
</style>
</head>
<body>
<div class="wrap">
  <h1>磁盘空间体检报告</h1>
<div class="sub">扫描时间 SCNTIME ｜ 容量按 macOS 原生口径（1000 进制）显示，与 Finder 一致 ｜ 数据来源：本机实时扫描</div>
H1

echo "  <div class=\"grid\">"
echo "    <div class=\"metric\"><div class=\"k\">磁盘总容量</div><div class=\"v\">$(human "$TOTAL_KB")</div></div>"
echo "    <div class=\"metric\"><div class=\"k\">已使用</div><div class=\"v\">$(human "$USED_KB")</div></div>"
echo "    <div class=\"metric\"><div class=\"k\">可用空间</div><div class=\"v\">$(human "$AVAIL_KB")</div></div>"
echo "    <div class=\"metric clean\"><div class=\"k\">可直接清理合计</div><div class=\"v\">$(human "$CAT_CLEAN")</div></div>"
echo "  </div>"
echo "  <div class=\"card\">"
echo "    <h2>空间使用率 ${USED_PCT}%</h2>"
echo "    <div class=\"bar-outer\"><div class=\"bar-used\" style=\"width:${USED_PCT}%\"></div></div>"
echo "    <div class=\"legend\">"
echo "      <span><i style=\"background:#E24B4A\"></i>已使用 $(human "$USED_KB")</span>"
echo "      <span><i style=\"background:#EDEBE6\"></i>可用 $(human "$AVAIL_KB")</span>"
echo "    </div>"
echo "  </div>"

# --- 排行图 ---
echo "  <div class=\"card\">"
echo "    <h2>占用排行</h2>"
echo "    <div class=\"note\">按扫描到的重点目录占用大小排序，条形长度相对于最大值。</div>"
sort -rn "$DATA" 2>/dev/null | head -22 | while IFS=$'\t' read -r kb cat label path; do
  [ -n "${kb:-}" ] || continue
  pct=$(( kb * 100 / MAX_KB )); [ "$pct" -lt 2 ] && pct=2
  echo "    <div class=\"row c-${cat}\">"
  echo "      <div class=\"row-head\"><span class=\"dot\"></span><span class=\"lbl\">$(esc "$label")</span><span class=\"sz\">$(human "$kb")</span></div>"
  echo "      <div class=\"track\"><div class=\"fill\" style=\"width:${pct}%\"></div></div>"
  [ -n "$path" ] && echo "      <div class=\"pth\">$(esc "$path")</div>"
  echo "    </div>"
done
echo "  </div>"

# --- 分类明细 ---
echo "  <div class=\"card\">"
echo "    <h2>分类明细</h2>"
echo "    <div class=\"note\">点击按钮切换分类查看。</div>"
echo "    <div class=\"tabs\">"
echo "      <button class=\"tab on\" data-f=\"all\">全部</button>"
echo "      <button class=\"tab\" data-f=\"clean\">可直接清理 · $(human "$CAT_CLEAN")</button>"
echo "      <button class=\"tab\" data-f=\"asset\">实际数据/资产 · $(human "$CAT_ASSET")</button>"
echo "      <button class=\"tab\" data-f=\"system\">系统与开发环境 · $(human "$CAT_SYSTEM")</button>"
echo "    </div>"
echo "    <div id=\"list\">"
sort -rn "$DATA" 2>/dev/null | while IFS=$'\t' read -r kb cat label path; do
  [ -n "${kb:-}" ] || continue
  echo "      <div class=\"row c-${cat}\" data-c=\"${cat}\"><div class=\"row-head\"><span class=\"dot\"></span><span class=\"lbl\">$(esc "$label")</span><span class=\"sz\">$(human "$kb")</span></div><div class=\"pth\">$(esc "$path")</div></div>"
done
echo "    </div>"
echo "    <div class=\"sum\"><span>可清理项目合计</span><b>$(human "$CAT_CLEAN")</b></div>"
echo "  </div>"

# --- 大文件 ---
if [ -s "$BIG" ]; then
  echo "  <div class=\"card\">"
  echo "    <h2>全盘大于 1GB 的文件 Top $(wc -l < "$BIG" | tr -d ' ')</h2>"
  echo "    <div class=\"note\">这些是单个体积最大的文件，通常也是清理收益最高的目标。</div>"
  while IFS='|' read -r kb f; do
    [ -n "${kb:-}" ] || continue
    printf "    <div class=\"file\"><span class=\"f\">%s</span><span class=\"s\">%s</span></div>\n" "$(esc "$f")" "$(human "$kb")"
  done < "$BIG"
  echo "  </div>"
fi

cat <<'H2'
  <footer>
    由「磁盘空间体检」生成 · 双击 .command 文件可随时重新扫描<br>
    本报告仅为只读扫描结果，不会自动清理任何文件
  </footer>
</div>
<script>
document.querySelectorAll('.tab').forEach(function(t){
  t.addEventListener('click', function(){
    document.querySelectorAll('.tab').forEach(function(x){ x.classList.remove('on'); });
    t.classList.add('on');
    var f = t.getAttribute('data-f');
    document.querySelectorAll('#list .row').forEach(function(r){
      r.style.display = (f === 'all' || r.getAttribute('data-c') === f) ? '' : 'none';
    });
  });
});
</script>
</body>
</html>
H2
} > "$OUT"

sed -i '' "s/SCNTIME/$NOW/" "$OUT"

rm -f "$DATA" "$BIG"

echo "${G}✓ 报告已生成：${R}$OUT"
printf "${B}  正在打开浏览器…${R}\n\n"
open "$OUT"
sleep 1
