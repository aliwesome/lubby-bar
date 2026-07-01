//! Cross-platform core for the Lubby Bar Windows app: the on-disk status file,
//! the Claude Code hook logic, and status roll-up. Deliberately free of any GUI
//! or platform-window code so it can be unit-tested anywhere (including macOS CI).
//!
//! Mirrors the macOS app's `StatusFile.swift` / `HookCLI.swift`: the same
//! git-repo-aware project names and the same 30-minute staleness prune. One
//! deliberate difference: the file holds only coarse fields (status, agent,
//! project name, timestamp), per the README's privacy promise. The working
//! directory is used transiently to derive the project name, never persisted.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// How long a session can go without an update before it's treated as gone.
pub const STALE_AFTER_SECS: i64 = 30 * 60;

/// The coarse status a session can hold. Matches the strings written to disk.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Running,
    WaitingInput,
    Stopped,
    Idle,
}

impl Status {
    pub fn from_raw(raw: &str) -> Status {
        match raw {
            "running" | "heartbeat" | "started" => Status::Running,
            "waiting_input" | "notification" => Status::WaitingInput,
            "completed" | "failed" | "cancelled" | "stopped" | "stop" => Status::Stopped,
            _ => Status::Idle,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Status::Running => "Running",
            Status::WaitingInput => "Waiting for input",
            Status::Stopped => "Stopped",
            Status::Idle => "Idle",
        }
    }
}

/// Roll many session statuses into one: waiting (needs you) beats running beats
/// stopped beats idle. Same precedence as the macOS app and the server.
pub fn aggregate(statuses: &[Status]) -> Status {
    if statuses.contains(&Status::WaitingInput) {
        Status::WaitingInput
    } else if statuses.contains(&Status::Running) {
        Status::Running
    } else if statuses.contains(&Status::Stopped) {
        Status::Stopped
    } else {
        Status::Idle
    }
}

/// One session row, keyed by Claude session id in the file's `sessions` map.
/// Coarse fields only: no paths, no prompts, nothing beyond what the tray and
/// panel need to render. Unknown fields in files written by older builds (which
/// stored `cwd`/`term_program`) are dropped on the next write.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub status: String,
    pub agent: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    pub updated_at: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StatusFile {
    #[serde(default)]
    pub sessions: BTreeMap<String, Session>,
}

/// `%APPDATA%\lubby-bar` on Windows, the platform config dir elsewhere.
pub fn data_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("lubby-bar")
}

pub fn status_path() -> PathBuf {
    data_dir().join("status.json")
}

pub fn read(path: &Path) -> StatusFile {
    std::fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

pub fn write(path: &Path, file: &StatusFile) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_vec_pretty(file).unwrap_or_else(|_| b"{}".to_vec());
    std::fs::write(path, json)
}

/// Record/refresh one session and prune anything stale, mirroring the Swift
/// `StatusStore.upsert`. The project label is resolved once (on first sight of a
/// session) from the git repo, so the hot path doesn't shell out every event.
pub fn upsert(path: &Path, session_id: &str, status: &str, agent: &str, cwd: Option<&str>) {
    let mut file = read(path);
    let now = Utc::now();

    // `cwd` is used here once to derive a display name and then discarded; the
    // raw path never reaches the file.
    let existing = file.sessions.get(session_id).cloned();
    let project = existing
        .as_ref()
        .and_then(|s| s.project.clone())
        .or_else(|| cwd.and_then(project_name));

    file.sessions.insert(
        session_id.to_string(),
        Session {
            status: status.to_string(),
            agent: agent.to_string(),
            project,
            updated_at: now.to_rfc3339(),
        },
    );

    file.sessions.retain(|_, s| !is_stale(&s.updated_at, now));
    let _ = write(path, &file);
}

/// Sessions that are still fresh enough to show, newest first.
pub fn live_sessions(path: &Path) -> Vec<(String, Session)> {
    let file = read(path);
    let now = Utc::now();
    let mut rows: Vec<(String, Session)> = file
        .sessions
        .into_iter()
        .filter(|(_, s)| !is_stale(&s.updated_at, now))
        .collect();
    // Stable order by project then id, so rows don't jump around as they tick.
    rows.sort_by(|a, b| {
        let pa = a.1.project.clone().unwrap_or_default().to_lowercase();
        let pb = b.1.project.clone().unwrap_or_default().to_lowercase();
        pa.cmp(&pb).then(a.0.cmp(&b.0))
    });
    rows
}

