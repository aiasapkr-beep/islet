# Islet

A small island around your MacBook's notch: Claude Code usage limits on both sides, Now Playing in the middle.

Hover the notch to see your **5-hour session** and **weekly** utilization with reset timers. On Macs without a notch it hangs as a small island at the top of the screen, and there is always a menu bar item as well.

![collapsed](docs/collapsed.png)
![expanded](docs/expanded.png)

- Reads the same numbers that Claude Code's `/usage` shows (`api.anthropic.com/api/oauth/usage`).
- No API key, no extra cost. It reuses the Claude Code login already on your Mac.
- Auto-refreshes the OAuth token when it expires (same flow Claude Code uses) and writes it back so `claude` keeps working too. Can be turned off in the menu.
- Reset countdown next to each gauge, even when collapsed.
- A small green dot beside the notch pulses while Claude Code is writing a transcript (FSEvents on `~/.claude/projects`); the expanded footer shows whether sessions are working, idle, or absent.
- **Now Playing island**: album art on the left of the notch, equalizer bars on the right while music plays. Hover for title, artist, progress, and previous/play-pause/next. Works with anything that publishes to macOS Now Playing (YouTube Music as a Chrome app, Spotify, Apple Music, Safari…). Toggle off in the menu.
- Polls once a minute, backs off on `429`.
- Launch at login, show/hide the notch island, hide the menu bar icon entirely (right-click the island for the same menu).

## Requirements

- macOS 14 Sonoma or later (Apple Silicon or Intel).
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) signed in with a Claude subscription (`claude` → `/login`). Usage limits are a subscription feature; API-key logins have no 5-hour/weekly window.
- Xcode 15+ (or Command Line Tools with a Swift 5.10 toolchain) to build.

## Build & run

```bash
git clone https://github.com/aiasapkr-beep/islet.git
cd islet
make run          # builds build/Islet.app and opens it
make install      # copies it to /Applications
```

The first launch asks for access to the **"Claude Code-credentials"** Keychain item. Click **Always Allow**; that is how the app reads (and refreshes) the token.

`make icon` regenerates `Resources/AppIcon.icns` from `Scripts/make-icon.swift`.

## How it works

1. Loads Claude Code's credentials from the login Keychain (service `Claude Code-credentials`). It reads them through `/usr/bin/security` so it never raises a per-app Keychain permission dialog, falling back to direct Keychain access and then `~/.claude/.credentials.json` (or `$CLAUDE_CONFIG_DIR`).
2. If the access token is expired, refreshes it with Claude Code's public OAuth client id and saves the new token back in the same format.
3. Calls `GET /api/oauth/usage` with `anthropic-beta: oauth-2025-04-20` and renders `five_hour`, `seven_day`, and the per-model weekly windows when present.

### Now Playing on macOS 15.4+

Apple locked the private MediaRemote framework to entitled system binaries in 15.4. Islet bundles [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3, vendored under `Vendor/`), which loads a small helper framework inside `/usr/bin/perl` and streams Now Playing JSON. The app reads that stream as a child process; the bars are procedural (macOS exposes no audio levels). If Apple breaks the adapter, music quietly disappears and usage keeps working.

Environment flags for development:

| Flag | Effect |
|---|---|
| `ISLET_DEBUG=1` | Echo logs to stderr (also visible in Console.app under subsystem `kr.asapai.Islet`). |
| `ISLET_MOCK=1` | Show sample data (usage, activity, music); no Keychain or network access. |
| `ISLET_MOCK_USAGE=1` | Mock only the usage numbers; activity pulse and Now Playing stay real. |
| `ISLET_ADAPTER_DIR` | Directory holding `mediaremote-adapter.pl` + `MediaRemoteAdapter.framework` when running the bare binary. |
| `ISLET_EXPANDED=1` | Start with the island expanded (for screenshots). |
| `ISLET_SNAPSHOT=/path/out.png` | Render the island to a trimmed PNG and quit. `make shots` regenerates `docs/*.png`. |

## Troubleshooting

