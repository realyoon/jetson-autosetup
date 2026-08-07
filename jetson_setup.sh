#!/bin/bash
###############################################################################
# Jetson Nano 기본 세팅 완전 자동화 스크립트
#   "젯슨나노설정_기본세팅.pdf" 의 모든 단계를 자동 수행합니다.
#
#   부팅 시 systemd 서비스로 1회 자동 실행되며, 완료 후 스스로 비활성화됩니다.
#   랜선이 연결되어 있다는 전제로 동작합니다.
###############################################################################

# ---------------------------------------------------------------------------
# 설정 스위치 (1=설치, 0=건너뜀)  필요 없으면 0으로 바꾸세요
# ---------------------------------------------------------------------------
SWAP_SIZE=6G              # 스왑 크기
INSTALL_VSCODE=1          # VSCode + 확장(Python/Pylance) + 인터프리터 설정
INSTALL_PYTORCH=1         # PyTorch 1.10.0
INSTALL_TORCHVISION=1     # torchvision 0.11.1 (소스 빌드: 20분~1시간+ 소요)
INSTALL_JTOP=1            # jetson-stats (jtop)
ENABLE_SSH=1              # SSH 서버 (PC에서 MobaXterm으로 접속하기 위함)
AUTO_REBOOT=1             # 완료 후 자동 재부팅
# ---------------------------------------------------------------------------

LOG=/var/log/jetson_setup.log
DONE_FLAG=/var/lib/jetson_setup.done

# 화면과 로그 파일 양쪽에 동시 출력
exec > >(tee -a "$LOG") 2>&1

step()  { echo ""; echo "=== [$1] $2"; }
warn()  { echo "  !! $1 (건너뜁니다)"; }
ok()    { echo "  -> $1"; }

echo "############################################################"
echo "# Jetson Nano 자동 셋업 시작: $(date)"
echo "############################################################"

# 이미 완료되었으면 종료 (중복 실행 방지)
if [ -f "$DONE_FLAG" ]; then
    echo "이미 셋업이 완료되어 있습니다. 종료합니다."
    exit 0
fi

# ---------------------------------------------------------------------------
# 데스크톱 사용자 찾기 (VSCode 확장/설정은 root가 아닌 실제 사용자에게 적용해야 함)
# ---------------------------------------------------------------------------
TARGET_USER=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
echo "대상 사용자: ${TARGET_USER:-(없음)}  홈: ${USER_HOME:-(없음)}"

###############################################################################
step "1/9" "네트워크 연결 확인 (최대 3분 대기)"
###############################################################################
NET_OK=0
for i in $(seq 1 36); do
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        NET_OK=1; ok "인터넷 연결 확인됨"; break
    fi
    echo "  ($i/36) 네트워크 대기 중..."; sleep 5
done
[ "$NET_OK" = "0" ] && warn "인터넷 연결 없음 - 온라인 설치는 모두 건너뜁니다"

###############################################################################
step "2/9" "SWAP 메모리 ${SWAP_SIZE} 설정"
###############################################################################
if [ ! -f /swapfile ]; then
    if fallocate -l "$SWAP_SIZE" /swapfile && \
       chmod 600 /swapfile                 && \
       mkswap /swapfile >/dev/null         && \
       swapon /swapfile; then
        ok "스왑 활성화 완료"
        # 스왑 생성에 성공했을 때만 fstab 에 등록 (실패 시 등록하면 부팅 경고 발생)
        grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        ok "/etc/fstab 등록 완료 (재부팅 후에도 유지)"
    else
        warn "스왑 설정 실패 - fstab 에는 등록하지 않음"
        rm -f /swapfile
    fi
else
    ok "/swapfile 이 이미 존재함 - 건너뜀"
fi
free -h | sed 's/^/  /'

###############################################################################
step "3/9" "전원 성능 모드 설정 (MAXN 10W + 클럭 고정)"
###############################################################################
nvpmodel -m 0   >/dev/null 2>&1 && ok "nvpmodel -m 0 (MAXN) 적용" || warn "nvpmodel 실패"
jetson_clocks   >/dev/null 2>&1 && ok "jetson_clocks 적용"        || warn "jetson_clocks 실패"
nvpmodel -q 2>/dev/null | sed 's/^/  /'

# ===========================  이하 온라인 작업  =============================
if [ "$NET_OK" = "1" ]; then