fn is_stale(updated_at: &str, now: DateTime<Utc>) -> bool {
    match DateTime::parse_from_rfc3339(updated_at) {
        Ok(t) => {
            now.signed_duration_since(t.with_timezone(&Utc))
                .num_seconds()
                > STALE_AFTER_SECS
        }
        Err(_) => true,
    }
}

/// A readable, distinguishable project label: the git repo folder at a repo root
/// ("lubby"), "repo/leaf" inside a subdir ("lubby/web"), else the cwd's folder.
pub fn project_name(cwd: &str) -> Option<String> {
    let leaf = Path::new(cwd).file_name()?.to_string_lossy().to_string();
    match git_root(cwd) {
        Some(root) => {
            let repo = Path::new(&root)
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| leaf.clone());
            let at_root = same_path(&root, cwd);
            Some(if at_root {
                repo
            } else {
                format!("{repo}/{leaf}")
            })
        }
        None => Some(leaf),
    }
}

fn git_root(cwd: &str) -> Option<String> {
    let out = Command::new("git")
        .args(["-C", cwd, "rev-parse", "--show-toplevel"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let root = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if root.is_empty() {
        None
    } else {
        Some(root)
    }
}

fn same_path(a: &str, b: &str) -> bool {
    let norm = |p: &str| std::fs::canonicalize(p).unwrap_or_else(|_| PathBuf::from(p));
    norm(a) == norm(b)
}

// ---------------------------------------------------------------------------
// Hook CLI
// ---------------------------------------------------------------------------

/// Map a Claude Code hook event name to a status string.
pub fn status_for_event(event: &str) -> &'static str {
    match event {
        "started" | "running" | "heartbeat" => "running",
        "waiting_input" | "notification" => "waiting_input",
        "completed" | "stop" | "stopped" | "end" => "completed",
        _ => "running",
    }
}

/// Run the `hook <event>` subcommand: read the small JSON Claude pipes on stdin
/// (`session_id`, `cwd` only), and upsert the status file. Never touches the
/// transcript, prompt, or file contents; `cwd` is only used to derive the
/// project name and is not written to disk.
pub fn run_hook(event: &str, stdin_json: &str, path: &Path) {
    let mut session_id = "default".to_string();
    let mut cwd: Option<String> = None;

    if let Ok(value) = serde_json::from_str::<serde_json::Value>(stdin_json) {
        if let Some(sid) = value.get("session_id").and_then(|v| v.as_str()) {
            if !sid.is_empty() {
                session_id = sid.to_string();
            }
        }
        if let Some(dir) = value.get("cwd").and_then(|v| v.as_str()) {
            if !dir.is_empty() {
                cwd = Some(dir.to_string());
            }
        }
    }

    upsert(
        path,
        &session_id,
        status_for_event(event),
        "claude_code",
        cwd.as_deref(),
    );
}

// ---------------------------------------------------------------------------
// Claude hook installation
//
// Registers `lubby-bar.exe hook <event>` in ~/.claude/settings.json so Claude
// Code drives the status file. Mirrors the macOS `HookInstaller`: idempotent,
// preserves any hooks the user already has, and identifies its own entries by a
// marker so reinstall replaces in place and uninstall can remove them cleanly.
// ---------------------------------------------------------------------------

/// Path to `~/.claude/settings.json`, where Claude Code reads hook registrations.
pub fn claude_settings_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".claude")
        .join("settings.json")
}

/// The Claude hook events we register, and the status arg each passes to
/// `lubby-bar.exe hook <arg>`. SessionStart/UserPromptSubmit/PreToolUse mark the
/// agent as working; Notification means it needs you; Stop/SessionEnd end it.
pub const HOOK_EVENTS: &[(&str, &str)] = &[
    ("SessionStart", "started"),
    ("UserPromptSubmit", "running"),
    ("PreToolUse", "running"),
    ("Notification", "waiting_input"),
    ("Stop", "completed"),
    ("SessionEnd", "end"),
];

/// The command string for one hook arg, with the exe path quoted so spaces in
/// `C:\Program Files\...` survive the shell.
fn hook_command(exe: &str, arg: &str) -> String {
    format!("\"{exe}\" hook {arg}")
}

