//
//  Sound.swift
//  zmk-companion
//
//  Created by Jeff on 9/14/24.
//
///**********************************************************************
/// Belowing is an all-in-one version of https://github.com/badjeff/ISSoundAdditions
///**********************************************************************

//
//  SoundOutputManager.swift
//  Created by Alessio Moiso on 08.03.22.
//

import CoreAudio
import AudioToolbox
import Cocoa
import CoreServices

/// Entry point to access and modify the system sound settings, such
/// muting/unmuting and changing the volume.
///
/// # Overview
/// This class cannot be instantiated, but you can interact with its `output` property directly.
/// You can use the shared instance to change the output volume as well as
/// mute and unmute.
public enum Sound {
  public static let output = SoundOutputManager()
}

extension Sound {
  /// Mute, unmute and change the volume of the system default output device.
  ///
  /// # Overview
  /// You can interact with this class in two ways:
  /// - you can interact with its properties, meaning that all changes
  /// will be applied immediately and errors will be hidden.
  /// - you can call its methods and handle errors manually.
  public final class SoundOutputManager {
    /// All the possible errors that could occur while interacting
    /// with the default output device.
    enum Errors: Error {
            /// The system couldn't complete the requested operation and
            /// returned the given status.
      case  operationFailed(OSStatus)
            /// The current default output device doesn't support the requested property.
      case  unsupportedProperty
            /// The current default output device doesn't allow changing the requested property.
      case  immutableProperty
            /// There is no default output device.
      case  noDevice
    }
    
    internal init() { }
    
    /// Get the system default output device.
    ///
    /// You can use this value to interact with the device directly
    /// via other system calls.
    ///
    /// - throws: `Errors.operationFailed` if the system fails to return the default output device.
    /// - returns: the default device ID or `nil` if none is set.
    public func retrieveDefaultOutputDevice() throws -> AudioDeviceID? {
      var result = kAudioObjectUnknown
      var size = UInt32(MemoryLayout<AudioDeviceID>.size)
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )
      
      // Ensure that a default device exists.
      guard AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &address) else { return nil }
      
