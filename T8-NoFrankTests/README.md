# T8-NoFrankTests — 알람 로직 테스트 가이드

> 비전공자/테스트 처음인 팀원도 읽을 수 있게 쓴 문서입니다.
> "왜 했는지 → 무엇을 검증하는지 → 앞으로 어떻게 추가하는지" 순서로 읽으세요.

---

## 1. 왜 도입했나 (Why)

### 기존 방식의 통증
알람 로직을 고칠 때마다 이렇게 확인했습니다.

```
코드 수정 → 실기기에 빌드 → 알람을 "1분 뒤"로 설정 → 1분 동안 멍하니 대기 → 진짜 울리나 눈으로 확인
```

- 한 번 확인에 **최소 1분 + 빌드 시간**
- 강제 종료 케이스, 요일 경계 케이스 등은 매번 손으로 재현해야 함
- "노티가 정확히 60개 잡혔나?", "64개 한도 안 넘었나?" 같은 건 **눈으로 셀 수도 없음**

### 도입 후
```
코드 수정 → ⌘U → 0.5초 뒤 초록 체크 ✅
```

실기기도, 1분 대기도 없이 **코드가 시키는 동작을 즉시 검증**합니다.

> ⚠️ 단, 테스트가 보장하는 건 **"우리 코드가 무엇을 호출했는가"**까지입니다.
> "실제로 스피커에서 소리가 나는가", "iOS가 진짜 노티를 발사하는가"는
> 여전히 릴리즈 전 실기기 확인이 필요합니다. (테스트의 한계)

---

## 2. 무엇을 검증하나 (What)

테스트는 두 묶음입니다.

### 묶음 A — 알람 시각 판정 (`AlarmEvaluationTests.swift`)
"지금 시각·요일·상태를 보면 알람을 울려야 하나?"를 판정하는 순수 함수
`BackgroundAudioPlayer.evaluateAlarm(...)`를 검증합니다.

- 알람 시각 도달 + 선택 요일 → `.ring` (울림)
- 알람 시각 1초 전 → `.wait` (대기)
- 이미 알람 모드 → `.wait` (재발동 방지)
- 시각은 지났지만 미선택 요일 → `.rescheduleToNextWeekday` (다음 요일로)

이게 가능한 이유: 이 함수는 `Date()`를 내부에서 직접 읽지 않고
**가짜 시각을 인자로 받기** 때문에, 테스트가 "1시 20분"을 마음대로 주입할 수 있습니다.

### 묶음 B — 노티 스케줄링 (`BackgroundAudioPlayerNotificationTests.swift`)
"알람이 켜지고 꺼질 때 노티가 **언제·몇 개·어떤 ID**로 예약/제거되는가"를 검증합니다.

- `startSilentSound` → 이전 종료 경고 노티 정리되는가
- `scheduleTerminationWarning` → 종료 경고 노티 1개만 등록되는가 (3초 트리거)
- `scheduleAlarmBurst` → burst 노티 정확히 **60개**, ID `ALARM_BURST_0~59`
- `scheduleAlarmBurst` → 간격이 **30초씩**(30, 60, …, 1800초) 증가하는가
- `cancelAlarmBurst` → 60개 pending + delivered 모두 제거되는가
- **회귀 방어**: burst 60 + 종료경고 1 = 61개 ≤ **iOS 펜딩 한도 64개**

---

## 3. 어떻게 동작하나 (How) — Spy 패턴 한 장 요약

핵심 아이디어 하나만 이해하면 됩니다: **"노티 센터에 CCTV를 달았다."**

원래 코드는 iOS의 진짜 노티 센터(`UNUserNotificationCenter`)를 직접 불렀습니다.
이러면 테스트에서 "몇 개 예약됐는지" 들여다볼 방법이 없습니다.

그래서 사이에 **얇은 인터페이스(`NotificationScheduling` 프로토콜)**를 끼웠습니다.

```
BackgroundAudioPlayer
        │  "노티 예약해줘"
        ▼
NotificationScheduling (프로토콜 = 약속)
        │
   ┌────┴─────────────────────┐
   ▼                          ▼
SystemNotificationScheduler   SpyNotificationScheduler
(운영: 진짜 iOS 노티 센터 호출)  (테스트: 호출 기록만 저장)
```