/// Whether a command string is one of ours, so reinstall replaces it and
/// uninstall finds it. Keyed on the exe stem plus the ` hook ` marker.
fn is_our_command(cmd: &str) -> bool {
    let lower = cmd.to_lowercase();
    lower.contains("lubby-bar") && lower.contains(" hook ")
}

/// Whether a hook *group* (`{ "hooks": [ { command } ] }`) contains our command.
fn group_is_ours(group: &Value) -> bool {
    group
        .get("hooks")
        .and_then(|h| h.as_array())
        .map(|inner| {
            inner.iter().any(|h| {
                h.get("command")
                    .and_then(|c| c.as_str())
                    .map(is_our_command)
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

fn read_json(path: &Path) -> Value {
    std::fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_else(|| json!({}))
}

fn write_json(path: &Path, value: &Value) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_vec_pretty(value).unwrap_or_else(|_| b"{}".to_vec());
    std::fs::write(path, json)
}

/// Register our hooks, preserving everything else in settings.json. Idempotent:
/// existing Lubby entries are replaced, never duplicated.
pub fn install_hook(exe: &str, settings_path: &Path) -> std::io::Result<()> {
    let mut root = read_json(settings_path);
    if !root.is_object() {
        root = json!({});
    }
    let obj = root.as_object_mut().expect("root is an object");
    let hooks = obj.entry("hooks").or_insert_with(|| json!({}));
    if !hooks.is_object() {
        *hooks = json!({});
    }
    let hooks = hooks.as_object_mut().expect("hooks is an object");

    for &(event, arg) in HOOK_EVENTS {
        let groups = hooks.entry(event).or_insert_with(|| json!([]));
        if !groups.is_array() {
            *groups = json!([]);
        }
        let arr = groups.as_array_mut().expect("event holds an array");
        arr.retain(|g| !group_is_ours(g)); // drop our prior entry, keep the user's
        arr.push(json!({
            "hooks": [ { "type": "command", "command": hook_command(exe, arg) } ]
        }));
    }

    write_json(settings_path, &root)
}

/// Remove our hooks, dropping any event array we leave empty, and leaving the
/// user's own hooks untouched.
pub fn uninstall_hook(settings_path: &Path) -> std::io::Result<()> {
    let mut root = read_json(settings_path);
    if let Some(hooks) = root.get_mut("hooks").and_then(|h| h.as_object_mut()) {
        for groups in hooks.values_mut() {
            if let Some(arr) = groups.as_array_mut() {
                arr.retain(|g| !group_is_ours(g));
            }
        }
        hooks.retain(|_, groups| groups.as_array().map(|a| !a.is_empty()).unwrap_or(true));
    }
    write_json(settings_path, &root)
}

/// Whether our hooks are currently registered in settings.json.
pub fn hook_installed(settings_path: &Path) -> bool {
    read_json(settings_path)
        .get("hooks")
        .and_then(|h| h.as_object())
        .map(|hooks| {
            hooks.values().any(|groups| {
                groups
                    .as_array()
                    .map(|a| a.iter().any(group_is_ours))
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_path() -> PathBuf {
        let mut p = std::env::temp_dir();
        let n = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        p.push(format!("lubby-core-test-{n}.json"));
        p
    }

    #[test]
    fn aggregate_precedence() {
        assert_eq!(
            aggregate(&[Status::Running, Status::WaitingInput]),
            Status::WaitingInput
        );
        assert_eq!(
            aggregate(&[Status::Running, Status::Stopped]),
            Status::Running
        );
        assert_eq!(aggregate(&[Status::Stopped]), Status::Stopped);
        assert_eq!(aggregate(&[]), Status::Idle);
    }

    #[test]
    fn event_mapping() {
        assert_eq!(status_for_event("started"), "running");
        assert_eq!(status_for_event("notification"), "waiting_input");
        assert_eq!(status_for_event("stop"), "completed");
    }

    #[test]
    fn hook_writes_status_and_project() {
        let path = temp_path();
        // cwd = this crate dir (a git repo), so project resolves to the repo name.
        let cwd = env!("CARGO_MANIFEST_DIR");
        let stdin = format!(
            r#"{{"session_id":"s1","cwd":"{}"}}"#,
            cwd.replace('\\', "\\\\")
        );

        run_hook("started", &stdin, &path);
        let live = live_sessions(&path);
        assert_eq!(live.len(), 1);
        assert_eq!(live[0].1.status, "running");
        assert!(live[0].1.project.is_some());

        run_hook("notification", &stdin, &path);
        let live = live_sessions(&path);
        assert_eq!(live[0].1.status, "waiting_input");

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn status_file_holds_only_coarse_fields() {
        // The README promises the status file records only a coarse status, the
        // agent name, and the project name. In particular the cwd passed by the
        // hook must inform the project label but never be written to disk.
        let path = temp_path();
        let cwd = env!("CARGO_MANIFEST_DIR");
        let stdin = format!(
            r#"{{"session_id":"s1","cwd":"{}"}}"#,
            cwd.replace('\\', "\\\\")
        );
        run_hook("started", &stdin, &path);

        let raw: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        let session = &raw["sessions"]["s1"];
        let keys: Vec<&str> = session
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        for key in &keys {
            assert!(
                ["status", "agent", "project", "updated_at"].contains(key),
                "unexpected field persisted: {key}"
            );
        }
        assert!(!raw.to_string().contains(&cwd.replace('\\', "\\\\")));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn stale_sessions_are_pruned() {
        let path = temp_path();
        let old = (Utc::now() - chrono::Duration::seconds(STALE_AFTER_SECS + 60)).to_rfc3339();
        let mut file = StatusFile::default();
        file.sessions.insert(
            "old".into(),
            Session {
                status: "running".into(),
                agent: "claude_code".into(),
                project: Some("ghost".into()),
                updated_at: old,
            },
        );
        write(&path, &file).unwrap();

        // Any upsert prunes stale rows; the fresh one survives.
        upsert(&path, "fresh", "running", "claude_code", None);
        let live = live_sessions(&path);
        assert_eq!(live.len(), 1);
        assert_eq!(live[0].0, "fresh");

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn project_name_uses_repo_then_leaf() {
        // The crate dir is .../lubby-bar/windows/core -> repo "lubby-bar", and
        // since it's a subdir, "lubby-bar/core".
        let name = project_name(env!("CARGO_MANIFEST_DIR")).unwrap();
        assert!(name.contains("lubby-bar"), "got {name}");
    }

    #[test]
    fn hook_install_is_idempotent_and_preserves_user_hooks() {
        let path = temp_path();
        // A pre-existing unrelated hook and an unrelated top-level key.
        let pre = json!({
            "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "echo bye" } ] } ] },
            "statusLine": { "type": "command", "command": "node x.mjs" }
        });
        write_json(&path, &pre).unwrap();

        let exe = "C:\\Program Files\\Lubby Bar\\lubby-bar.exe";
        install_hook(exe, &path).unwrap();
        install_hook(exe, &path).unwrap(); // reinstall must not duplicate

        assert!(hook_installed(&path));
        let root = read_json(&path);

        // Stop now holds exactly one of ours plus the user's untouched echo.
        let stop = root["hooks"]["Stop"].as_array().unwrap();
        assert_eq!(stop.iter().filter(|g| group_is_ours(g)).count(), 1);
        assert!(stop.iter().any(|g| !group_is_ours(g)));
        // Quoted exe path made it into the command verbatim.
        assert!(serde_json::to_string(&root)
            .unwrap()
            .contains("\\\"C:\\\\Program Files"));
        // Unrelated top-level key preserved.
        assert_eq!(root["statusLine"]["command"], "node x.mjs");

        uninstall_hook(&path).unwrap();
        assert!(!hook_installed(&path));
        // Our removal leaves the user's Stop hook in place.
        let root = read_json(&path);
        let stop = root["hooks"]["Stop"].as_array().unwrap();
        assert_eq!(stop.len(), 1);
        assert!(!group_is_ours(&stop[0]));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn hook_install_into_empty_settings() {
        let path = temp_path();
        let _ = std::fs::remove_file(&path); // ensure absent
        assert!(!hook_installed(&path));
        install_hook("/usr/local/bin/lubby-bar", &path).unwrap();
        assert!(hook_installed(&path));
        // Every configured event got registered.
        let root = read_json(&path);
        for (event, _) in HOOK_EVENTS {
            assert!(root["hooks"][event].is_array(), "missing {event}");
        }
        let _ = std::fs::remove_file(&path);
    }
}
