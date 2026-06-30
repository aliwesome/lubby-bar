// On Windows release builds, don't pop a console window.
#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::io::Read;
use std::time::Duration;

use serde::Serialize;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{Emitter, Manager};

use lubby_core::{aggregate, live_sessions, status_path, Status};

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
    let statuses: Vec<Status> = rows.iter().map(|(_, s)| Status::from_raw(&s.status)).collect();
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
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![get_status])
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
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("panel") {
                            if win.is_visible().unwrap_or(false) {
                                let _ = win.hide();
                            } else {
                                let _ = win.show();
                                let _ = win.set_focus();
                            }
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