- **운영 빌드**: 진짜 노티 센터를 그대로 부릅니다 → 앱 동작은 1도 안 변함
- **테스트**: 가짜(Spy)를 끼워넣어, 진짜 노티는 안 쏘고
  "누가 언제 무슨 ID로 몇 개 예약했는지" 기록만 남깁니다 → 그걸 읽어서 검증

> 이걸 어려운 말로 **의존성 주입(DI)** + **테스트 더블(Spy)** 이라고 합니다.
> 면접에서 "외부 의존성을 어떻게 테스트하나요?" 물으면 이 패턴이 정답입니다.

---

## 4. 테스트 돌리는 법

1. 상단 디바이스 선택에서 **시뮬레이터**(예: iPhone 16) 선택 — 실기기 불필요
2. **⌘U** (Product → Test)
3. **⌘6**(Test Navigator)에서 초록 체크 ✅ / 빨강 X ❌ 확인

> 시뮬레이터는 첫 부팅만 ~15초, 그 다음부터 ⌘U는 1초 내. 창은 닫지 말고 둘 것.

---

## 5. 앞으로 테스트를 추가하려면 (How to add)

### 규칙 1 — 테스트하고 싶은 로직은 "순수 함수"로 빼라
시각·랜덤·외부 상태를 **함수 안에서 읽지 말고, 인자로 받게** 만드세요.
그래야 테스트가 가짜 값을 주입할 수 있습니다. (`evaluateAlarm`이 좋은 예)

### 규칙 2 — 외부 시스템(노티/오디오 등)은 "프로토콜 뒤로" 숨겨라
`UNUserNotificationCenter`, `AVAudioSession` 같은 걸 직접 부르면 테스트가 막힙니다.
`NotificationScheduling`처럼 프로토콜을 만들고, 테스트는 Spy를 주입하세요.

### 규칙 3 — 테스트 한 개의 모양
```swift
import Testing
@testable import T8_NoFrank

@Suite("무엇을 검증하는 묶음인지")
struct MyFeatureTests {
    @Test("이 상황이면 → 이 결과가 나와야 한다")
    func someBehavior() {
        // 1) 준비 (가짜 값/Spy 세팅)
        let spy = SpyNotificationScheduler()
        let sut = BackgroundAudioPlayer(scheduler: spy, setupAudio: false)

        // 2) 실행 (검증할 동작 호출)
        sut.scheduleAlarmBurst()

        // 3) 검증 (#expect 조건이 true여야 통과)
        #expect(spy.addedRequests(withPrefix: "ALARM_BURST_").count == 60)
    }
}
```

- `@Suite` = 테스트 묶음 이름표
- `@Test` = 테스트 1개 (설명을 한글로 적으면 결과창에 그대로 보임)
- `#expect(조건)` = 이 조건이 **true면 통과, false면 실패**
- `makeSUT()` 같은 헬퍼로 준비 코드를 짧게 유지하면 읽기 편합니다

### 규칙 4 — 새 테스트 파일은 타겟 체크 잊지 말기
새 `.swift` 파일을 만들면 Xcode 우측 **Target Membership**에서
**`T8-NoFrankTests`** 체크해야 ⌘U에 포함됩니다. (안 하면 그냥 무시됨)

---

## 6. 자주 묻는 질문

**Q. 테스트 통과 = 버그 없음 인가요?**
아니요. **"내가 쓴 `#expect` 조건만큼만"** 보장합니다.
검증 안 한 케이스에서는 여전히 버그가 날 수 있어요. 테스트를 잘 짜는 게 실력입니다.

**Q. 실기기 확인은 이제 안 해도 되나요?**
줄어들 뿐, 0은 아닙니다. 실제 소리·진짜 노티 발사·강제 종료 후 동작은
릴리즈 전 실기기로 최종 확인하세요. 테스트는 그 횟수를 크게 줄여줄 뿐입니다.

**Q. `setupAudio: false`는 뭔가요?**
`BackgroundAudioPlayer`는 생성될 때 오디오 세션을 켭니다(부작용).
테스트에선 그게 필요 없고 방해되므로 끄는 옵션입니다. 운영은 기본값 `true`.
