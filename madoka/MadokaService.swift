//
//  MadokaService.swift
//  madoka
//
//  Created by mtgto on 2015/07/22.
//  Copyright (c) 2015 mtgto. All rights reserved.
//

import Cocoa
import RealmSwift

class MadokaService: NSObject {
    private typealias StatisticTuple = (applicationIdentifier: String, since: NSTimeInterval, duration: NSTimeInterval)

    static let sharedInstance = MadokaService()
    
    struct UsingApplication {
        let applicationIdentifier: String
        let localizedName: String
        let since: NSDate
    }
    
    private var usingApp: UsingApplication? = nil
    
    private var localizedNames: [String: String] = [String: String]()

    private let ignoreApplicationIdentifiers: Set<String> = ["com.apple.loginwindow"]
    
    /**
     * Tuple of (Application bundle's identifier, since (TimeIntervalSinceReferenceDate), duration)
     *
     * It contains only today's statistics.
     * If you need to use older statistics, use realm.
     */
    private var statistics: Array<StatisticTuple> = []
    
    override init() {
        super.init()
        let realm = try! Realm()
        self.localizedNames = Array<LocalizedName>(realm.objects(LocalizedName))
            .reduce([String: String]()) { (var dict, element: LocalizedName) in
                dict[element.applicationIdentifier] = element.localizedName; return dict
            }
        self.statistics = Array<Statistic>(realm.objects(Statistic))
            .map {
                (applicationIdentifier: $0.applicationIdentifier, since: $0.start.timeIntervalSinceReferenceDate, $0.end.timeIntervalSinceDate($0.start))
            }
        debugPrint(self.localizedNames)
    }
    
    /**
     * Be invoked from NSNotifacionCenter when active application has changed.
     */
    func didActivateApplication(notification: NSNotification?) {
        if let userInfo: [String: AnyObject] = notification?.userInfo as? [String: AnyObject] {
            if let application: NSRunningApplication = userInfo[NSWorkspaceApplicationKey] as? NSRunningApplication {
                self.applicationChanged(application)
            }
        }
    }

    /**
     * Be invoked from NSNotifacionCenter when computer is going to sleep.
     */
    func willSleep(notification: NSNotification?) {
        debugPrint("willSleep")
        applicationChanged(nil)
    }

    /**
     * Be invoked from NSNotifacionCenter when computer wake.
     */
    func didWake(notification: NSNotification?) {
        debugPrint("didWake")
        if let application = NSWorkspace.sharedWorkspace().frontmostApplication {
            applicationChanged(application)
        }
    }

    func willTerminate() {
        debugPrint("willTerminate")
        applicationChanged(nil)
    }

    /**
     * Notify when current application changed.
     */
    func applicationChanged(application: NSRunningApplication?) {
        let current = NSDate()
        if let lastApplication = self.usingApp {
            let duration: NSTimeInterval = current.timeIntervalSinceDate(lastApplication.since)
            self.updateUsingApp(lastApplication, duration: duration)
        }
        if let application = application {
            if let applicationIdentifier = application.bundleIdentifier {
                if let localizedName: String = application.localizedName {
                    debugPrint("localizedName: ", localizedName, applicationIdentifier)
                    self.localizedNames[applicationIdentifier] = localizedName
                    self.usingApp = UsingApplication(applicationIdentifier: applicationIdentifier, localizedName: localizedName, since: current)
                }
            }
        } else {
            self.usingApp = nil
        }
    }

    func usedAppsSince(since: NSDate, to: NSDate) -> [(name: String, duration: NSTimeInterval)] {
        let sinceReference = since.timeIntervalSinceReferenceDate
        let toReference = to.timeIntervalSinceReferenceDate
        return self.currentStatistics().reduce([String: NSTimeInterval]()) { (var dict: [String: NSTimeInterval], stat) in
            let duration = min(stat.since + stat.duration, toReference) - max(sinceReference, stat.since)
            if duration > 0 && !self.ignoreApplicationIdentifiers.contains(stat.applicationIdentifier) {
                if let lastDuration: NSTimeInterval = dict[stat.applicationIdentifier] {
                    dict[stat.applicationIdentifier] = duration + lastDuration
                } else {
                    dict[stat.applicationIdentifier] = duration
                }
            }
            return dict
        }.sort {
            return $0.1 > $1.1
        }.map {
            return (name: self.localizedNames[$0.0]!, duration: $0.1)
        }
    }

    /**
     * Statistics with current application.
     */
    private func currentStatistics() -> [StatisticTuple] {
        if let usingApplication = self.usingApp {
            return self.statistics + [(applicationIdentifier: usingApplication.applicationIdentifier, since: usingApplication.since.timeIntervalSinceReferenceDate, duration: -usingApplication.since.timeIntervalSinceNow)]
        } else {
            return self.statistics
        }
    }
    
    private func updateUsingApp(lastUsingApp: UsingApplication, duration: NSTimeInterval) {
        let realm = try! Realm()
        let statistic: Statistic = Statistic(start: lastUsingApp.since, end: lastUsingApp.since.dateByAddingTimeInterval(duration), applicationIdentifier: lastUsingApp.applicationIdentifier)
        let localizedName: LocalizedName = LocalizedName(applicationIdentifier: lastUsingApp.applicationIdentifier, localizedName: lastUsingApp.localizedName)
        try! realm.write {
            realm.add(statistic)
            realm.add(localizedName, update: true)
        }
        self.statistics.append(applicationIdentifier: lastUsingApp.applicationIdentifier, since: lastUsingApp.since.timeIntervalSinceReferenceDate, duration: duration)
    }
}
