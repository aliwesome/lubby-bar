// On Windows release builds, don't pop a console window.
#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::io::Read;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, Rect, WebviewWindow, WindowEvent};

use lubby_core::{aggregate, claude_settings_path, live_sessions, status_path, Status};

#[derive(Serialize, Clone)]
struct SessionView {
    id: String,
    status: String,
    project: Option<String>,
    agent: String,
}

#[derive(Serialize, Clone)]
struct StatusView {
    overall: String,
    sessions: Vec<SessionView>,
}

fn status_key(s: Status) -> &'static str {
    match s {
        Status::Running => "running",
        Status::WaitingInput => "waiting_input",
        Status::Stopped => "stopped",
        Status::Idle => "idle",
    }
}

fn current_status() -> StatusView {
    let rows = live_sessions(&status_path());
    let statuses: Vec<Status> = rows
        .iter()
        .map(|(_, s)| Status::from_raw(&s.status))
        .collect();
    let overall = aggregate(&statuses);
    StatusView {
        overall: status_key(overall).to_string(),
        sessions: rows
            .into_iter()
            .map(|(id, s)| SessionView {
                id,
                status: status_key(Status::from_raw(&s.status)).to_string(),
                project: s.project,
                agent: s.agent,
            })
            .collect(),
    }
}

/// Exposed to the panel UI; it polls this every few seconds.
#[tauri::command]
fn get_status() -> StatusView {
    current_status()
}

/// Whether our Claude Code hook is registered in `~/.claude/settings.json`.
#[tauri::command]
fn hook_status() -> bool {
    lubby_core::hook_installed(&claude_settings_path())
}

/// Register the hook (so sessions start flowing) and return the new state.
#[tauri::command]
fn install_hook() -> Result<bool, String> {
    let exe = std::env::current_exe()
        .map_err(|e| format!("Could not locate the app: {e}"))?
        .to_string_lossy()
        .into_owned();
    lubby_core::install_hook(&exe, &claude_settings_path())
        .map_err(|e| format!("Could not write Claude settings: {e}"))?;
    Ok(true)
}

/// Remove the hook and return the new state.
#[tauri::command]
fn uninstall_hook() -> Result<bool, String> {
    lubby_core::uninstall_hook(&claude_settings_path())
        .map_err(|e| format!("Could not write Claude settings: {e}"))?;
    Ok(false)
}

/// When the panel last auto-hid on focus loss, in unix millis. Clicking the
/// tray icon while the panel is open first blurs it (mouse-down steals focus,
/// the blur handler hides it) and then delivers the click (mouse-up), which
/// would instantly re-show it; this timestamp lets the click handler tell that
/// sequence apart from a genuine "open the panel" click.
static LAST_BLUR_HIDE_MS: AtomicU64 = AtomicU64::new(0);

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// The flyout anchor for a tray click: the top-center of the tray icon's own
/// bounds. Preferred over the cursor position because it also works when the
/// icon is activated from the keyboard (Win+B, Enter), which reports no
/// meaningful cursor position. None when the OS sent a degenerate rect.
fn rect_anchor(app: &AppHandle, rect: &Rect) -> Option<PhysicalPosition<f64>> {
    // The tray rect is physical on Windows; the scale factor only matters for
    // the logical fallback, where the primary monitor is the best guess.
    let scale = app
        .primary_monitor()
        .ok()
        .flatten()
        .map(|m| m.scale_factor())
        .unwrap_or(1.0);
    let pos = rect.position.to_physical::<i32>(scale);
    let size = rect.size.to_physical::<u32>(scale);
    if pos.x == 0 && pos.y == 0 && size.width == 0 && size.height == 0 {
        return None;
    }
    Some(PhysicalPosition::new(
        pos.x as f64 + size.width as f64 / 2.0,
        pos.y as f64,
    ))
}