      // Attempt to get the default output device.
      let error = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &result)
      guard error == noErr else {
        throw Errors.operationFailed(error)
      }
      
      if result == kAudioObjectUnknown {
        throw Errors.noDevice
      }
      
      return result
    }
      
    /// Get the volume of the system default output device.
    ///
    /// - throws: `Errors.noDevice` if the system doesn't have a default output device; `Errors.unsupportedProperty` if the current device doesn't have a volume property; `Errors.operationFailed` if the system is unable to read the property value.
    /// - returns: The current volume in a range between 0 and 1.
    public func readVolume() throws -> Float {
      guard let deviceID = try retrieveDefaultOutputDevice() else {
        throw Errors.noDevice
      }
      
      var size = UInt32(MemoryLayout<Float32>.size)
      var volume: Float = 0
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
      )
      
      // Ensure the device has a volume property.
      guard AudioObjectHasProperty(deviceID, &address) else {
        throw Errors.unsupportedProperty
      }
      
      let error = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
      guard error == noErr else {
        throw Errors.operationFailed(error)
      }
      
      return min(max(0, volume), 1)
    }
    
    /// Set the volume of the system default output device.
    ///
    /// - parameter newValue: The volume to set in a range between 0 and 1.
    /// - throws: `Erors.noDevice` if the system doesn't have a default output device; `Errors.unsupportedProperty` or `Errors.immutableProperty` if the output device doesn't support setting or doesn't currently allow changes to its volume; `Errors.operationFailed` if the system is unable to apply the volume change.
    public func setVolume(_ newValue: Float) throws {
      guard let deviceID = try retrieveDefaultOutputDevice() else {
        throw Errors.noDevice
      }
      
      var normalizedValue = min(max(0, newValue), 1)
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
      )
      
      // Ensure the device has a volume property.
      guard AudioObjectHasProperty(deviceID, &address) else {
        throw Errors.unsupportedProperty
      }
      
      var canChangeVolume = DarwinBoolean(true)
      let size = UInt32(MemoryLayout<Float>.size(ofValue: normalizedValue))
      let isSettableError = AudioObjectIsPropertySettable(deviceID, &address, &canChangeVolume)
      
      // Ensure the volume property is editable.
      guard isSettableError == noErr else {
        throw Errors.operationFailed(isSettableError)
      }
      guard canChangeVolume.boolValue else {
        throw Errors.immutableProperty
      }
      
      let error = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &normalizedValue)
      
      if error != noErr {
        throw Errors.operationFailed(error)
      }
    }
    
    /// Get whether the system default output device is currently muted or not.
    ///
    /// - throws: `Errors.noDevice` if the system doesn't have a default output device;
    /// `Errors.unsupportedProperty` if the current device doesn't have a mute property;
    /// `Errors.operationFailed` if the system is unable to read the property value.
    /// - returns: Whether the device is muted or not.
    public func readMute() throws -> Bool {
      guard let deviceID = try retrieveDefaultOutputDevice() else {
        throw Errors.noDevice
      }
      
      var isMuted: UInt32 = 0
      var size = UInt32(MemoryLayout<UInt32>.size(ofValue: isMuted))
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
      )
      
      // Ensure the device supports the option to be muted.
      guard AudioObjectHasProperty(deviceID, &address) else {
        throw Errors.unsupportedProperty
      }
      
      let error = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isMuted)
      
      guard error == noErr else {
        throw Errors.operationFailed(error)
      }
      
      return isMuted == 1
    }
    
    /// Mute or unmute the system default output device.
    ///
    /// - parameter isMuted: Mute or unmute.
    /// - throws: `Errors.noDevice` if the system doesn't have a default output device;
    /// `Errors.unsupportedProperty` or `Errors.immutableProperty` if the output device doesn't
    /// support setting or doesn't currently allow changes to its mute property; `Errors.operationFailed`
    /// if the system is unable to apply the change.
    public func mute(_ isMuted: Bool) throws {
      guard let deviceID = try retrieveDefaultOutputDevice() else {
        throw Errors.noDevice
      }
      
      var normalizedValue: UInt = isMuted ? 1 : 0
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
      )
      
      // Ensure the device supports the option to be muted.
      guard AudioObjectHasProperty(deviceID, &address) else {
        throw Errors.unsupportedProperty
      }
      
      var canMute = DarwinBoolean(true)
      let size = UInt32(MemoryLayout<UInt>.size(ofValue: normalizedValue))
      let isSettableError = AudioObjectIsPropertySettable(deviceID, &address, &canMute)
      
      // Ensure that the mute property is editable.
      guard isSettableError == noErr, canMute.boolValue else {
        throw Errors.immutableProperty
      }
      
      let error = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &normalizedValue)
      
      if error != noErr {
        throw Errors.operationFailed(error)
      }
    }

    public var didAudioDevicesChanged: (() -> Void)? = nil
    var hasObserverForDidAudioDevicesChanged: Bool = false
    
    @objc
    private func handleNotification(_ notification: Notification) {
      if notification.name == AudioDevicNotification.audioDevicesDidChange.notificationName {
        self.didAudioDevicesChanged?()
      }
    }

    public func addAudioDevicesChangeObserver() throws {
      guard let deviceID = try retrieveDefaultOutputDevice() else {
        throw Errors.noDevice
      }
        if !self.hasObserverForDidAudioDevicesChanged {
          var listenerAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertySelectorWildcard,
            mScope: kAudioObjectPropertyScopeWildcard,
            mElement: kAudioObjectPropertyElementWildcard
          )
          var propListener: AudioObjectPropertyListenerProc = { _, _, _, _ in
            NotificationCenter.post(audioDevicNotification: .audioDevicesDidChange)
            return 0
          }
          NotificationCenter.addObserver(observer: self,
                                         selector: #selector(handleNotification(_:)),
                                         name: .audioDevicesDidChange)
          let error = AudioObjectAddPropertyListener(deviceID, &listenerAddr, propListener, nil)
          guard error == noErr else {
            throw Errors.operationFailed(error)
          }
          self.hasObserverForDidAudioDevicesChanged = true
        }
      }
            
  }
}

