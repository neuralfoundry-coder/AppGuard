# AppGuard — 앱 실행 시 Touch ID/암호 인증

작성일: 2026-11-21

## 목적
아래 대상은 실행(접근)할 때마다 Touch ID 또는 계정 암호 인증에 1회 성공해야 사용 가능.
- 메시지(`com.apple.MobileSMS`), 사진(`com.apple.Photos`), 메모(`com.apple.Notes`), 전화(`com.apple.mobilephone`, 2026-11-21 추가)
- Finder에서 iCloud Drive(`~/Library/Mobile Documents/...`) 접근

## 방법
macOS에는 앱별 잠금 기능이 없어, 로그인 시 자동 실행되는 Swift 백그라운드 에이전트(LaunchAgent)로 구현.

1. **앱 3종**: `NSWorkspace.didLaunchApplicationNotification`으로 실행 감지 → 즉시 `SIGSTOP`(프로세스 정지)+숨김
   → `LocalAuthentication`(`.deviceOwnerAuthentication`: Touch ID, 실패 시 암호) 호출
   → 성공 `SIGCONT`로 재개 / 실패·취소 시 `SIGKILL`. 앱을 종료하면 인증이 풀려 다음 실행 때 다시 인증.
2. **Finder iCloud**: Finder는 항상 실행 중이라 1초 주기로 AppleScript로 Finder 창 경로를 검사.
   iCloud 경로 창이 보이면 그 창을 홈으로 되돌리고 인증 → 성공 시 원래 폴더 다시 열기.
   iCloud 창이 모두 닫히면 인증 상태 초기화(다음 접근 때 다시 인증).
3. LaunchAgent(`RunAtLoad`, `KeepAlive`)로 로그인 시 자동 시작, 죽어도 재시작.

## 결과물
| 파일 | 설명 |
|---|---|
| `AppGuard.swift` | 소스 |
| `install.sh` | 빌드+설치+등록 (빌드 산출물은 `/Volumes/BuildSpace/appguard/`, 정책 준수) |
| `uninstall.sh` | 완전 제거 |
| 설치 위치 | `~/.local/bin/appguard`, `~/Library/LaunchAgents/com.local.appguard.plist` |

## 현재 상태 (2026-11-21)
- 빌드 성공, LaunchAgent 등록 및 실행 확인 (`launchctl list | grep appguard`).
- Touch ID 프롬프트 동작은 이 세션에서 직접 테스트하지 못함 → 직접 메시지/사진/메모를 실행해 확인 필요.

## 최초 1회 필요한 권한
- Finder 제어 허용: 첫 실행 시 "appguard이(가) Finder를 제어하려 합니다" 팝업 → 허용
  (시스템 설정 → 개인정보 보호 및 보안 → 자동화).

## 한계 (보안 경계가 아닌 억제 장치)
- 앱 창이 실행 직후 ~수십 ms 잠깐 보일 수 있음 (감지 후 정지까지의 지연).
- 관리자 권한 사용자가 에이전트를 종료/삭제하면 우회 가능.
- 에이전트 재시작 시 이미 실행 중인 대상 앱도 다시 인증을 요구함.
- Finder 외 앱의 열기/저장 대화상자, 터미널의 iCloud 경로 접근은 막지 못함.
- 앱 업데이트로 번들 ID가 바뀌면 `AppGuard.swift`의 `guardedBundleIDs` 수정.

## 관리
```
launchctl list | grep appguard          # 상태
./install.sh                            # 수정 후 재빌드/재설치
./uninstall.sh                          # 제거
```
