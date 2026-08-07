#!/bin/bash
###############################################################################
# 자동 셋업 등록기 (이 스크립트만 한 번 실행하면 끝)
#
# 사용법:
#   sudo bash install_autosetup.sh
#
# 등록되는 것:
#   /usr/local/bin/jetson_setup.sh            실제 셋업 스크립트
#   /usr/local/bin/jetson_setup_watch.sh      진행상황 터미널
#   /etc/systemd/system/jetson-setup.service  부팅 시 자동 실행
#   /etc/xdg/autostart/...watch.desktop       로그인 시 진행상황 창
###############################################################################

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "root 권한이 필요합니다. 다음처럼 실행하세요:"
    echo "   sudo bash install_autosetup.sh"
    exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# 필요한 파일이 모두 같은 폴더에 있는지 먼저 확인
# ---------------------------------------------------------------------------
MISSING=0
for f in jetson_setup.sh jetson_setup_watch.sh \
         jetson-setup.service jetson-setup-watch.desktop; do
    if [ ! -f "$DIR/$f" ]; then
        echo "  [없음] $f"
        MISSING=1
    fi
done

if [ "$MISSING" = "1" ]; then
    echo ""
    echo "============================================================"
    echo " 필요한 파일이 빠져 있습니다."
    echo ""
    echo " 아래 5개 파일이 모두 같은 폴더에 있어야 합니다:"
    echo "   install_autosetup.sh   (지금 실행한 파일)"
    echo "   jetson_setup.sh"
    echo "   jetson_setup_watch.sh"
    echo "   jetson-setup.service"
    echo "   jetson-setup-watch.desktop"
    echo ""
    echo " 현재 폴더: $DIR"
    echo " 파일을 다시 내려받은 뒤 실행하세요."
    echo "============================================================"
    exit 1
fi

echo "[1/5] 셋업 스크립트 복사..."
install -m 755 "$DIR/jetson_setup.sh"       /usr/local/bin/jetson_setup.sh
install -m 755 "$DIR/jetson_setup_watch.sh" /usr/local/bin/jetson_setup_watch.sh

echo "[2/5] systemd 서비스 등록..."
install -m 644 "$DIR/jetson-setup.service" /etc/systemd/system/jetson-setup.service

echo "[3/5] 진행상황 표시 자동시작 등록..."
mkdir -p /etc/xdg/autostart
install -m 644 "$DIR/jetson-setup-watch.desktop" /etc/xdg/autostart/jetson-setup-watch.desktop

echo "[4/5] 이전 완료 기록 제거 (새로 실행되도록)..."
rm -f /var/lib/jetson_setup.done

echo "[5/5] 서비스 활성화..."
systemctl daemon-reload
systemctl enable jetson-setup.service

cat <<'MSG'

============================================================
 등록 완료!

 이제 재부팅하면 셋업이 자동으로 시작됩니다.
 화면에 진행상황 터미널이 자동으로 뜨고, 모든 설치가
 끝나면 스스로 재부팅한 뒤 다시는 실행되지 않습니다.

 (랜선이 연결되어 있어야 합니다)

 진행상황을 따로 보려면:
   tail -f /var/log/jetson_setup.log
============================================================

MSG

read -p "지금 바로 재부팅할까요? [y/N] " ans
case "$ans" in
    y|Y) echo "재부팅합니다..."; reboot ;;
    *)   echo "나중에 'sudo reboot' 하면 셋업이 시작됩니다." ;;
esac