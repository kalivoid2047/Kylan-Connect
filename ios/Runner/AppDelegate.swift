import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let bgRefreshTaskId = "com.kylanconnect.app.refresh"
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // MARK: - App lifecycle

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        registerBGTasks()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        setupMethodChannel(binaryMessenger: engineBridge.binaryMessenger)
    }

    // When the app moves to background, request ~30 s of extra execution time so
    // the Dart networking layer can finish any pending sends before suspension.
    override func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundTaskId = application.beginBackgroundTask(withName: "KylanConnectBackground") {
            application.endBackgroundTask(self.backgroundTaskId)
            self.backgroundTaskId = .invalid
        }
        scheduleAppRefresh()
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }

    // MARK: - Background Tasks (iOS 13+)

    private func registerBGTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgRefreshTaskId,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgRefreshTaskId)
        // iOS enforces a minimum interval; 15 minutes is the practical lower bound.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler can fail in the simulator or if the identifier is not
            // listed in Info.plist — safe to ignore here.
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Immediately schedule the next refresh so we never miss a slot.
        scheduleAppRefresh()

        // Give up to 25 seconds for reconnection / discovery before the OS
        // reclaims the time budget.
        let deadline = DispatchTime.now() + .seconds(25)
        DispatchQueue.main.asyncAfter(deadline: deadline) {
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Method Channel

    private func setupMethodChannel(binaryMessenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.kylanconnect.app/background",
            binaryMessenger: binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "scheduleAppRefresh":
                self.scheduleAppRefresh()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
