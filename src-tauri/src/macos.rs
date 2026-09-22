#![cfg(target_os = "macos")]

use cocoa::appkit::{
    NSApp, NSApplication, NSApplicationPresentationOptions, NSWindow, NSWindowCollectionBehavior,
};
use cocoa::base::{id, NO};
use objc::{msg_send, sel, sel_impl};
use tauri::WebviewWindow;

const NS_SCREENSAVER_WINDOW_LEVEL: i64 = 1000;

pub fn shield_window(window: &WebviewWindow) -> Result<(), String> {
    let raw = window.ns_window().map_err(|e| e.to_string())?;
    unsafe {
        let ns_window: id = raw as id;
        ns_window.setLevel_(NS_SCREENSAVER_WINDOW_LEVEL);
        ns_window.setCollectionBehavior_(
            NSWindowCollectionBehavior::NSWindowCollectionBehaviorCanJoinAllSpaces
                | NSWindowCollectionBehavior::NSWindowCollectionBehaviorFullScreenAuxiliary
                | NSWindowCollectionBehavior::NSWindowCollectionBehaviorStationary
                | NSWindowCollectionBehavior::NSWindowCollectionBehaviorIgnoresCycle,
        );
        ns_window.setHidesOnDeactivate_(NO);
        ns_window.setCanHide_(NO);
        ns_window.setAcceptsMouseMovedEvents_(cocoa::base::YES);
        let _: () = msg_send![ns_window, makeKeyAndOrderFront: cocoa::base::nil];
    }
    Ok(())
}

pub fn enter_kiosk() {
    unsafe {
        let app = NSApp();
        let opts = NSApplicationPresentationOptions::NSApplicationPresentationHideDock
            | NSApplicationPresentationOptions::NSApplicationPresentationHideMenuBar
            | NSApplicationPresentationOptions::NSApplicationPresentationDisableAppleMenu
            | NSApplicationPresentationOptions::NSApplicationPresentationDisableProcessSwitching
            | NSApplicationPresentationOptions::NSApplicationPresentationDisableForceQuit
            | NSApplicationPresentationOptions::NSApplicationPresentationDisableSessionTermination
            | NSApplicationPresentationOptions::NSApplicationPresentationDisableHideApplication;
        app.setPresentationOptions_(opts);
    }
}

pub fn exit_kiosk() {
    unsafe {
        let app = NSApp();
        app.setPresentationOptions_(NSApplicationPresentationOptions::NSApplicationPresentationDefault);
    }
}