###############################################################################
step "4/9" "기본 패키지 및 파이썬 모듈 설치"
###############################################################################
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    git curl wget \
    python3-pip python3-setuptools python3-wheel \
    python3-matplotlib python3-opencv python3-dev \
    libopenblas-base libopenmpi-dev \
    libjpeg-dev zlib1g-dev libpython3-dev \
    libavcodec-dev libavformat-dev libswscale-dev \
    && ok "apt 패키지 설치 완료" || warn "일부 apt 패키지 설치 실패"

# setuptools 는 torchvision/jtop 의 소스 빌드에 반드시 필요
pip3 install --no-cache-dir -U setuptools wheel \
    && ok "setuptools, wheel 준비 완료" || warn "setuptools 설치 실패"
pip3 install --no-cache-dir Cython numpy && ok "Cython, numpy 설치 완료" || warn "pip 설치 실패"

# Pillow: 최신 버전은 Python 3.8+ 문법을 써서 Python 3.6 에서 문법 오류가 남.
# torchvision 이 자동으로 최신 Pillow 를 받아오는 것을 막기 위해 미리 호환 버전을 설치.
if python3 -c "import PIL" 2>/dev/null; then
    ok "Pillow 가 이미 설치되어 있음"
else
    pip3 install --no-cache-dir "pillow<9" \
        && ok "Pillow (Python 3.6 호환 버전) 설치 완료" || warn "Pillow 설치 실패"
fi

# setuptools 가 정말 import 되는지 확인 (안 되면 이후 빌드가 전부 실패함)
if python3 -c "import setuptools" 2>/dev/null; then
    ok "setuptools 확인됨"
else
    warn "setuptools 를 불러올 수 없음 - torchvision/jtop 설치가 실패할 수 있음"
fi

###############################################################################
step "5/9" "PyTorch 1.10.0 설치"
###############################################################################
if [ "$INSTALL_PYTORCH" = "1" ]; then
    if python3 -c "import torch" 2>/dev/null; then
        ok "torch 가 이미 설치되어 있음 - 건너뜀"
    else
        WHL=/tmp/torch-1.10.0-cp36-cp36m-linux_aarch64.whl
        wget -q --show-progress -O "$WHL" \
          https://nvidia.box.com/shared/static/fjtbno0vpo676a25cgvuqc1wty0fkkg6.whl \
          && pip3 install --no-cache-dir "$WHL" \
          && ok "PyTorch 설치 완료" || warn "PyTorch 설치 실패"
    fi
else
    ok "설정에 의해 건너뜀"
fi

###############################################################################
step "6/9" "torchvision 0.11.1 설치 (빌드에 20분~1시간 이상 걸립니다)"
###############################################################################
if [ "$INSTALL_TORCHVISION" = "1" ]; then
    if python3 -c "import torchvision" 2>/dev/null; then
        ok "torchvision 이 이미 설치되어 있음 - 건너뜀"
    else
        cd /tmp && rm -rf torchvision
        if git clone --depth 1 --branch v0.11.1 \
             https://github.com/pytorch/vision torchvision; then
            if ( cd torchvision && export BUILD_VERSION=0.11.1 && python3 setup.py install ); then
                ok "torchvision 설치 완료"
            else
                warn "torchvision 빌드 실패"
            fi
        else
            warn "torchvision 소스 clone 실패"
        fi
    fi
else
    ok "설정에 의해 건너뜀"
fi

###############################################################################
step "7/9" "jetson-stats (jtop) 설치"
###############################################################################
if [ "$INSTALL_JTOP" = "1" ]; then
    pip3 install --no-cache-dir -U jetson-stats \
        && ok "jtop 설치 완료 (부팅 후 'jtop' 명령으로 실행)" || warn "jtop 설치 실패"
else
    ok "설정에 의해 건너뜀"
fi

