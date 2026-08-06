# Jetson Nano 기본 세팅 완전 자동화

`젯슨나노설정_기본세팅.pdf` 의 모든 단계를 **부팅 한 번으로 자동 실행**되게 만드는 도구입니다.
세팅이 안 된 새 Jetson Nano를 받은 초보자가, 파일만 복사하고 명령 한 줄 치면 나머지는 전부 알아서 진행됩니다.

---

## 자동화 범위

| PDF 슬라이드 | 자동화 여부 | 처리 방식 |
|---|---|---|
| SWAP 메모리 6GB (p.38) | 완전 자동 | fallocate ~ fstab 등록까지 |
| Power 설정 / MAXN 10W (p.37) | 완전 자동 | `nvpmodel -m 0`, `jetson_clocks` |
| 환경설정 추가 (p.39) | 완전 자동 | pip3, Cython, numpy, matplotlib |
| Jetson-stats / jtop (p.36) | 완전 자동 | `pip3 install -U jetson-stats` |
| VSCode 설치 (p.27) | 완전 자동 | JetsonHacksNano/installVSCode 클론 후 실행 |
| Pylance / Intellisense (p.32) | 완전 자동 | `code --install-extension` 로 무인 설치 |
| Python 인터프리터 설정 (p.29) | 자동 (대체) | GUI 클릭 대신 `settings.json` 에 python3 고정 |
| MobaXterm (p.33~35) | **부분** | Windows 전용 프로그램이라 Jetson에선 설치 불가.<br>대신 **SSH 서버를 자동 활성화**하고 접속 IP를 바탕화면에 저장 |
| PyTorch / torchvision | 완전 자동 | 대화에서 진행했던 내용 포함 (스위치로 끌 수 있음) |
| VSCode 실행 / Python 실행 화면 (p.28,30,31) | 해당없음 | 결과 확인용 화면이라 자동화 대상 아님 |

MobaXterm은 Windows PC에 직접 설치해야 합니다: https://mobaxterm.mobatek.net/
셋업이 끝나면 바탕화면에 `SSH_접속정보.txt` 가 생성되니, 거기 적힌 IP로 접속하면 됩니다.

---

## 파일 구성

| 파일 | 역할 |
|---|---|
| `install_autosetup.sh` | **이것만 한 번 실행** 하면 등록 완료 |
| `jetson_setup.sh` | 실제 셋업을 수행하는 메인 스크립트 |
| `jetson-setup.service` | 부팅 시 자동 실행시키는 systemd 서비스 |
| `jetson_setup_watch.sh` | 진행상황 터미널을 자동으로 띄우는 스크립트 |
| `jetson-setup-watch.desktop` | 로그인 시 위 터미널을 자동 실행하는 항목 |
| `README.md` | 이 문서 |

---

## 사용법 (딱 3단계)

1. **랜선을 연결**합니다. (P3450은 와이파이가 내장돼 있지 않습니다)

2. 이 폴더 전체를 Jetson으로 복사합니다. (USB, SD카드, scp 등 아무 방법)

3. 복사한 폴더에서 터미널을 열고:
   ```bash
   sudo bash install_autosetup.sh
   ```
   "지금 재부팅할까요?" 에 `y` 입력.

이후로는 **아무것도 하지 않아도 됩니다.**
재부팅되면 화면에 진행상황 터미널이 자동으로 뜨고, 모든 설치가 끝나면 스스로 재부팅합니다.
그다음 부팅부터는 평범하게 켜지고 셋업은 다시 실행되지 않습니다.

---

## 소요 시간

torchvision 소스 빌드 때문에 전체 **40분 ~ 1시간 30분** 정도 걸립니다.
빠르게 끝내고 싶으면 `jetson_setup.sh` 상단에서:
```bash
INSTALL_TORCHVISION=0
INSTALL_PYTORCH=0
```
로 바꾸면 10분 내외로 끝납니다.

---

## 설정 스위치

`jetson_setup.sh` 맨 위에서 원하는 항목만 켜고 끌 수 있습니다.

```bash
SWAP_SIZE=6G              # 스왑 크기
INSTALL_VSCODE=1          # VSCode + 확장 + 인터프리터 설정
INSTALL_PYTORCH=1         # PyTorch 1.10.0
INSTALL_TORCHVISION=1     # torchvision 0.11.1 (오래 걸림)
INSTALL_JTOP=1            # jetson-stats (jtop)
ENABLE_SSH=1              # SSH 서버 (MobaXterm 접속용)
AUTO_REBOOT=1             # 완료 후 자동 재부팅
```

---

## 진행상황 확인

자동으로 뜨는 터미널 외에, 다른 터미널에서 직접 볼 수도 있습니다:
```bash
tail -f /var/log/jetson_setup.log
```
(Ctrl+C 로 빠져나와도 셋업은 계속 진행됩니다)

---

## 완료 후 확인

```bash
python3 -c "import numpy, cv2, torch, torchvision, matplotlib; print(torch.__version__, torch.cuda.is_available())"
jtop
free -h
```
스크립트가 마지막에 이 검증을 자동으로 수행해 로그에 남깁니다.

---

## 다시 처음부터 실행하고 싶을 때

```bash
sudo rm /var/lib/jetson_setup.done
sudo systemctl enable jetson-setup.service
sudo reboot
```

---

## 알아둘 점

- **인터넷 필수**: 랜선이 없으면 스왑/전원 설정만 되고 온라인 설치는 전부 건너뜁니다. 이 경우 위의 "다시 실행" 방법으로 재시도하세요.
- **중간 재실행 안전**: 각 단계가 "이미 설치됨"이면 스스로 건너뛰므로, 중간에 멈췄다가 다시 돌려도 문제없습니다.
- **첫 배포 전 1대에서 테스트 권장**: PyTorch 다운로드 URL이나 torchvision 버전은 시간이 지나면 바뀔 수 있습니다. 한 대에서 로그를 보며 확인한 뒤 여러 대에 배포하세요.
- 어느 단계가 실패해도 나머지는 계속 진행되며, 실패 항목은 로그에 `!!` 로 표시됩니다.
