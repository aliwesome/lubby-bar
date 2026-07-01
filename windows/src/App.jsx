import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { useEffect, useState } from 'react';

const COLORS = {
    running: '#34C759',
    waiting_input: '#FF9F0A',
    stopped: '#FF453A',
    idle: '#8E8E93',
};
const LABEL = {
    running: 'Running',
    waiting_input: 'Waiting for input',
    stopped: 'Stopped',
    idle: 'Idle',
};
const CHIP = { running: 'RUN', waiting_input: 'WAIT', stopped: 'STOP', idle: 'IDLE' };

export default function App() {
    const [data, setData] = useState({ overall: 'idle', sessions: [] });
    // Assume installed until the first check resolves, so the CTA never flashes.
    const [hookInstalled, setHookInstalled] = useState(true);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState(null);

    useEffect(() => {
        const refresh = () => invoke('get_status').then(setData).catch(() => {});
        refresh();
        invoke('hook_status').then(setHookInstalled).catch(() => {});

        const id = setInterval(refresh, 4000);
        const unlisten = listen('status-updated', (e) => setData(e.payload));
        return () => {
            clearInterval(id);
            unlisten.then((u) => u());
        };
    }, []);

    const runHook = async (command) => {
        setBusy(true);
        setError(null);
        try {
            setHookInstalled(await invoke(command));
        } catch (e) {
            setError(String(e));
        } finally {
            setBusy(false);
        }
    };

    const color = COLORS[data.overall] ?? COLORS.idle;
    const sessions = data.sessions ?? [];

    return (
        <div className="panel">
            <header className="header">
                <span className="brand-dot" />
                <span className="brand">Lubby</span>
                <span className="tab active">Sessions</span>
            </header>

            <div className="hero">
                <span
                    className="badge"
                    style={{ background: `${color}26`, boxShadow: `0 0 22px ${color}55` }}
                >
                    <span className="dot lg" style={{ background: color }} />
                </span>
                <div className="hero-title">{LABEL[data.overall] ?? 'Idle'}</div>
                <div className="hero-sub">
                    this device · {sessions.length}{' '}
                    {sessions.length === 1 ? 'session' : 'sessions'}
                </div>
            </div>

            <div className="rows">
                {sessions.length === 0 ? (
                    hookInstalled ? (
                        <div className="empty">No active Claude sessions</div>
                    ) : (
                        <div className="cta">
                            <div className="cta-title">Connect Claude Code</div>
                            <div className="cta-sub">
                                Install a local hook so Lubby can show what your agents are
                                doing. Nothing ever leaves this machine.
                            </div>
                            <button
                                className="btn primary"
                                disabled={busy}
                                onClick={() => runHook('install_hook')}
                            >
                                {busy ? 'Installing…' : 'Install hook'}
                            </button>
                        </div>
                    )
                ) : (
                    sessions.map((s) => {
                        const c = COLORS[s.status] ?? COLORS.idle;
                        return (
                            <div className="row" key={s.id}>
                                <span className="dot" style={{ background: c }} />
                                <span className="name">{s.project || s.agent}</span>
                                <span
                                    className="chip"
                                    style={{ color: c, background: `${c}26` }}
                                >
                                    {CHIP[s.status] ?? 'IDLE'}
                                </span>
                            </div>
                        );
                    })
                )}
            </div>

            {error && <div className="err">{error}</div>}

            {hookInstalled && (
                <footer className="footer">
                    <span className="hook-ok">
                        <span className="dot" style={{ background: '#34C759' }} />
                        Hook installed
                    </span>
                    <button
                        className="btn ghost"
                        disabled={busy}
                        onClick={() => runHook('uninstall_hook')}
                    >
                        Remove
                    </button>
                </footer>
            )}
        </div>
    );
}