- **Menu bar shows `!`** – open the menu to read the error. Most common: the token *and* its refresh token are expired. Run `claude` in Terminal and `/login` once; the app picks it up on the next poll.
- **`Keychain error`** – you denied the Keychain prompt. Quit the app, open Keychain Access, find "Claude Code-credentials" → Access Control, and add Islet, or just relaunch and click Always Allow.
- **No music shows up** – make sure the player publishes to Now Playing (the macOS Control Center media widget shows it). Run `/usr/bin/perl Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$PWD/Vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework" get --no-artwork` to test the adapter directly.
- **Rebuilt the app and the prompt is back** – ad-hoc signatures change with every build. Sign with your own Developer ID in `Scripts/build-app.sh` if that bothers you.
- **Island overlaps a menu bar icon** – it extends about 130pt on each side of the notch. Turn it off with "Show in Notch" and rely on the menu bar item, or shrink `sideWidth` in `NotchView.swift`.
- **Something peeks out beside the notch** – with many status items macOS pushes them behind the notch, and Islet's own menu bar item can end up there. Turn off "Show % in Menu Bar" (default) or "Menu Bar Icon"; right-click the island to get the menu back.

## Privacy

Everything stays on your Mac. The only network calls go to `api.anthropic.com` (usage) and `platform.claude.com` / `console.anthropic.com` (token refresh). No analytics, no third-party servers.

## License

MIT

---

## 한국어

맥북 노치 주변에 붙는 작은 섬입니다. 양옆에 Claude Code의 **5시간 세션**과 **주간** 사용량, 가운데에 지금 재생 중인 음악을 보여줍니다. 노치에 마우스를 올리면 리셋까지 남은 시간과 함께 펼쳐집니다. 노치 없는 맥에서는 화면 상단 중앙에 작은 아일랜드로 붙고, 메뉴바 아이템은 항상 있습니다.

- Claude Code의 `/usage`와 같은 엔드포인트를 그대로 읽습니다. 별도 API 키나 추가 비용이 없습니다.
- 맥에 이미 로그인된 Claude Code 자격증명(키체인)을 재사용하고, 만료되면 Claude Code와 같은 방식으로 토큰을 갱신해 다시 저장합니다. 메뉴에서 끌 수 있습니다.
- 접힌 상태에서도 게이지 옆에 리셋까지 남은 시간 표시.
- Claude Code가 대화 기록을 쓰는 동안 노치 옆 초록 점이 맥박처럼 뜁니다(`~/.claude/projects` 파일 이벤트). 펼치면 세션이 작업 중인지, 대기 중인지, 없는지 하단에 표시.
- **Now Playing 아일랜드**: 음악이 재생되면 노치 왼쪽에 앨범아트, 오른쪽에 이퀄라이저 바가 뜹니다. 펼치면 제목·아티스트·진행바·이전/재생·정지/다음 버튼. macOS Now Playing에 올라오는 앱은 전부 지원(YouTube Music 크롬 앱, Spotify, Apple Music, Safari 등). 메뉴에서 끌 수 있습니다.
- 1분마다 갱신, `429`면 대기.
- 로그인 시 실행, 노치 표시 켜고 끄기, 메뉴바 아이콘 완전히 숨기기(설정 메뉴는 섬을 우클릭해도 나옵니다).

### 빌드

```bash
git clone https://github.com/aiasapkr-beep/islet.git
cd islet
make run
```

처음 실행하면 "Claude Code-credentials" 키체인 접근을 묻습니다. **항상 허용**을 누르세요.

### 문제 해결

- **메뉴바에 `!`** 메뉴를 열면 오류 메시지가 보입니다. 대개 토큰과 갱신 토큰이 모두 만료된 경우이므로 터미널에서 `claude`를 실행해 `/login`을 한 번 하면 됩니다.
- **키체인 오류** 접근을 거부한 경우입니다. 앱을 다시 열고 항상 허용을 누르거나, 키체인 접근 앱에서 "Claude Code-credentials" 항목의 접근 제어에 Islet를 추가하세요.
- **메뉴바 아이콘과 겹침** 노치 양옆으로 100pt 정도씩 뻗습니다. "Show in Notch"를 끄거나 `NotchView.swift`의 `sideWidth`를 줄이세요.