###############################################################################
step "8/9" "VSCode 설치 + 확장 + Python 인터프리터 설정"
###############################################################################
if [ "$INSTALL_VSCODE" = "1" ]; then
    if command -v code >/dev/null 2>&1; then
        ok "VSCode 가 이미 설치되어 있음 - 건너뜀"
    else
        cd /tmp && rm -rf installVSCode
        if git clone --depth 1 https://github.com/JetsonHacksNano/installVSCode.git; then
            if ( cd installVSCode && chmod +x installVSCode.sh && ./installVSCode.sh ); then
                ok "VSCode 설치 완료"
            else
                warn "VSCode 설치 실패"
            fi
        else
            warn "installVSCode 저장소 clone 실패"
        fi
    fi

    # --- 확장 설치 (반드시 root가 아닌 실제 사용자 권한으로 실행) ---
    if command -v code >/dev/null 2>&1 && [ -n "$TARGET_USER" ]; then
        for EXT in ms-python.python ms-python.vscode-pylance; do
            sudo -u "$TARGET_USER" -H \
                code --install-extension "$EXT" --force >/dev/null 2>&1 \
                && ok "확장 설치: $EXT" || warn "확장 설치 실패: $EXT"
        done
    fi

    # --- Python 인터프리터를 python3 로 고정 (슬라이드의 '좌하단 클릭' 과정 대체) ---
    if [ -n "$USER_HOME" ]; then
        SET_DIR="$USER_HOME/.config/Code/User"
        mkdir -p "$SET_DIR"
        cat > "$SET_DIR/settings.json" <<'EOF'
{
    "python.defaultInterpreterPath": "/usr/bin/python3",
    "python.pythonPath": "/usr/bin/python3",
    "python.terminal.activateEnvironment": false,
    "terminal.integrated.defaultProfile.linux": "bash",
    "editor.fontSize": 14,
    "files.autoSave": "afterDelay"
}
EOF
        chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.config/Code" 2>/dev/null
        ok "VSCode 인터프리터를 /usr/bin/python3 (3.6) 으로 고정"
    fi
else
    ok "설정에 의해 건너뜀"
fi

###############################################################################
step "9/9" "SSH 서버 활성화 (PC에서 MobaXterm 으로 원격 접속용)"
###############################################################################
if [ "$ENABLE_SSH" = "1" ]; then
    apt-get install -y openssh-server >/dev/null 2>&1
    systemctl enable ssh >/dev/null 2>&1
    systemctl start  ssh >/dev/null 2>&1 && ok "SSH 서버 실행 중 (포트 22)" || warn "SSH 활성화 실패"
    IPADDR=$(hostname -I | awk '{print $1}')
    echo "  ------------------------------------------------------"
    echo "   MobaXterm 접속 정보 (Windows PC에서 사용)"
    echo "     Host : ${IPADDR:-확인불가}"
    echo "     User : ${TARGET_USER}"
    echo "     Port : 22"
    echo "  ------------------------------------------------------"
    # 바탕화면에도 접속정보를 파일로 남겨둠
    if [ -d "$USER_HOME/Desktop" ]; then
        printf 'MobaXterm 접속 정보\n  Host: %s\n  User: %s\n  Port: 22\n' \
            "${IPADDR}" "${TARGET_USER}" > "$USER_HOME/Desktop/SSH_접속정보.txt"
        chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/Desktop/SSH_접속정보.txt"
    fi
else
    ok "설정에 의해 건너뜀"
fi

else
    echo ""
    echo "인터넷이 없어 4~9 단계(온라인 설치)를 모두 건너뛰었습니다."
    echo "랜선을 연결한 뒤 아래 명령으로 다시 실행하세요:"
    echo "  sudo rm /var/lib/jetson_setup.done && sudo systemctl enable jetson-setup.service && sudo reboot"
fi

###############################################################################
# 설치 결과 검증
###############################################################################
echo ""
echo "############################################################"
echo "# 설치 결과 검증"
echo "############################################################"
python3 - <<'PYEOF' 2>&1 | sed 's/^/  /'
mods = ["numpy", "cv2", "torch", "torchvision", "matplotlib"]
for m in mods:
    try:
        mod = __import__(m)
        v = getattr(mod, "__version__", "?")
        print("[OK]   %-12s %s" % (m, v))
    except Exception as e:
        print("[FAIL] %-12s (%s)" % (m, type(e).__name__))
try:
    import torch
    print("[GPU]  torch.cuda.is_available() =", torch.cuda.is_available())
except Exception:
    pass
PYEOF

echo ""
echo "############################################################"
echo "# 셋업 완료: $(date)"
echo "# 전체 로그: $LOG"
echo "############################################################"

# 완료 플래그 + 서비스 비활성화 (다음 부팅부터 실행 안 함)
if [ "$NET_OK" = "1" ]; then
    touch "$DONE_FLAG"
    systemctl disable jetson-setup.service >/dev/null 2>&1 || true
    rm -f /etc/xdg/autostart/jetson-setup-watch.desktop 2>/dev/null || true
else
    # 인터넷이 없어 설치를 못 했으므로 완료 처리하지 않음 -> 다음 부팅에 자동 재시도
    echo "완료 처리하지 않습니다. 랜선 연결 후 재부팅하면 자동으로 다시 시도합니다."
fi

if [ "$AUTO_REBOOT" = "1" ]; then
    echo "30초 후 재부팅합니다... (취소하려면 Ctrl+C)"
    sleep 30
    reboot
fi