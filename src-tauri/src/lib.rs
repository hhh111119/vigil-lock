mod auth;
mod power;

#[cfg(target_os = "macos")]
mod macos;

use auth::{hash_password, verify_password, Config};
use power::CaffeinateGuard;
use serde::Serialize;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager, State, WebviewUrl, WebviewWindowBuilder};

struct AppState {
    config_path: PathBuf,
    config: Mutex<Config>,
    locked: Mutex<bool>,
    locked_at: Mutex<u64>,
    failed: Mutex<u32>,
    backoff_until: Mutex<u64>,
    caffeinate: Mutex<Option<CaffeinateGuard>>,
}

#[derive(Serialize)]
struct Settings {
    has_password: bool,
    message: String,
    keep_awake: bool,
    locked: bool,
}

#[derive(Serialize)]
struct LockMeta {
    message: String,
    locked_at: u64,
    keep_awake: bool,
}

#[derive(Serialize)]
struct UnlockResult {
    ok: bool,
    wait_ms: u64,
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn persist(state: &AppState) -> Result<(), String> {
    state.config.lock().unwrap().save(&state.config_path)
}

fn is_locked(state: &AppState) -> bool {
    *state.locked.lock().unwrap()
}

#[tauri::command]
fn get_settings(state: State<AppState>) -> Settings {
    let cfg = state.config.lock().unwrap().clone();
    Settings {
        has_password: cfg.password_hash.is_some(),
        message: cfg.message,
        keep_awake: cfg.keep_awake,
        locked: is_locked(&state),
    }
}

#[tauri::command]
fn lock_meta(state: State<AppState>) -> LockMeta {
    let cfg = state.config.lock().unwrap().clone();
    LockMeta {
        message: cfg.message,
        locked_at: *state.locked_at.lock().unwrap(),
        keep_awake: cfg.keep_awake,
    }
}

#[tauri::command]
fn setup_password(password: String, state: State<AppState>) -> Result<(), String> {
    if password.chars().count() < 4 {
        return Err("至少 4 个字符".into());
    }
    let hash = hash_password(&password)?;
    {
        let mut cfg = state.config.lock().unwrap();
        cfg.password_hash = Some(hash);
    }
    persist(&state)
}

#[tauri::command]
fn set_message(message: String, state: State<AppState>) -> Result<(), String> {
    {
        let mut cfg = state.config.lock().unwrap();
        cfg.message = message.chars().take(80).collect();
    }
    persist(&state)
}

#[tauri::command]
fn set_keep_awake(value: bool, state: State<AppState>) -> Result<(), String> {
    {
        let mut cfg = state.config.lock().unwrap();
        cfg.keep_awake = value;
    }
    persist(&state)
}

#[tauri::command]
fn lock(app: AppHandle, state: State<AppState>) -> Result<(), String> {
    start_lock(&app, &state)
}

#[tauri::command]
fn unlock(password: String, app: AppHandle, state: State<AppState>) -> UnlockResult {
    let now = now_ms();
    let until = *state.backoff_until.lock().unwrap();
    if now < until {
        return UnlockResult {
            ok: false,
            wait_ms: until.saturating_sub(now),
        };
    }
    let hash = state.config.lock().unwrap().password_hash.clone();
    let Some(hash) = hash else {
        return UnlockResult {
            ok: false,
            wait_ms: 0,
        };
    };
    if !verify_password(&password, &hash) {
        let mut failed = state.failed.lock().unwrap();
        *failed += 1;
        let wait = (1000u64 * 2u64.pow((*failed - 1).min(3))).min(8000);
        *state.backoff_until.lock().unwrap() = now + wait;
        return UnlockResult {
            ok: false,
            wait_ms: wait,
        };
    }
    match stop_lock(&app, &state) {
        Ok(()) => UnlockResult {
            ok: true,
            wait_ms: 0,
        },
        Err(_) => UnlockResult {
            ok: false,
            wait_ms: 0,
        },
    }
}

fn start_lock(app: &AppHandle, state: &AppState) -> Result<(), String> {
    if state.config.lock().unwrap().password_hash.is_none() {
        return Err("请先设置密码".into());
    }
    if is_locked(state) {
        return Ok(());
    }

    let keep_awake = state.config.lock().unwrap().keep_awake;
    if keep_awake {
        let guard = CaffeinateGuard::start()?;
        *state.caffeinate.lock().unwrap() = Some(guard);
    }

    *state.locked.lock().unwrap() = true;
    *state.locked_at.lock().unwrap() = now_ms();
    *state.failed.lock().unwrap() = 0;
    *state.backoff_until.lock().unwrap() = 0;

    if let Some(main) = app.get_webview_window("main") {
        let _ = main.hide();
    }

    #[cfg(target_os = "macos")]
    macos::enter_kiosk();

    let monitors = app.available_monitors().unwrap_or_default();
    if monitors.is_empty() {
        open_lock_window(app, "lock-0", None)?;
    } else {
        for (i, monitor) in monitors.iter().enumerate() {
            open_lock_window(app, &format!("lock-{i}"), Some(monitor))?;
        }
    }
    Ok(())
}

fn open_lock_window(
    app: &AppHandle,
    label: &str,
    monitor: Option<&tauri::Monitor>,
) -> Result<(), String> {
    if let Some(existing) = app.get_webview_window(label) {
        let _ = existing.set_focus();
        return Ok(());
    }
    let mut builder = WebviewWindowBuilder::new(app, label, WebviewUrl::App("lock.html".into()))
        .title("Vigil")
        .decorations(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .closable(false)
        .minimizable(false)
        .maximizable(false)
        .resizable(false)
        .visible(true)
        .focused(true)
        .visible_on_all_workspaces(true)
        .accept_first_mouse(true);

    if let Some(monitor) = monitor {
        let sf = monitor.scale_factor();
        let size = monitor.size();
        let pos = monitor.position();
        builder = builder
            .inner_size(size.width as f64 / sf, size.height as f64 / sf)
            .position(pos.x as f64 / sf, pos.y as f64 / sf);
    } else {
        builder = builder.fullscreen(true);
    }

    let window = builder.build().map_err(|e| e.to_string())?;
    window.on_window_event(|event| {
        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
        }
    });

    #[cfg(target_os = "macos")]
    macos::shield_window(&window)?;

    let _ = window.set_always_on_top(true);
    let _ = window.set_focus();
    Ok(())
}

fn stop_lock(app: &AppHandle, state: &AppState) -> Result<(), String> {
    *state.caffeinate.lock().unwrap() = None;
    *state.locked.lock().unwrap() = false;
    *state.failed.lock().unwrap() = 0;
    *state.backoff_until.lock().unwrap() = 0;

    #[cfg(target_os = "macos")]
    macos::exit_kiosk();

    let labels: Vec<String> = app
        .webview_windows()
        .into_keys()
        .filter(|label| label.starts_with("lock-"))
        .collect();
    for label in labels {
        if let Some(window) = app.get_webview_window(&label) {
            let _ = window.destroy();
        }
    }
    if let Some(main) = app.get_webview_window("main") {
        let _ = main.show();
        let _ = main.set_focus();
    }
    Ok(())
}

fn lock_from_tray(app: &AppHandle) {
    let state = app.state::<AppState>();
    let _ = start_lock(app, &state);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let path = app
                .path()
                .app_config_dir()
                .unwrap_or_else(|_| std::env::temp_dir().join("vigil"))
                .join("config.json");
            let config = Config::load(&path);
            app.manage(AppState {
                config_path: path,
                config: Mutex::new(config),
                locked: Mutex::new(false),
                locked_at: Mutex::new(0),
                failed: Mutex::new(0),
                backoff_until: Mutex::new(0),
                caffeinate: Mutex::new(None),
            });

            let lock_item = MenuItem::with_id(app, "lock", "锁定", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&lock_item, &quit_item])?;
            let mut tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("Vigil 守夜")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "lock" => lock_from_tray(app),
                    "quit" => {
                        let locked = is_locked(&app.state::<AppState>());
                        if !locked {
                            app.exit(0);
                        }
                    }
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            tray.build(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            lock_meta,
            setup_password,
            set_message,
            set_keep_awake,
            lock,
            unlock
        ])
        .build(tauri::generate_context!())
        .expect("failed to build Vigil")
        .run(|app, event| {
            if let tauri::RunEvent::ExitRequested { api, .. } = event {
                if is_locked(&app.state::<AppState>()) {
                    api.prevent_exit();
                }
            }
        });
}
