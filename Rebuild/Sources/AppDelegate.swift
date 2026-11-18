import UIKit

/// 澄影重构版 · iOS。没有网页：打开就是原生相机（双摄系统提取而来），所有功能和设置都是原生界面。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = .black
        w.overrideUserInterfaceStyle = .dark
        w.rootViewController = DualCamViewController()
        w.makeKeyAndVisible()
        window = w
        application.isIdleTimerDisabled = true      // 取景时不自动锁屏
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .portrait }
}
