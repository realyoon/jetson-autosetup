#!/bin/bash
###############################################################################
# 셋업 진행상황을 보여주는 터미널을 자동으로 띄웁니다.
#   - 데스크톱 로그인 시 자동 실행됨 (/etc/xdg/autostart 에 등록)
#   - 셋업이 이미 끝났으면 아무것도 하지 않고 종료
###############################################################################

DONE_FLAG=/var/lib/jetson_setup.done
LOG=/var/log/jetson_setup.log

# 이미 셋업이 끝났으면 아무것도 하지 않음
[ -f "$DONE_FLAG" ] && exit 0

# 로그 파일이 생길 때까지 잠시 대기
for i in $(seq 1 30); do
    [ -f "$LOG" ] && break
    sleep 2
done

# 사용 가능한 터미널 프로그램을 찾아서 로그를 실시간으로 표시
CMD='echo "=== Jetson Nano 자동 셋업이 진행 중입니다. 창을 닫지 마세요. ==="; \
     echo "=== 완료되면 자동으로 재부팅됩니다. ==="; echo; \
     tail -f /var/log/jetson_setup.log'

for TERM_APP in gnome-terminal xfce4-terminal lxterminal xterm; do
    if command -v "$TERM_APP" >/dev/null 2>&1; then
        case "$TERM_APP" in
            gnome-terminal)
                exec gnome-terminal --maximize -- bash -c "$CMD" ;;
            xfce4-terminal)
                exec xfce4-terminal --maximize -e "bash -c '$CMD'" ;;
            lxterminal)
                exec lxterminal -e bash -c "$CMD" ;;
            xterm)
                exec xterm -maximized -e bash -c "$CMD" ;;
        esac
    fi
done

exit 0
