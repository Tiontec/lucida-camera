import UIKit

/// 澄影 · iOS 原生外壳。
/// 网页（Resources/web/index.html）负责全部界面与调色算法；本工程负责：
/// 系统相册写入、实况照片、原生拍摄（HEIF / ProRAW）、摄像头检测、原生液态玻璃叠层。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = .black
        w.overrideUserInterfaceStyle = .dark
        w.rootViewController = WebViewController()
        w.makeKeyAndVisible()
        window = w
        application.isIdleTimerDisabled = true      // 取景时不自动锁屏
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }
}
