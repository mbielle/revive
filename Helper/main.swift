import Foundation
import LucentKit

// Lucent's privileged helper. launchd starts it on demand as root when the app connects.
// It only runs the commands of `PrivilegedCommand`, only for the signed Lucent app;
// the logic lives in LucentKit's HelperService so it is covered by tests.

#if DEBUG
let allowsAdHoc = true
#else
let allowsAdHoc = false
#endif

let delegate = HelperListenerDelegate(requirement: HelperListenerDelegate.requirement(allowsAdHoc: allowsAdHoc))
let listener = NSXPCListener(machServiceName: helperServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
