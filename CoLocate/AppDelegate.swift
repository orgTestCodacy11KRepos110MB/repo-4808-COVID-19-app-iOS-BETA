//
//  AppDelegate.swift
//  CoLocate
//
//  Created by NHSX.
//  Copyright © 2020 NHSX. All rights reserved.
//

import UIKit
import CoreData
import Firebase
import FirebaseInstanceID
import Logging

private let logger = Logger(label: "Application")

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    let remoteNotificationManager = ConcreteRemoteNotificationManager.shared
    let persistence = Persistence.shared
    let registrationService = ConcreteRegistrationService()
    let bluetoothNursery: BluetoothNursery

    var appCoordinator: AppCoordinator!
    var onboardingViewController: OnboardingViewController!
    
    
    override init() {
        LoggingManager.bootstrap()
        bluetoothNursery = BluetoothNursery()
        
        super.init()

        persistence.delegate = self
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // TODO: If DEBUG is only necessary as long as we have the same bundle ID for both builds.
        #if INTERNAL || DEBUG
        if let window = UITestResponder.makeWindowForTesting() {
            self.window = window
            return true
        }
        #endif
        
        logger.info("Launched", metadata: Logger.Metadata(launchOptions: launchOptions))
        
        application.registerForRemoteNotifications()

        remoteNotificationManager.configure()

        let rootViewController = RootViewController()
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = rootViewController

        if let registration = persistence.registration {
            continueWithRegistration(registration)
        }

        window?.makeKeyAndVisible()

        onboardingViewController = OnboardingViewController.instantiate()
        onboardingViewController.rootViewController = rootViewController

        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logger.info("Received notification", metadata: Logger.Metadata(dictionary: userInfo))
        
        remoteNotificationManager.handleNotification(userInfo: userInfo, completionHandler: { result in
             completionHandler(result)
        })
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("Terminating")

        let content = UNMutableNotificationContent()
        content.body = "Scanning for other devices has ended. To keep yourself secure, please relaunch the app."

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let request = UNNotificationRequest(identifier: "willTerminate.relaunch.immediate", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.info("Did Enter Background")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.info("Will Enter Foreground")
    }

    // MARK: - Private
    
    func continueWithRegistration(_ registration: Registration) {
        guard let rootViewController = window?.rootViewController as? RootViewController else {
            return
        }

        bluetoothNursery.startBroadcaster(stateDelegate: nil, sonarId: registration.id)
        bluetoothNursery.startListener(stateDelegate: nil)
        
        appCoordinator = AppCoordinator(navController: rootViewController,
                                        persistence: persistence,
                                        secureRequestFactory: ConcreteSecureRequestFactory(registration: registration))
        appCoordinator.start()
    }

}

extension AppDelegate: PersistenceDelegate {
    func persistence(_ persistence: Persistence, didRecordDiagnosis diagnosis: Diagnosis) {
        appCoordinator.showAppropriateViewController()
    }

    func persistence(_ persistence: Persistence, didUpdateRegistration registration: Registration) {
        onboardingViewController.updateState()

        // TODO: This is probably not the right place to put this,
        // but it'll do until we remove the old onboarding flow.
        continueWithRegistration(registration)
    }
}
