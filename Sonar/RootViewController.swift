//
//  RootViewController.swift
//  Sonar
//
//  Created by NHSX on 4/6/20.
//  Copyright © 2020 NHSX. All rights reserved.
//

import UIKit

class RootViewController: UIViewController {

    private var persistence: Persisting! = nil
    private var authorizationManager: AuthorizationManaging! = nil
    private var remoteNotificationManager: RemoteNotificationManager! = nil
    private var notificationCenter: NotificationCenter! = nil
    private var registrationService: RegistrationService! = nil
    private var bluetoothNursery: BluetoothNursery!
    private var onboardingCoordinator: OnboardingCoordinating!
    private var monitor: AppMonitoring!
    private var session: Session!
    private var contactEventsUploader: ContactEventsUploading!
    private var uiQueue: TestableQueue! = nil
    private var setupChecker: SetupChecker!
    private var statusStateMachine: StatusStateMachining!
    private var urlOpener: TestableUrlOpener!
    private var accessibilityChangeNotifier: AccessibilityChangeNotifier!
    private weak var presentedSetupErorrViewController: UIViewController? = nil

    private var statusViewController: StatusViewController!

    func inject(
        persistence: Persisting,
        authorizationManager: AuthorizationManaging,
        remoteNotificationManager: RemoteNotificationManager,
        notificationCenter: NotificationCenter,
        registrationService: RegistrationService,
        bluetoothNursery: BluetoothNursery,
        onboardingCoordinator: OnboardingCoordinating,
        monitor: AppMonitoring,
        session: Session,
        contactEventsUploader: ContactEventsUploading,
        linkingIdManager: LinkingIdManaging,
        statusStateMachine: StatusStateMachining,
        uiQueue: TestableQueue,
        urlOpener: TestableUrlOpener,
        drawerMailbox: DrawerMailboxing
    ) {
        self.persistence = persistence
        self.authorizationManager = authorizationManager
        self.remoteNotificationManager = remoteNotificationManager
        self.notificationCenter = notificationCenter
        self.registrationService = registrationService
        self.bluetoothNursery = bluetoothNursery
        self.onboardingCoordinator = onboardingCoordinator
        self.monitor = monitor
        self.session = session
        self.contactEventsUploader = contactEventsUploader
        self.statusStateMachine = statusStateMachine
        self.uiQueue = uiQueue
        
        statusViewController = StatusViewController.instantiate()
        statusViewController.inject(
            statusStateMachine: statusStateMachine,
            persistence: persistence,
            linkingIdManager: linkingIdManager,
            registrationService: registrationService,
            notificationCenter: notificationCenter,
            drawerMailbox: drawerMailbox,
            localeProvider: AutoupdatingCurrentLocaleProvider()
        )
        
        setupChecker = SetupChecker(authorizationManager: authorizationManager, bluetoothNursery: bluetoothNursery)
        
        notificationCenter.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        accessibilityChangeNotifier = AccessibilityChangeNotifier(
            notificationCenter: notificationCenter,
            uiQueue: uiQueue,
            rootViewController: self
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
        remoteNotificationManager.dispatcher.removeHandler(forType: .status)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        showFirstView()
    }
    
    // MARK: - Routing
    func showFirstView() {
        show(viewController: UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()!)
        
        let navigationController = UINavigationController()
        navigationController.pushViewController(self.statusViewController, animated: false)

        onboardingCoordinator.determineIsOnboardingRequired { onboardingIsRequired in
            self.uiQueue.async {
                if onboardingIsRequired {
                    let onboardingViewController = OnboardingViewController.instantiate()
                    let env = OnboardingEnvironment(
                        persistence: self.persistence,
                        authorizationManager: self.authorizationManager,
                        remoteNotificationManager: self.remoteNotificationManager,
                        notificationCenter: self.notificationCenter
                    )
                    
                    onboardingViewController.inject(
                        env: env,
                        coordinator: self.onboardingCoordinator,
                        bluetoothNursery: self.bluetoothNursery,
                        uiQueue: self.uiQueue
                    ) { [weak self] in
                        guard let self = self else { return }
                        self.monitor.report(.onboardingCompleted)
                        self.show(viewController: navigationController)
                        self.checkSetup()
                    }
                    
                    self.show(viewController: onboardingViewController)
                } else {
                    self.show(viewController: navigationController)
                    self.checkSetup()
                }
            }
        }
    }
    
    @objc func applicationDidBecomeActive(_ notification: NSNotification) {
        guard children.first as? OnboardingViewController == nil else {
            // The onboarding flow has its own handling for setup problems, and if we present them from here
            // during onboarding then there will likely be two of them shown at the same time.
            return
        }
        
        checkSetup()
    }
        
    private func checkSetup() {
        setupChecker.check { problem in
            self.uiQueue.sync {
                self.statusViewController.hasNotificationProblem = (problem == .notificationPermissions)
                
                guard let problem = problem else { return self.dismissSetupError() }
                
                switch problem {
                case .bluetoothOff:
                    let vc = BluetoothOffViewController.instantiate()
                    self.showSetupError(viewController: vc)
                case .bluetoothPermissions:
                    let vc = BluetoothDeniedViewController.instantiate()
                    self.showSetupError(viewController: vc)
                case .notificationPermissions:
                    break
                }
            }
        }
    }
    
    private func showSetupError(viewController: UIViewController) {
        viewController.modalPresentationStyle = .fullScreen
        presentedSetupErorrViewController = viewController
        present(viewController, animated: true)
    }
    
    private func dismissSetupError() {
        if self.presentedSetupErorrViewController != nil {
            self.dismiss(animated: true)
        }
    }
                
    // MARK: - Debug view controller management
    
    #if DEBUG || INTERNAL
    var previouslyPresentedViewController: UIViewController?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard type(of: presentedViewController) != DebugViewController.self else { return }
        
        if let vc = presentedViewController {
            previouslyPresentedViewController = vc
            dismiss(animated: true)
        }

        if motion == UIEvent.EventSubtype.motionShake {
            showDebugView()
        }
    }

    @IBAction func unwindFromDebugViewController(unwindSegue: UIStoryboardSegue) {
        dismiss(animated: true)

        statusViewController.reload()

        if let vc = previouslyPresentedViewController {
            present(vc, animated: true)
        }
    }

    private func showDebugView() {
        let storyboard = UIStoryboard(name: "Debug", bundle: Bundle(for: Self.self))
        guard let tabBarVC = storyboard.instantiateInitialViewController() as? UITabBarController,
            let navVC = tabBarVC.viewControllers?.first as? UINavigationController,
            let debugVC = navVC.viewControllers.first as? DebugViewController else { return }
        
        debugVC.inject(
            persisting: persistence,
            bluetoothNursery: bluetoothNursery,
            contactEventRepository: bluetoothNursery.contactEventRepository,
            contactEventPersister: bluetoothNursery.contactEventPersister,
            contactEventsUploader: contactEventsUploader,
            statusStateMachine: statusStateMachine
        )
        
        present(tabBarVC, animated: true)
    }
    #endif

    func show(viewController newChild: UIViewController) {
        children.first?.willMove(toParent: nil)
        children.first?.viewIfLoaded?.removeFromSuperview()
        children.first?.removeFromParent()
        addChild(newChild)
        newChild.view.frame = view.bounds
        view.addSubview(newChild.view)
        newChild.didMove(toParent: self)
    }
}