enum AudioDevicNotification: String {
  case audioDevicesDidChange
  var stringValue: String {
    return "AudioDevicNotification_" + rawValue
  }
  var notificationName: NSNotification.Name {
    return NSNotification.Name(stringValue)
  }
}

extension NotificationCenter {
  static func post(audioDevicNotification name: AudioDevicNotification, object: Any? = nil) {
    NotificationCenter.default.post(name: name.notificationName, object: object)
  }
  static func addObserver(observer: Any, selector: Selector, name: AudioDevicNotification, object: Any? = nil) {
    NotificationCenter.default.addObserver(observer, selector: selector, name: name.notificationName, object: object)
  }
  static func removeObserver(observer: Any, name: AudioDevicNotification, object: Any? = nil) {
    NotificationCenter.default.removeObserver(observer, name: name.notificationName, object: object)
  }
}

public extension Sound.SoundOutputManager {
  /// Increase the volume of the default output device
  /// by the given amount.
  ///
  /// Errors will be ignored.
  ///
  /// The values range between 0 and 1. If the increase results
  /// in a value outside of the bounds, it will be normalized to the closest
  /// value in the bounds.
  func increaseVolume(by value: Float, autoMuteUnmute: Bool = false, muteThreshold: Float = 0.005) {
    setVolume(volume+value, autoMuteUnmute: autoMuteUnmute, muteThreshold: muteThreshold)
  }
  
  /// Decrease the volume of the default output device
  /// by the given amount.
  ///
  /// Errors will be ignored.
  ///
  /// The values range between 0 and 1. If the decrease results
  /// in a value outside of the bounds, it will be normalized to the closest
  /// value in the bounds.
  func decreaseVolume(by value: Float, autoMuteUnmute: Bool = false, muteThreshold: Float = 0.005) {
    setVolume(volume-value, autoMuteUnmute: autoMuteUnmute, muteThreshold: muteThreshold)
  }
  
  /// Set the volume of the default output device and,
  /// if lower or higher then `muteThreshold` also toggles the mute property.
  ///
  /// - warning: This function will unmute a muted device, if the volume is greater
  /// then `muteThreshold`. Please, make sure that the user is aware of this and always
  /// respect the Do Not Disturb modes and other system settings.
  ///
  /// - parameters:
  ///   - newValue: The volume.
  ///   - autoMuteUnmute: If `true`, will use the `muteThreshold` to determine whether the device
  ///   should also be muted or unmuted.
  ///   - muteThreshold: Defines the threshold that should cause an automatic mute for all values below it.
  func setVolume(_ newValue: Float, autoMuteUnmute: Bool, muteThreshold: Float = 0.005) {
    volume = newValue
    guard autoMuteUnmute else { return }
    isMuted = newValue <= muteThreshold
  }
}

public extension Sound.SoundOutputManager {
  /// Get the system default output device.
  ///
  /// You can use this value to interact with the device directly via
  /// other system calls.
  ///
  /// This value will return `nil` if there is currently no device selected in
  /// System Preferences > Sound > Output.
  var defaultOutputDevice: AudioDeviceID? {
    try? retrieveDefaultOutputDevice()
  }
  
  /// Get or set the volume of the default output device.
  ///
  /// Errors will be ignored. If you need to handle errors,
  /// use `readVolume` and `setVolume`.
  ///
  /// The values range between 0 and 1.
  var volume: Float {
    get {
      (try? readVolume()) ?? 0
    }
    set {
      do {
        try setVolume(newValue)
      } catch { }
    }
  }
  
  /// Get or set whether the system default output device is muted or not.
  ///
  /// Errors will be ignored. If you need to handle errors,
  /// use `readMute` and `mute`. Devices that do not support muting
  /// will always return `false`.
  var isMuted: Bool {
    get {
      (try? readMute()) ?? false
    }
    set {
      do {
        try mute(newValue)
      } catch { }
    }
  }
}
