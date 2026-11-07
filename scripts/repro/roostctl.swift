// Sends a debug command to a running Roost (only obeyed while debugState is on).
// Usage: roostctl <minimise|restore|drop|resize|layout|login-on|login-off> [window title or layout] [x y | width height]
import Foundation
let a = CommandLine.arguments
guard a.count >= 2 else { print("usage: roostctl action [title] [x y]"); exit(2) }
var info = ["action": a[1]]
if a.count >= 3 { info["title"] = a[2] }
if a.count >= 5 { info["x"] = a[3]; info["y"] = a[4] }
DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.priyansh.roost.debug"), object: nil, userInfo: info, deliverImmediately: true)
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
