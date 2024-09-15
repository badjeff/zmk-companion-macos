//
//  Hid.swift
//  zmk-companion
//
//  Created by Jeff on 9/13/24.
//

import SwiftUI
import IOKit
import IOKit.hid

public enum Hid {
    public static let manager = HIDManager.shared
}

public class HIDManager {
    static let shared = HIDManager()

    var manager: IOHIDManager!
    var hasManager: Bool = false
    
    @Published var device: IOHIDDevice?
    @Published var isOpen: Bool?

    public struct HIDDeviceInfo {
        let Transport: String
        let VendorID: Int
        let ProductID: Int
        let Product: String
        let PrimaryUsagePage: Int
        let PrimaryUsage: Int
        let ReportInterval: Int
    }
    @Published var hidDevices: [HIDDeviceInfo]

    private init() {
        self.hidDevices = []
    }
    
    func openShareManger() -> IOHIDManager {
        if !hasManager {
            manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            // IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hasManager = true
        }
        return manager
    }
    
    func closeSharedManager() {
        if hasManager {
            if let manager = self.manager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            hasManager = false
        }
    }

    func listHIDDevices(printLog: Bool) {
        self.hidDevices = []

        let manager = openShareManger()
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("Failed to open HID Manager")
        }
        IOHIDManagerSetDeviceMatching(manager, nil)
        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in deviceSet {
                if let deviceInfo = getDeviceInfo(device) {
                    hidDevices.append(deviceInfo)
                }
            }
        }
        if (printLog) {
            for hid in self.hidDevices {
                print(hid.Product, hid.VendorID, hid.ProductID, hid.PrimaryUsagePage, hid.PrimaryUsage)
            }
        }
    }

    private func getDeviceInfo(_ device: IOHIDDevice) -> HIDDeviceInfo? {
        guard let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String,
              let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
              let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
              let primaryUsagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int,
              let primaryUsage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int,
              let reportInterval = IOHIDDeviceGetProperty(device, kIOHIDReportIntervalKey as CFString) as? Int else {
            return nil
        }
        return HIDDeviceInfo(
            Transport: transport,
            VendorID: vendorID,
            ProductID: productID,
            Product: product,
            PrimaryUsagePage: primaryUsagePage,
            PrimaryUsage: primaryUsage,
            ReportInterval: reportInterval
        )
    }
    
    func openHID(vid: Int, pid: Int, productKey: String, usagePage: Int, usage: Int) {
        let manager = openShareManger()
        let deviceMatching: [String: Any] = [
            kIOHIDVendorIDKey: vid,
            kIOHIDProductIDKey: pid,
            kIOHIDProductKey: productKey,
            kIOHIDPrimaryUsagePageKey: usagePage,
            kIOHIDPrimaryUsageKey: usage
        ]
        IOHIDManagerSetDeviceMatching(manager, deviceMatching as CFDictionary)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("Failed to open HID Manager")
            return
        }
        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let matchedDevice = deviceSet.first {
            self.openHID(device: matchedDevice)
        } else {
            self.isOpen = nil
        }
    }
    
    func openHID(device inDevice: IOHIDDevice) {
        let openResult = IOHIDDeviceOpen(inDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            self.device = inDevice
            self.isOpen = true
        } else {
            self.isOpen = false
        }
    }
    
    func closeHID() {
        if let device = self.device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        // print("HID Manager closed")
        self.isOpen = false
    }
    
    func sendHIDReport(report: [UInt8]) {
        guard let device = self.device else { return }
        let reportId = report[0]
        var report = report
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportId), &report, report.count)
        if result == kIOReturnSuccess {
            // print("HID Report sent: \(report)")
        } else {
            print("Failed to send HID Report")
        }
    }

    func readHIDReport(reportId: Int, reportLength: Int) -> [UInt8] {
        guard let device = self.device else { return [] }
        var report = [UInt8](repeating: 0, count: reportLength)  // count = report buffer length
        var reportLength = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, CFIndex(reportId), &report, &reportLength)
        if result == kIOReturnSuccess {
            // print("HID Report read: \(report)")
        } else {
            print("Failed to read HID Report")
        }
        return report
    }

    public var didHidDevicesAdded: ((IOHIDDevice) -> Void)? = nil
    public var didHidDevicesRemoved: ((IOHIDDevice) -> Void)? = nil
    var hasObserverForDidHidDevicesAddedOrRemoved: Bool = false

    public var didHidDevicesReported: ((Int) -> Void)? = nil
    var hasObserverForDidHidDevicesReported: Bool = false
    
    @objc
    private func handleHidDeviceNotification(_ notification: Notification) {
        if notification.name == HidDevicNotification.hidDevicesDidAdd.notificationName {
            guard let object = notification.object as? [String: Any?] else { return }
            let device: IOHIDDevice = object["device"] as! IOHIDDevice
            self.didHidDevicesAdded?(device)
        }
        if notification.name == HidDevicNotification.hidDevicesDidRemove.notificationName {
            guard let object = notification.object as? [String: Any?] else { return }
            let device: IOHIDDevice = object["device"] as! IOHIDDevice
            self.didHidDevicesRemoved?(device)
        }
        if notification.name == HidDevicNotification.hidDevicesDidReport.notificationName {
            guard let object = notification.object as? [String: Any?] else { return }
            guard let reportId = object["reportId"] as? Int else { return }
            self.didHidDevicesReported?(reportId)
        }
    }
    
    public func addHidDevicesAddRemoveObserver(vid: Int, pid: Int, productKey: String,
                                               usagePage: Int, usage: Int) throws {
    
        if !self.hasObserverForDidHidDevicesAddedOrRemoved {
            NotificationCenter.addObserver(observer: self,
                                           selector: #selector(handleHidDeviceNotification(_:)),
                                           name: .hidDevicesDidAdd)
            NotificationCenter.addObserver(observer: self,
                                           selector: #selector(handleHidDeviceNotification(_:)),
                                           name: .hidDevicesDidRemove)

            let manager = openShareManger()
            var deviceMatches:[[String:Any]] = []
            let match: [String:Any] = [
                kIOHIDVendorIDKey: vid,
                kIOHIDProductIDKey: pid,
                kIOHIDProductKey: productKey,
                kIOHIDPrimaryUsagePageKey: usagePage,
                kIOHIDPrimaryUsageKey: usage
            ]
            deviceMatches.append(match)
            IOHIDManagerSetDeviceMatchingMultiple(manager, deviceMatches as CFArray)
                        
            let matchingCallback: IOHIDDeviceCallback = {
                inContext, inResult, inSender, inIOHIDDeviceRef in
                // let this: HIDManager = unsafeBitCast(inContext, to: HIDManager.self)
                NotificationCenter.post(hidDevicNotification: .hidDevicesDidAdd,
                                        object: [ "device": inIOHIDDeviceRef ])
            }
            
            let removalCallback: IOHIDDeviceCallback = {
                inContext, inResult, inSender, inIOHIDDeviceRef in
                // let this: HIDManager = unsafeBitCast(inContext, to: HIDManager.self)
                NotificationCenter.post(hidDevicNotification: .hidDevicesDidRemove,
                                        object: [ "device": inIOHIDDeviceRef ])
            }
            IOHIDManagerRegisterDeviceMatchingCallback(manager, matchingCallback, 
                                                       unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
            IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, 
                                                      unsafeBitCast(self, to: UnsafeMutableRawPointer.self))

            self.hasObserverForDidHidDevicesAddedOrRemoved = true
        }
    }

    public func removeHidDevicesAddRemoveObserver() throws {
        if self.hasObserverForDidHidDevicesAddedOrRemoved {
            NotificationCenter.removeObserver(observer: self, name: .hidDevicesDidAdd, object: nil)
            NotificationCenter.removeObserver(observer: self, name: .hidDevicesDidRemove, object: nil)
            self.hasObserverForDidHidDevicesAddedOrRemoved = true
        }
    }
    
    public func addHidDeviceReportObserver() throws {
        guard let device = self.device else { return }
        if !self.hasObserverForDidHidDevicesReported {
            NotificationCenter.addObserver(observer: self,
                                           selector: #selector(handleHidDeviceNotification(_:)),
                                           name: .hidDevicesDidReport)
            
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
            
            let report = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            let inputCallback : IOHIDReportCallback = {
                inContext, inResult, inSender, inType, inReportId, inReport, inReportLength in
                // let this: HIDManager = unsafeBitCast(inContext, to: HIDManager.self)
                if inResult == kIOReturnSuccess {
                    NotificationCenter.post(hidDevicNotification: .hidDevicesDidReport, 
                                            object: [ "reportId": inReportId ])
                }
            }
            IOHIDDeviceRegisterInputReportCallback(device, report, 1, inputCallback,
                                                   unsafeBitCast(self, to: UnsafeMutableRawPointer.self))

            self.hasObserverForDidHidDevicesReported = true
        }
    }
    
    public func removeHidDeviceReportObserver() throws {
        if self.hasObserverForDidHidDevicesReported {
            NotificationCenter.removeObserver(observer: self, name: .hidDevicesDidReport, object: nil)
            self.hasObserverForDidHidDevicesReported = false
        }
    }

}

enum HidDevicNotification: String {
    case hidDevicesDidAdd
    case hidDevicesDidRemove
    case hidDevicesDidReport
    var stringValue: String {
        return "HidDevicNotification_" + rawValue
    }
    var notificationName: NSNotification.Name {
        return NSNotification.Name(stringValue)
    }
}

extension NotificationCenter {
    static func post(hidDevicNotification name: HidDevicNotification, object: Any? = nil) {
        NotificationCenter.default.post(name: name.notificationName, object: object)
    }
    static func addObserver(observer: Any, selector: Selector, name: HidDevicNotification, object: Any? = nil) {
        NotificationCenter.default.addObserver(observer, selector: selector, name: name.notificationName, object: object)
    }
    static func removeObserver(observer: Any, name: HidDevicNotification, object: Any? = nil) {
        NotificationCenter.default.removeObserver(observer, name: name.notificationName, object: object)
    }
}
