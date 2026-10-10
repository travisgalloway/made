import Foundation
import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformView = NSView
public typealias PlatformPoint = NSPoint
public typealias PlatformEvent = NSEvent
#elseif os(iOS)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformView = UIView
public typealias PlatformPoint = CGPoint
public typealias PlatformEvent = UIEvent
#endif

public enum UniversalPlatform {
    public static var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    public static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}
