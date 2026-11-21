import Cocoa
import LocalAuthentication

// AppGuard: 지정한 앱을 실행할 때 Touch ID / 암호 인증에 성공해야만 사용 가능하게 한다.
// - 대상 앱(메시지, 사진, 메모): 실행 감지 즉시 SIGSTOP(정지) -> 인증 -> 성공 시 SIGCONT, 실패 시 강제 종료
// - Finder: 1초마다 창 경로를 검사해 iCloud Drive(Mobile Documents) 접근 시 인증 요구

let guardedBundleIDs: Set<String> = [
    "com.apple.MobileSMS",  // 메시지
    "com.apple.Photos",     // 사진
    "com.apple.Notes",      // 메모
    "com.apple.mobilephone", // 전화
]

var authedPIDs = Set<pid_t>()
var pendingPIDs = Set<pid_t>()
var finderAuthed = false
var finderPrompting = false

func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
    let ctx = LAContext()
    var err: NSError?
    // deviceOwnerAuthentication = Touch ID, 실패/취소 시 계정 암호 입력 허용
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
        NSLog("AppGuard: cannot evaluate policy: \(String(describing: err))")
        completion(false)
        return
    }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, e in
        if !ok { NSLog("AppGuard: auth failed: \(String(describing: e))") }
        DispatchQueue.main.async { completion(ok) }
    }
}

func lock(_ app: NSRunningApplication) {
    let pid = app.processIdentifier
    guard !authedPIDs.contains(pid), !pendingPIDs.contains(pid) else { return }
    pendingPIDs.insert(pid)
    kill(pid, SIGSTOP)
    app.hide()
    let name = app.localizedName ?? "App"
    authenticate(reason: "\(name) 실행을 위해 인증이 필요합니다") { ok in
        pendingPIDs.remove(pid)
        if ok {
            authedPIDs.insert(pid)
            kill(pid, SIGCONT)
            app.unhide()
            app.activate()
        } else {
            kill(pid, SIGKILL)
        }
    }
}

func runScript(_ src: String) -> String? {
    var errInfo: NSDictionary?
    let r = NSAppleScript(source: src)?.executeAndReturnError(&errInfo)
    if let errInfo = errInfo { NSLog("AppGuard: applescript error: \(errInfo)") }
    return r?.stringValue
}

func checkFinder() {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first != nil else { return }
    let src = """
    tell application "Finder"
      set out to ""
      repeat with i from 1 to (count of Finder windows)
        try
          set out to out & i & "|" & POSIX path of (target of Finder window i as alias) & linefeed
        end try
      end repeat
      return out
    end tell
    """
    let lines = (runScript(src) ?? "").split(separator: "\n").map(String.init)
    let icloud = lines.filter { $0.contains("/Library/Mobile Documents/") }
    if icloud.isEmpty { finderAuthed = false; return }   // iCloud 창이 모두 닫히면 다음 접근 때 다시 인증
    if finderAuthed || finderPrompting { return }
    finderPrompting = true
    // 인증 전까지 해당 창을 홈으로 되돌려 내용을 숨김
    var restore: [String] = []
    for l in icloud {
        let parts = l.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        restore.append(parts[1])
        _ = runScript("tell application \"Finder\" to set target of Finder window \(parts[0]) to home")
    }
    authenticate(reason: "Finder에서 iCloud Drive에 접근하려면 인증이 필요합니다") { ok in
        finderPrompting = false
        if ok {
            finderAuthed = true
            for p in restore { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
        }
    }
}

let nc = NSWorkspace.shared.notificationCenter
nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
    guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          let id = app.bundleIdentifier, guardedBundleIDs.contains(id) else { return }
    lock(app)
}
nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
    if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        authedPIDs.remove(app.processIdentifier)
        pendingPIDs.remove(app.processIdentifier)
    }
}

// 에이전트 시작 시 이미 실행 중인 대상 앱도 잠금
for app in NSWorkspace.shared.runningApplications {
    if let id = app.bundleIdentifier, guardedBundleIDs.contains(id) { lock(app) }
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in checkFinder() }

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
