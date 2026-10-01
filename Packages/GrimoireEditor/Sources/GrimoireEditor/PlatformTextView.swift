#if os(macOS)
import AppKit

/// The TextKit 2 text view the editor engine drives on this platform.
public typealias PlatformTextView = NSTextView
#elseif os(iOS)
import UIKit

/// The TextKit 2 text view the editor engine drives on this platform.
public typealias PlatformTextView = UITextView
#endif