/// Place the panel as a flyout hugging the anchor, clamped to the anchor
/// monitor's work area so it never sits off-screen or under the taskbar,
/// whichever edge the taskbar is on.
fn position_panel(win: &WebviewWindow, anchor: Option<PhysicalPosition<f64>>) {
    let Ok(size) = win.outer_size() else { return };
    let app = win.app_handle();

    // The monitor under the anchor. The panel itself is hidden (possibly at a
    // stale position), so current_monitor() would be wrong on multi-display.
    let monitor = anchor
        .and_then(|a| app.monitor_from_point(a.x, a.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    let Some(monitor) = monitor else { return };

    let area = monitor.work_area();
    let margin = 8.0 * monitor.scale_factor();
    let min_x = area.position.x as f64 + margin;
    let min_y = area.position.y as f64 + margin;
    let max_x = area.position.x as f64 + area.size.width as f64 - size.width as f64 - margin;
    let max_y = area.position.y as f64 + area.size.height as f64 - size.height as f64 - margin;

    // No usable anchor (keyboard activation on some builds): the work area's
    // bottom-right corner, where the tray lives on a default taskbar.
    let anchor = anchor.unwrap_or(PhysicalPosition::new(
        max_x + size.width as f64,
        max_y + size.height as f64,
    ));

    // Right-align to the anchor and open above it; the clamp flips it inside
    // the work area when the taskbar is on the top or left instead.
    let x = (anchor.x - size.width as f64).clamp(min_x.min(max_x), max_x.max(min_x));
    let y = (anchor.y - size.height as f64 - margin).clamp(min_y.min(max_y), max_y.max(min_y));
    let _ = win.set_position(PhysicalPosition::new(x, y));
}

/// Toggle the panel: hide if visible, else position it by the tray and show it.
fn toggle_panel(win: &WebviewWindow, anchor: Option<PhysicalPosition<f64>>) {
    if win.is_visible().unwrap_or(false) {
        let _ = win.hide();
    } else if now_ms().saturating_sub(LAST_BLUR_HIDE_MS.load(Ordering::Relaxed)) > 300 {
        position_panel(win, anchor);
        let _ = win.show();
        let _ = win.set_focus();
    }
    // else: the mouse-down of this very click just blurred-and-hid the panel,
    // so the user meant "close", not "reopen".
}

/// A small colored dot PNG per rolled-up status, swapped on the tray icon.
fn tray_icon(overall: &str) -> Image<'static> {
    let bytes: &[u8] = match overall {
        "running" => include_bytes!("../icons/status/green.png"),
        "waiting_input" => include_bytes!("../icons/status/orange.png"),
        "stopped" => include_bytes!("../icons/status/red.png"),
        _ => include_bytes!("../icons/status/gray.png"),
    };
    Image::from_bytes(bytes).expect("valid tray icon png")
}

fn run_gui() {
    tauri::Builder::default()
        // Single-instance must be registered first: a second launch just
        // re-shows the existing panel instead of spawning a duplicate tray.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(win) = app.get_webview_window("panel") {
                let _ = win.show();
                let _ = win.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_status,
            hook_status,
            install_hook,
            uninstall_hook
        ])
        // Dismiss the flyout when it loses focus (click-away), like a native
        // tray popover.
        .on_window_event(|window, event| {
            if let WindowEvent::Focused(false) = event {
                if window.label() == "panel" && window.is_visible().unwrap_or(false) {
                    let _ = window.hide();
                    LAST_BLUR_HIDE_MS.store(now_ms(), Ordering::Relaxed);
                }
            }
        })
        .setup(|app| {
            let quit = MenuItem::with_id(app, "quit", "Quit Lubby Bar", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&quit])?;

            TrayIconBuilder::with_id("main")
                .icon(tray_icon("idle"))
                .tooltip("Lubby Bar")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| {
                    if event.id.as_ref() == "quit" {
                        app.exit(0);
                    }
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        position,
                        rect,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("panel") {
                            // Prefer the icon's own bounds; fall back to the
                            // cursor, which keyboard activation may not set.
                            let anchor = rect_anchor(app, &rect).or_else(|| {
                                (position.x != 0.0 || position.y != 0.0).then_some(position)
                            });
                            toggle_panel(&win, anchor);
                        }
                    }
                })
                .build(app)?;

            // Reflect the rolled-up status on the tray and nudge the panel to
            // refresh, by polling the status file on a background thread.
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                let mut last = String::new();
                loop {
                    let view = current_status();
                    if view.overall != last {
                        last = view.overall.clone();
                        if let Some(tray) = handle.tray_by_id("main") {
                            let _ = tray.set_icon(Some(tray_icon(&view.overall)));
                            let _ = tray.set_tooltip(Some(format!("Lubby, {}", view.overall)));
                        }
                    }
                    let _ = handle.emit("status-updated", &view);
                    std::thread::sleep(Duration::from_secs(3));
                }
            });

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error building Lubby Bar")
        .run(|_app, event| {
            // Closing the panel keeps the app alive in the tray.
            if let tauri::RunEvent::ExitRequested { api, .. } = event {
                api.prevent_exit();
            }
        });
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("hook") {
        // `lubby-bar.exe hook <event>`: read Claude's stdin JSON and update the
        // status file, then exit. No GUI.
        let event = args.get(2).map(String::as_str).unwrap_or("");
        let mut stdin = String::new();
        let _ = std::io::stdin().read_to_string(&mut stdin);
        lubby_core::run_hook(event, &stdin, &status_path());
        return;
    }
    run_gui();
}
